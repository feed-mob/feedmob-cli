# frozen_string_literal: true

require 'date'
require 'json'
require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class TimeOffBase < Base
        private

        def service_name = 'time-off'

        def time_off_request(method:, path:, json:, message:)
          credential = credential!(service)
          response = runtime.client(service).request(method:, path:, token: credential.value, json:)
          output.success(
            { service: service.name, status: response.status, response: response.data },
            message:
          )
        end

        def journal_date(value)
          date = Date.iso8601(value.to_s)
          return value if date.iso8601 == value

          raise Error.new(code: 'invalid_input', message: 'date must be in YYYY-MM-DD format.')
        rescue Date::Error
          raise Error.new(code: 'invalid_input', message: 'date must be in YYYY-MM-DD format.')
        end

        def journal_content(value)
          content = value.to_s
          return content unless content.strip.empty?

          raise Error.new(code: 'invalid_input', message: 'content must not be empty.')
        end
      end

      class TimeOffJournalUpdate < TimeOffBase
        desc 'Create or update your work journal for a date'
        argument :date, required: true, desc: 'Journal date in YYYY-MM-DD format'
        option :content, type: :string, desc: 'Journal content'

        def call(date:, content: nil, **)
          value = journal_date(date)
          time_off_request(
            method: :put,
            path: "/api/v1/journals/#{value}",
            json: { content: journal_content(content) },
            message: "Updated work journal for #{value}."
          )
        end
      end
    end
  end
end
