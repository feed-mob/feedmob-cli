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
        option :raw, type: :boolean, default: false, desc: 'Write the response body verbatim (incompatible with --json)'

        def call(path:, raw: false, **)
          validate_pixel_request!(path, raw)
          return super(path:) unless raw

          credential = credential!(service)
          response = runtime.client(service).request(method: :get, path:, token: credential.value, raw: true)
          (@out || $stdout).write(response.data)
        end

        private

        def validate_pixel_request!(path, raw)
          if raw && FeedMob::CLI.json?
            raise Error.new(code: 'invalid_input', message: '--raw cannot be combined with --json.')
          end
          return unless URI.parse(service.base_url).path == '/rails' && path.match?(%r{\A/rails(?:/|\?|$)})

          raise Error.new(code: 'invalid_path',
                          message: 'Pixel base URL already includes /rails; use /api/v1/... paths.')
        end

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

      class WorkspaceRequestGet < RequestGet
        desc 'Perform an authenticated GET request against the FeedMob Workspace API'

        def call(path:, **)
          validate_workspace_path!(path)
          super
        end

        def service_name = 'workspace'

        private

        def validate_workspace_path!(path)
          return if path.to_s.start_with?('/api/v1/')

          raise Error.new(
            code: 'invalid_path',
            message: 'FeedMob Workspace requests must target a path under /api/v1/.'
          )
        end
      end
    end
  end
end
