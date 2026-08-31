# frozen_string_literal: true

require 'net/http'
require 'uri'

module FeedMob
  module CLI
    module HTTP
      class NetHTTPTransport
        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 30

        def request(method:, url:, headers:, body: nil)
          uri = URI.parse(url)
          request = request_class(method).new(uri, headers)
          request.body = body unless body.nil?
          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == 'https',
            open_timeout: OPEN_TIMEOUT,
            read_timeout: READ_TIMEOUT
          ) { |http| http.request(request) }

          {
            status: response.code.to_i,
            headers: response.each_header.to_h,
            body: response.body.to_s
          }
        end

        private

        def request_class(method)
          case method.to_sym
          when :get then Net::HTTP::Get
          when :post then Net::HTTP::Post
          when :put then Net::HTTP::Put
          when :delete then Net::HTTP::Delete
          else
            raise Error.new(code: 'unsupported_method', message: "Unsupported HTTP method: #{method}")
          end
        end
      end
    end
  end
end
