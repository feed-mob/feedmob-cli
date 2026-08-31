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

        def request(method:, path:, token:, **options)
          validate_path!(path)
          raw = @transport.request(**transport_request(method:, path:, token:, options:))
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

        def transport_request(method:, path:, token:, options:)
          json = options.fetch(:json, nil)
          body = options.fetch(:body, nil)
          if !json.nil? && !body.nil?
            raise Error.new(code: 'invalid_request', message: 'Specify either json or body, not both.')
          end

          headers = default_headers(token).merge(options.fetch(:headers, {}))
          body = JSON.generate(json).tap { headers['Content-Type'] = 'application/json' } unless json.nil?
          request = { method: method.to_sym, url: "#{@service.base_url}#{path}", headers: }
          request[:body] = body unless body.nil?
          request
        end

        def default_headers(token)
          { 'Accept' => 'application/json', 'Authorization' => "Bearer #{token}" }
        end

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
          code, message = api_error(data, status)
          raise Error.new(code: code.to_s, message:, details: { status: })
        end

        def api_error(data, status)
          remote_error = data['error'] if data.is_a?(Hash)
          if remote_error.is_a?(Hash)
            [remote_error['code'] || 'http_error', remote_error['message'] || default_api_error(status)]
          else
            [data_code(data), data_message(data, remote_error, status)]
          end
        end

        def data_code(data)
          data.is_a?(Hash) ? data['code'] || 'http_error' : 'http_error'
        end

        def data_message(data, remote_error, status)
          return remote_error if remote_error.is_a?(String)
          return default_api_error(status) unless data.is_a?(Hash)

          data['message'] || data['msg'] || default_api_error(status)
        end

        def default_api_error(status)
          "#{@service.label} API returned HTTP #{status}."
        end
      end
    end
  end
end
