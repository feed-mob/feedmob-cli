# frozen_string_literal: true

module FeedMob
  module CLI
    module Services
      DEFINITIONS = {
        'pixel' => {
          label: 'Pixel', base_url: 'https://feedmob-pixel-dashboard.feedmob.com/rails',
          base_url_env: 'FEEDMOB_PIXEL_BASE_URL', token_env: 'FEEDMOB_PIXEL_TOKEN', token_prefix: 'fmpat_',
          identity_path: '/api/v1/cli/me', identity_response: true, revoke_path: '/api/v1/cli/token',
          keychain_service: 'com.feedmob.fm.pixel'
        },
        'time-off' => {
          label: 'Time Off', base_url: 'https://time-off.feedmob.com', base_url_env: 'FEEDMOB_TIME_OFF_BASE_URL',
          token_env: 'FEEDMOB_TIME_OFF_TOKEN', token_prefix: 'fmtopat_', identity_path: '/api/v1/me',
          identity_response: true, revoke_path: nil, keychain_service: 'com.feedmob.fm.time-off'
        },
        'femini' => {
          label: 'Femini', base_url: 'https://assistant.feedmob.ai', base_url_env: 'FEEDMOB_FEMINI_BASE_URL',
          token_env: 'FEEDMOB_FEMINI_TOKEN', token_prefix: nil,
          identity_path: '/clients.json?name_cont=__feedmob_cli_auth_probe__', identity_response: false,
          revoke_path: nil, keychain_service: 'com.feedmob.fm.femini'
        },
        'pages' => {
          label: 'Pages', base_url: 'https://pages.feedmob.com', base_url_env: 'FEEDMOB_PAGES_BASE_URL',
          token_env: 'FEEDMOB_PAGES_TOKEN', token_prefix: nil, identity_path: '/api/me', identity_response: true,
          revoke_path: nil, keychain_service: 'com.feedmob.fm.pages'
        },
        'workspace' => {
          label: 'FeedMob Workspace', base_url: 'https://admin.feedmob.com',
          base_url_env: 'FEEDMOB_WORKSPACE_BASE_URL', token_env: 'FEEDMOB_WORKSPACE_TOKEN',
          token_prefix: 'fmapat_', identity_path: '/api/v1/me', identity_response: true, revoke_path: nil,
          keychain_service: 'com.feedmob.fm.workspace'
        }
      }.freeze
    end
  end
end
