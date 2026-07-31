# frozen_string_literal: true

require 'open3'
require_relative 'error'

module FeedMob
  module CLI
    class Keychain
      Result = Data.define(:stdout, :stderr, :success?)

      def initialize(platform: RUBY_PLATFORM, runner: CommandRunner.new)
        @platform = platform
        @runner = runner
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
        result = @runner.call(
          [
            '/usr/bin/security', 'add-generic-password', '-U', '-a', 'fm', '-s', service.keychain_service,
            '-w'
          ],
          stdin_data: "#{token}\n"
        )
        return true if result.success?

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

      class CommandRunner
        def call(argv, stdin_data: nil)
          stdout, stderr, status = Open3.capture3(*argv, stdin_data:)
          Result.new(stdout:, stderr:, success?: status.success?)
        end
      end
    end
  end
end
