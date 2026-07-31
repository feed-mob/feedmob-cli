# frozen_string_literal: true

require 'json'
require 'openssl'
require 'uri'
require_relative '../error'
require_relative 'net_http_transport'
require_relative 'response'

module FeedMob
  module CLI
    module HTTP
      class Client
        def initialize(service:, transport: NetHTTPTransport.new)
          @service = service
          @transport = transport
        end

        def request(method:, path:, token:)
          validate_path!(path)
          raw = @transport.request(
            method: method.to_sym,
            url: "#{@service.base_url}#{path}",
            headers: {
              'Accept' => 'application/json',
              'Authorization' => "Bearer #{token}"
            }
          )
          data = parse_body(raw.fetch(:body))
          raise_api_error!(raw.fetch(:status), data) unless (200..299).cover?(raw.fetch(:status))

          Response.new(status: raw.fetch(:status), headers: raw.fetch(:headers), data:)
        rescue Error
          raise
        rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
          raise Error.new(
            code: 'network_error',
            message: "Could not reach #{@service.label}: #{e.class.name}."
          )
        end

        private

        def validate_path!(path)
          value = path.to_s
          uri = URI.parse(value)
          valid = value.start_with?('/') && !value.start_with?('//') && uri.scheme.nil? && uri.host.nil?
          return if valid

          raise Error.new(
            code: 'invalid_path',
            message: 'Request path must start with one slash and stay on the configured service host.'
          )
        rescue URI::InvalidURIError
          raise Error.new(code: 'invalid_path', message: 'Request path is not a valid relative URL.')
        end

        def parse_body(body)
          return nil if body.empty?

          JSON.parse(body)
        rescue JSON::ParserError
          body
        end

        def raise_api_error!(status, data)
          remote_error = data.is_a?(Hash) ? data['error'] : nil
          if remote_error.is_a?(Hash)
            code = remote_error['code'] || 'http_error'
            message = remote_error['message'] || "#{@service.label} API returned HTTP #{status}."
          else
            code = 'http_error'
            message = remote_error.is_a?(String) ? remote_error : "#{@service.label} API returned HTTP #{status}."
          end

          raise Error.new(code:, message:, details: { status: })
        end
      end
    end
  end
end
