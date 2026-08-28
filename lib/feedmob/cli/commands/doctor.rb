# frozen_string_literal: true

require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class Doctor < Base
        desc 'Check FeedMob service credential configuration'

        def call(**)
          services = runtime.services.map { |service| check(service) }
          output.success({ services: }, message: "Checked #{services.length} FeedMob services.")
        end

        private

        def check(service)
          credential_source = 'unknown'
          credential = runtime.credentials.resolve(service)
          credential_source = credential.source
          return missing(service) if credential.source == 'missing'

          response = runtime.client(service).request(method: :get, path: service.identity_path, token: credential.value)
          payload = {
            service: service.name,
            authenticated: true,
            credential_source: credential.source
          }
          payload[:identity] = response.data if service.identity_response
          payload
        rescue Error => e
          {
            service: service.name,
            authenticated: false,
            credential_source:,
            error: { code: e.code, message: e.message }
          }
        end

        def missing(service)
          {
            service: service.name,
            authenticated: false,
            credential_source: 'missing',
            setup: "Set #{service.token_env} or run fm #{service.name} auth login."
          }
        end
      end
    end
  end
end
