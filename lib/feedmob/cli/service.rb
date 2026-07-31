# frozen_string_literal: true

module FeedMob
  module CLI
    Service = Data.define(
      :name,
      :label,
      :base_url,
      :token_env,
      :token_prefix,
      :identity_path,
      :revoke_path,
      :keychain_service
    )
  end
end
