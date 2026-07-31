# frozen_string_literal: true

require_relative 'base'
require_relative '../version'

module FeedMob
  module CLI
    module Commands
      class Version < Base
        desc 'Print the fm version'

        def call(**)
          output.success({ version: VERSION }, message: "fm #{VERSION}")
        end
      end
    end
  end
end
