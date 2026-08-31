# frozen_string_literal: true

require 'json'
require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class RequestGet < Base
        desc 'Perform an authenticated GET request against a service API'
        argument :path, required: true, desc: 'API path beginning with /'

        def call(path:, **)
          credential = credential!(service)
          response = runtime.client(service).request(method: :get, path:, token: credential.value)

          output.success(
            {
              service: service.name,
              status: response.status,
              response: response.data
            },
            message: "GET #{path} returned HTTP #{response.status}."
          )
        end
      end

      class PixelRequestGet < RequestGet
        desc 'Perform an authenticated GET request against the Pixel API'

        def service_name = 'pixel'
      end

      class TimeOffRequestGet < RequestGet
        desc 'Perform an authenticated GET request against the Time Off API'

        def service_name = 'time-off'
      end

      class TimeOffRequestPut < TimeOffRequestGet
        desc 'Perform an authenticated PUT request against the Time Off API'
        option :json_file, type: :string, desc: 'Required JSON request-body file'

        def call(path:, json_file: nil, **)
          body = json_payload(json_file)
          credential = credential!(service)
          response = runtime.client(service).request(method: :put, path:, token: credential.value, json: body)

          output.success(
            {
              service: service.name,
              status: response.status,
              response: response.data
            },
            message: "PUT #{path} returned HTTP #{response.status}."
          )
        end

        private

        def json_payload(path)
          file = path.to_s
          unless !file.empty? && File.file?(file)
            raise Error.new(code: 'invalid_input', message: 'json_file must name a readable file.')
          end

          JSON.parse(File.binread(file))
        rescue Errno::EACCES
          raise Error.new(code: 'invalid_input', message: 'json_file cannot be read.')
        rescue JSON::ParserError
          raise Error.new(code: 'invalid_input', message: 'json_file must contain valid JSON.')
        end
      end

      class FeminiRequestGet < RequestGet
        desc 'Perform an authenticated GET request against the Femini API'

        def service_name = 'femini'
      end

      class PagesRequestGet < RequestGet
        desc 'Perform an authenticated GET request against the Pages API'

        def service_name = 'pages'
      end
    end
  end
end
