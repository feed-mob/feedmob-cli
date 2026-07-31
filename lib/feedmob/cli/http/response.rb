# frozen_string_literal: true

module FeedMob
  module CLI
    module HTTP
      Response = Data.define(:status, :headers, :data)
    end
  end
end
