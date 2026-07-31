# frozen_string_literal: true

module FeedMob
  module CLI
    class Error < StandardError
      attr_reader :code, :details, :exit_status

      def initialize(code:, message:, details: nil, exit_status: 1)
        super(message)
        @code = code
        @details = details
        @exit_status = exit_status
      end
    end
  end
end
