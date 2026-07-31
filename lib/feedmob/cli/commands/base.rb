# frozen_string_literal: true

require 'dry/cli'
require_relative '../error'
require_relative '../output'

module FeedMob
  module CLI
    module Commands
      class Base < Dry::CLI::Command
        private

        def service
          runtime.service(service_name)
        end

        def runtime
          FeedMob::CLI.runtime
        end

        def output
          Output.new(stdout: @out || $stdout, stderr: @err || $stderr, json: FeedMob::CLI.json?)
        end

        def credential!(service)
          credential = runtime.credentials.resolve(service)
          return credential unless credential.source == 'missing'

          raise Error.new(
            code: 'credential_missing',
            message: [
              "No #{service.label} credential is configured.",
              "Set #{service.token_env} or run fm #{service.name} auth login."
            ].join(' ')
          )
        end
      end
    end
  end
end
