# frozen_string_literal: true

require_relative 'error'
require_relative 'keychain'

module FeedMob
  module CLI
    Credential = Data.define(:value, :source)

    class Credentials
      def initialize(env: ENV, keychain: Keychain.new)
        @env = env
        @keychain = keychain
      end

      def resolve(service)
        environment_value = @env[service.token_env].to_s.strip
        return credential(environment_value, 'env', service) unless environment_value.empty?

        keychain_value = @keychain.read(service).to_s.strip
        return credential(keychain_value, 'keychain', service) unless keychain_value.empty?

        Credential.new(value: nil, source: 'missing')
      end

      def store(service, token)
        validate_token!(service, token)
        @keychain.write(service, token)
      end

      def delete(service)
        @keychain.delete(service)
      end

      def validate_token!(service, token)
        return if token.to_s.start_with?(service.token_prefix)

        raise Error.new(
          code: 'invalid_token_format',
          message: "The #{service.label} credential does not use the expected #{service.token_prefix} prefix."
        )
      end

      private

      def credential(value, source, service)
        validate_token!(service, value)
        Credential.new(value:, source:)
      end
    end
  end
end
