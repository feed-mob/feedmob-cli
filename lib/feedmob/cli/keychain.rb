# frozen_string_literal: true

require 'open3'
require 'fiddle/import'
require_relative 'error'

module FeedMob
  module CLI
    class Keychain
      Result = Data.define(:stdout, :stderr, :success?)

      def initialize(platform: RUBY_PLATFORM, runner: CommandRunner.new, native_writer: nil)
        @platform = platform
        @runner = runner
        @native_writer = native_writer
      end

      def read(service)
        return nil unless macos?

        result = @runner.call(
          ['/usr/bin/security', 'find-generic-password', '-a', 'fm', '-s', service.keychain_service, '-w']
        )
        return result.stdout.strip if result.success?
        return nil if result.stderr.include?('could not be found')

        raise Error.new(code: 'keychain_error',
                        message: "Could not read the #{service.label} credential from macOS Keychain.")
      end

      def write(service, token)
        ensure_macos!(service)
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
        return false unless macos?

        result = @runner.call(
          ['/usr/bin/security', 'delete-generic-password', '-a', 'fm', '-s', service.keychain_service]
        )
        return true if result.success?
        return false if result.stderr.include?('could not be found')

        raise Error.new(code: 'keychain_error',
                        message: "Could not delete the #{service.label} credential from macOS Keychain.")
      end

      private

      def macos?
        @platform.include?('darwin')
      end

      def ensure_macos!(service)
        return if macos?

        raise Error.new(
          code: 'keychain_unavailable',
          message: "macOS Keychain is unavailable. Set #{service.token_env} instead."
        )
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
