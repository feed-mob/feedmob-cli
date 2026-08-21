# frozen_string_literal: true

require 'uri'
require_relative 'error'
require_relative 'service'

module FeedMob
  module CLI
    module Services
      DEFINITIONS = {
        'pixel' => {
          label: 'Pixel',
          base_url: 'https://feedmob-pixel-dashboard.feedmob.com/rails',
          base_url_env: 'FEEDMOB_PIXEL_BASE_URL',
          token_env: 'FEEDMOB_PIXEL_TOKEN',
          token_prefix: 'fmpat_',
          identity_path: '/api/v1/cli/me',
          revoke_path: '/api/v1/cli/token',
          keychain_service: 'com.feedmob.fm.pixel'
        },
        'time-off' => {
          label: 'Time Off',
          base_url: 'https://time-off.feedmob.com',
          base_url_env: 'FEEDMOB_TIME_OFF_BASE_URL',
          token_env: 'FEEDMOB_TIME_OFF_TOKEN',
          token_prefix: 'fmtopat_',
          identity_path: '/api/v1/me',
          revoke_path: nil,
          keychain_service: 'com.feedmob.fm.time-off'
        }
      }.freeze

      module_function

      def fetch(name, env: ENV)
        definition = DEFINITIONS[name.to_s]
        raise Error.new(code: 'unknown_service', message: "Unknown FeedMob service: #{name}") unless definition

        base_url_env = definition.fetch(:base_url_env)
        configured_url = env.fetch(base_url_env, definition.fetch(:base_url))
        Service.new(
          name: name.to_s,
          label: definition.fetch(:label),
          base_url: normalize_base_url(configured_url, base_url_env, env),
          token_env: definition.fetch(:token_env),
          token_prefix: definition.fetch(:token_prefix),
          identity_path: definition.fetch(:identity_path),
          revoke_path: definition.fetch(:revoke_path),
          keychain_service: definition.fetch(:keychain_service)
        )
      end

      def all(env: ENV)
        DEFINITIONS.keys.map { |name| fetch(name, env:) }
      end

      def normalize_base_url(value, variable_name, env)
        normalized = value.to_s.strip.sub(%r{/+\z}, '')
        uri = URI.parse(normalized)
        validate_base_url!(uri, variable_name)
        validate_base_url_scheme!(uri, variable_name, env)
        normalized
      rescue URI::InvalidURIError
        raise Error.new(
          code: 'invalid_base_url',
          message: base_url_error_message(variable_name, false)
        )
      end

      def validate_base_url!(uri, variable_name)
        return if valid_base_url?(uri)

        raise Error.new(code: 'invalid_base_url', message: base_url_error_message(variable_name, false))
      end

      def valid_base_url?(uri)
        uri.is_a?(URI::HTTP) && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      end

      def validate_base_url_scheme!(uri, variable_name, env)
        return if uri.scheme == 'https' || allowed_insecure_local_url?(uri, env)

        raise Error.new(code: 'insecure_base_url', message: base_url_error_message(variable_name, true))
      end

      def allowed_insecure_local_url?(uri, env)
        uri.scheme == 'http' && loopback_host?(uri.host) && env['FEEDMOB_ALLOW_INSECURE_HTTP'] == '1'
      end

      def loopback_host?(host)
        %w[localhost 127.0.0.1 ::1].include?(host.delete_prefix('[').delete_suffix(']'))
      end

      def base_url_error_message(variable_name, valid)
        return "#{variable_name} must be an http(s) URL without credentials, query, or fragment." unless valid

        "#{variable_name} must use HTTPS. HTTP is only allowed for loopback hosts when FEEDMOB_ALLOW_INSECURE_HTTP=1."
      end
    end
  end
end
