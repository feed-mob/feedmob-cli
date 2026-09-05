# frozen_string_literal: true

require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class WorkspaceBase < Base
        private

        def service_name = 'workspace'
      end

      class WorkspaceOpenapi < WorkspaceBase
        desc 'Fetch the OpenAPI schema for FeedMob Workspace'

        def call(**)
          credential = credential!(service)
          response = runtime.client(service).request(
            method: :get,
            path: '/api/v1/openapi',
            token: credential.value
          )

          output.success(
            {
              service: service.name,
              status: response.status,
              response: response.data
            },
            message: "GET /api/v1/openapi returned HTTP #{response.status}."
          )
        end
      end
    end
  end
end
