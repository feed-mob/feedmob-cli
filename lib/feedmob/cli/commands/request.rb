# frozen_string_literal: true

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
