# frozen_string_literal: true

require 'json'
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
        option :raw, type: :boolean, default: false, desc: 'Write the response body verbatim (incompatible with --json)'

        def call(raw: false, **)
          if raw && FeedMob::CLI.json?
            raise Error.new(code: 'invalid_input', message: '--raw cannot be combined with --json.')
          end

          credential = credential!(service)
          if raw
            response = runtime.client(service).request(
              method: :get,
              path: '/api/v1/openapi',
              token: credential.value,
              raw: true
            )
            (@out || $stdout).write(response.data)
            return
          end

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
            message: JSON.pretty_generate(response.data)
          )
        end
      end
    end
  end
end
