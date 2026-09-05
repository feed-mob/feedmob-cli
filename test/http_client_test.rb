# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/http/client'
require 'feedmob/cli/services'

class HttpClientTest < Minitest::Test
  class FakeTransport
    attr_reader :requests

    def initialize(response:)
      @response = response
      @requests = []
    end

    def request(**arguments)
      @requests << arguments
      @response
    end
  end

  def setup
    @service = FeedMob::CLI::Services.fetch('pixel', env: {})
  end

  def test_get_uses_configured_host_bearer_header_and_parses_json
    transport = FakeTransport.new(
      response: { status: 200, headers: { 'content-type' => 'application/json' }, body: '{"service":"pixel"}' }
    )
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)

    response = client.request(method: :get, path: '/api/v1/cli/me', token: 'fmpat_secret')

    assert_equal 200, response.status
    assert_equal({ 'service' => 'pixel' }, response.data)
    assert_equal(
      {
        method: :get,
        url: 'https://feedmob-pixel-dashboard.feedmob.com/rails/api/v1/cli/me',
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'Bearer fmpat_secret'
        }
      },
      transport.requests.fetch(0)
    )
  end

  def test_raw_preserves_body_bytes_and_still_raises_api_errors
    body = "{ \"advertisers\": [] }\n"
    transport = FakeTransport.new(response: { status: 200, headers: {}, body: })
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)
    assert_equal body, client.request(
      method: :get, path: '/api/v1/dashboard_api/advertisers', token: 'fmpat_sentinel', raw: true
    ).data

    transport = FakeTransport.new(response: { status: 401, headers: {}, body: '{"error":{"code":"invalid_token"}}' })
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)
    error = assert_raises(FeedMob::CLI::Error) do
      client.request(method: :get, path: '/api/v1/dashboard_api/advertisers', token: 'fmpat_sentinel', raw: true)
    end
    assert_equal 'invalid_token', error.code
  end

  def test_non_json_response_is_preserved_as_text
    transport = FakeTransport.new(response: { status: 200, headers: {}, body: 'ok' })
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)

    assert_equal 'ok', client.request(method: :get, path: '/up', token: 'fmpat_secret').data
  end

  def test_json_request_sets_content_type_and_serializes_the_body
    transport = FakeTransport.new(
      response: { status: 200, headers: {}, body: '{"code":0,"data":{"id":"page-id"}}' }
    )
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)

    response = client.request(
      method: :post,
      path: '/api/pages',
      token: 'fmpat_secret',
      json: { owner: 'growth', html: '<h1>Report</h1>' }
    )

    assert_equal 'page-id', response.data.dig('data', 'id')
    assert_equal(
      {
        method: :post,
        url: 'https://feedmob-pixel-dashboard.feedmob.com/rails/api/pages',
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'Bearer fmpat_secret',
          'Content-Type' => 'application/json'
        },
        body: '{"owner":"growth","html":"<h1>Report</h1>"}'
      },
      transport.requests.fetch(0)
    )
  end

  def test_pages_style_error_uses_the_documented_message_without_exposing_token
    transport = FakeTransport.new(
      response: {
        status: 422,
        headers: { 'content-type' => 'application/json' },
        body: '{"code":422,"msg":"HTML is invalid."}'
      }
    )
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)

    error = assert_raises(FeedMob::CLI::Error) do
      client.request(method: :post, path: '/api/pages', token: 'fmpat_never-print-me', json: { html: 'bad' })
    end

    assert_equal '422', error.code
    assert_equal 'HTML is invalid.', error.message
    refute_includes error.message, 'fmpat_never-print-me'
  end

  def test_rejects_paths_that_can_escape_the_configured_host
    client = FeedMob::CLI::HTTP::Client.new(
      service: @service,
      transport: FakeTransport.new(response: { status: 200, headers: {}, body: 'ok' })
    )

    ['https://evil.example/me', '//evil.example/me', 'api/v1/me'].each do |path|
      error = assert_raises(FeedMob::CLI::Error) do
        client.request(method: :get, path:, token: 'fmpat_secret')
      end
      assert_equal 'invalid_path', error.code
    end
  end

  def test_api_error_uses_remote_message_without_exposing_token
    transport = FakeTransport.new(
      response: {
        status: 401,
        headers: { 'content-type' => 'application/json' },
        body: '{"error":{"code":"invalid_token","message":"Credential expired."}}'
      }
    )
    client = FeedMob::CLI::HTTP::Client.new(service: @service, transport:)

    error = assert_raises(FeedMob::CLI::Error) do
      client.request(method: :get, path: '/api/v1/cli/me', token: 'fmpat_never-print-me')
    end

    assert_equal 'invalid_token', error.code
    assert_equal 'Credential expired.', error.message
    refute_includes error.message, 'fmpat_never-print-me'
  end

  def test_workspace_unauthorized_error_explains_the_account_approval_requirement
    workspace_service = FeedMob::CLI::Services.fetch('workspace', env: {})
    transport = FakeTransport.new(
      response: {
        status: 401,
        headers: { 'content-type' => 'application/json' },
        body: '{"error":"Unauthorized"}'
      }
    )
    client = FeedMob::CLI::HTTP::Client.new(service: workspace_service, transport:)

    error = assert_raises(FeedMob::CLI::Error) do
      client.request(method: :get, path: '/api/v1/me', token: 'fmapat_never-print-me')
    end

    expected_message = 'FeedMob Workspace could not authenticate with the FeedMob Admin API. ' \
                       'Confirm that the personal access token is active and the FeedMob SSO account is approved.'
    assert_equal 'http_error', error.code
    assert_equal expected_message, error.message
    assert_equal({ status: 401 }, error.details)
    refute_includes error.message, 'fmapat_never-print-me'
  end
end
