# frozen_string_literal: true

require 'json'

module FeedMob
  module CLI
    class Output
      def initialize(stdout:, stderr:, json:)
        @stdout = stdout
        @stderr = stderr
        @json = json
      end

      def success(payload = nil, message: nil, **attributes)
        payload ||= attributes
        if @json
          @stdout.puts JSON.generate(ok: true, data: payload)
        else
          @stdout.puts(message || payload.fetch(:message, humanize(payload)))
        end
      end

      def error(code:, message:, details: nil)
        if @json
          error = { code:, message: }
          error[:details] = details if details
          @stdout.puts JSON.generate(ok: false, error:)
        else
          @stderr.puts "Error: #{message}"
        end
      end

      private

      def humanize(payload)
        payload.map { |key, value| "#{key}=#{value}" }.join(' ')
      end
    end
  end
end
