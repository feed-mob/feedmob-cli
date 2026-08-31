# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/services'

class ServicesTest < Minitest::Test
  def test_pixel_contract
    service = FeedMob::CLI::Services.fetch('pixel', env: {})

    assert_equal 'Pixel', service.label
    assert_equal 'https://feedmob-pixel-dashboard.feedmob.com/rails', service.base_url
    assert_equal 'FEEDMOB_PIXEL_TOKEN', service.token_env
    assert_equal 'fmpat_', service.token_prefix
    assert_equal '/api/v1/cli/me', service.identity_path
    assert_equal '/api/v1/cli/token', service.revoke_path
  end

  def test_time_off_contract_stays_on_existing_api
    service = FeedMob::CLI::Services.fetch('time-off', env: {})

    assert_equal 'Time Off', service.label
    assert_equal 'https://time-off.feedmob.com', service.base_url
    assert_equal 'FEEDMOB_TIME_OFF_TOKEN', service.token_env
    assert_equal 'fmtopat_', service.token_prefix
    assert_equal '/api/v1/me', service.identity_path
    assert_nil service.revoke_path
  end

  def test_femini_contract_uses_documented_bearer_authentication
    service = FeedMob::CLI::Services.fetch('femini', env: {})

    assert_equal 'Femini', service.label
    assert_equal 'https://assistant.feedmob.ai', service.base_url
    assert_equal 'FEEDMOB_FEMINI_TOKEN', service.token_env
    assert_nil service.token_prefix
    assert_equal '/clients.json?name_cont=__feedmob_cli_auth_probe__', service.identity_path
    refute_predicate service, :identity_response
    assert_nil service.revoke_path
  end

  def test_pages_contract_uses_a_service_specific_api_key_and_identity_endpoint
    service = FeedMob::CLI::Services.fetch('pages', env: {})

    assert_equal 'Pages', service.label
    assert_equal 'https://pages.feedmob.com', service.base_url
    assert_equal 'FEEDMOB_PAGES_TOKEN', service.token_env
    assert_nil service.token_prefix
    assert_equal '/api/me', service.identity_path
    assert_nil service.revoke_path
    assert_equal 'com.feedmob.fm.pages', service.keychain_service
  end

  def test_https_base_url_environment_override_is_normalized
    service = FeedMob::CLI::Services.fetch(
      'pixel',
      env: { 'FEEDMOB_PIXEL_BASE_URL' => 'https://test.feedmob.example/rails/' }
    )

    assert_equal 'https://test.feedmob.example/rails', service.base_url
  end

  def test_http_base_url_is_rejected_without_an_explicit_loopback_opt_in
    error = assert_raises(FeedMob::CLI::Error) do
      FeedMob::CLI::Services.fetch(
        'pixel',
        env: { 'FEEDMOB_PIXEL_BASE_URL' => 'http://localhost:3000/rails/' }
      )
    end

    assert_equal 'insecure_base_url', error.code
    assert_includes error.message, 'FEEDMOB_ALLOW_INSECURE_HTTP=1'
  end

  def test_http_loopback_base_url_requires_and_honors_the_explicit_opt_in
    service = FeedMob::CLI::Services.fetch(
      'pixel',
      env: {
        'FEEDMOB_PIXEL_BASE_URL' => 'http://127.0.0.1:3000/rails/',
        'FEEDMOB_ALLOW_INSECURE_HTTP' => '1'
      }
    )

    assert_equal 'http://127.0.0.1:3000/rails', service.base_url
  end

  def test_http_non_loopback_base_url_is_rejected_even_when_insecure_http_is_enabled
    error = assert_raises(FeedMob::CLI::Error) do
      FeedMob::CLI::Services.fetch(
        'pixel',
        env: {
          'FEEDMOB_PIXEL_BASE_URL' => 'http://test.feedmob.example/rails',
          'FEEDMOB_ALLOW_INSECURE_HTTP' => '1'
        }
      )
    end

    assert_equal 'insecure_base_url', error.code
  end

  def test_unknown_service_is_rejected
    error = assert_raises(FeedMob::CLI::Error) do
      FeedMob::CLI::Services.fetch('admin', env: {})
    end

    assert_equal 'unknown_service', error.code
  end

  def test_invalid_base_url_override_is_rejected_before_a_request_is_attempted
    error = assert_raises(FeedMob::CLI::Error) do
      FeedMob::CLI::Services.fetch('pixel', env: { 'FEEDMOB_PIXEL_BASE_URL' => 'not a url' })
    end

    assert_equal 'invalid_base_url', error.code
    assert_includes error.message, 'FEEDMOB_PIXEL_BASE_URL'
  end
end
