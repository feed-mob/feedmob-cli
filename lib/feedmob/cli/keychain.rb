# frozen_string_literal: true

require 'fiddle/import'
require 'open3'
require_relative 'encrypted_store'
require_relative 'error'

module FeedMob
  module CLI
    class Keychain
      Result = Data.define(:stdout, :stderr, :success?)

      def initialize(platform: RUBY_PLATFORM, runner: CommandRunner.new, native_reader: nil, native_writer: nil,
                     fallback_store: nil)
        @platform = platform
        @runner = runner
        @native_reader = native_reader
        @native_writer = native_writer
        @fallback_store = fallback_store || EncryptedStore.new(platform:)
      end

      def read(service)
        return @fallback_store.read(service) unless macos?

        result = (@native_reader || NativeReader.new).read(account: 'fm', service: service.keychain_service)
        return result.password if result.status == NativeReader::SUCCESS
        return nil if result.status == NativeReader::ITEM_NOT_FOUND

        error_code = result.status == NativeReader::AUTH_FAILED ? 'keychain_auth_failed' : 'keychain_error'
        raise Error.new(code: error_code,
                        message: "Could not read the #{service.label} credential from macOS Keychain.")
      end

      def write(service, token)
        return @fallback_store.write(service, token) unless macos?

        written = (@native_writer || NativeWriter.new).write(
          account: 'fm',
          service: service.keychain_service,
          password: token
        )
        return true if written

        raise Error.new(code: 'keychain_error',
                        message: "Could not save the #{service.label} credential to macOS Keychain.")
      end

      def delete(service)
        return @fallback_store.delete(service) unless macos?

        result = @runner.call(
          ['/usr/bin/security', 'delete-generic-password', '-a', 'fm', '-s', service.keychain_service]
        )
        return true if result.success?
        return false if result.stderr.include?('could not be found')

        raise Error.new(code: 'keychain_error',
                        message: "Could not delete the #{service.label} credential from macOS Keychain.")
      end

      def storage_source
        macos? ? 'keychain' : 'encrypted_file'
      end

      def storage_label
        macos? ? 'macOS Keychain' : 'encrypted local credential store'
      end

      private

      def macos?
        @platform.include?('darwin')
      end

      class NativeReader
        Result = Data.define(:status, :password)

        SUCCESS = 0
        ITEM_NOT_FOUND = -25_300
        AUTH_FAILED = -25_293

        def initialize(api: nil)
          @api = api || SecurityFramework.new
        end

        def read(account:, service:)
          status, password, item = @api.read_generic_password(account:, service:)
          Result.new(status:, password:)
        ensure
          @api.release(item) if defined?(item) && item
        end
      end

      class NativeWriter
        SUCCESS = 0
        DUPLICATE_ITEM = -25_299

        def initialize(api: nil)
          @api = api || SecurityFramework.new
        end

        def write(account:, service:, password:)
          status = @api.add_generic_password(account:, service:, password:)
          return true if status == SUCCESS
          return false unless status == DUPLICATE_ITEM

          find_status, item = @api.find_generic_password(account:, service:)
          return false unless find_status == SUCCESS

          @api.modify_item(item, password:) == SUCCESS
        ensure
          @api.release(item) if defined?(item) && item
        end
      end

      class SecurityFramework
        SECURITY_LIBRARY = '/System/Library/Frameworks/Security.framework/Security'
        CORE_FOUNDATION_LIBRARY = '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'

        def initialize(functions: nil)
          @functions = functions || self.class.functions
        end

        def add_generic_password(account:, service:, password:)
          @functions.SecKeychainAddGenericPassword(
            nil,
            service.bytesize, service,
            account.bytesize, account,
            password.bytesize, password,
            nil
          )
        end

        def find_generic_password(account:, service:)
          item_output = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          item_output[0, Fiddle::SIZEOF_VOIDP] = [0].pack('J')
          status = @functions.SecKeychainFindGenericPassword(
            nil,
            service.bytesize, service,
            account.bytesize, account,
            nil, nil,
            item_output
          )
          item_address = item_output[0, Fiddle::SIZEOF_VOIDP].unpack1('J')
          item = Fiddle::Pointer.new(item_address) unless item_address.zero?
          [status, item]
        end

        def read_generic_password(account:, service:)
          password_address = 0
          password_length_output = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT)
          password_length_output[0, Fiddle::SIZEOF_INT] = [0].pack('I')
          password_output = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          password_output[0, Fiddle::SIZEOF_VOIDP] = [0].pack('J')
          item_output = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          item_output[0, Fiddle::SIZEOF_VOIDP] = [0].pack('J')
          status = @functions.SecKeychainFindGenericPassword(
            nil,
            service.bytesize, service,
            account.bytesize, account,
            password_length_output, password_output,
            item_output
          )
          password_address = password_output[0, Fiddle::SIZEOF_VOIDP].unpack1('J')
          item_address = item_output[0, Fiddle::SIZEOF_VOIDP].unpack1('J')
          password_length = password_length_output[0, Fiddle::SIZEOF_INT].unpack1('I')
          password = Fiddle::Pointer.new(password_address)[0, password_length] unless password_address.zero?
          item = Fiddle::Pointer.new(item_address) unless item_address.zero?
          [status, password, item]
        ensure
          unless password_address.zero?
            @functions.SecKeychainItemFreeContent(nil, Fiddle::Pointer.new(password_address))
          end
        end

        def modify_item(item, password:)
          @functions.SecKeychainItemModifyAttributesAndData(item, nil, password.bytesize, password)
        end

        def release(item)
          @functions.CFRelease(item)
        end

        class << self
          def functions
            @functions ||= Module.new do
              extend Fiddle::Importer

              dlload SECURITY_LIBRARY, CORE_FOUNDATION_LIBRARY
              extern 'int SecKeychainAddGenericPassword(void *, unsigned int, const char *, unsigned int, ' \
                     'const char *, unsigned int, const void *, void *)'
              extern 'int SecKeychainFindGenericPassword(void *, unsigned int, const char *, unsigned int, ' \
                     'const char *, void *, void *, void *)'
              extern 'int SecKeychainItemFreeContent(void *, void *)'
              extern 'int SecKeychainItemModifyAttributesAndData(void *, void *, unsigned int, const void *)'
              extern 'void CFRelease(void *)'
            end
          end
        end
      end

      class CommandRunner
        def call(argv, stdin_data: nil)
          stdout, stderr, status = Open3.capture3(*argv, stdin_data:)
          Result.new(stdout:, stderr:, success?: status.success?)
        end
      end
    end
  end
end
