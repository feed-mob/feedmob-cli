# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'feedmob/cli'
require 'feedmob/cli/services'

class PagesCommandsTest < Minitest::Test
  class FakeClient
    attr_reader :requests

    def initialize(responses = [])
      @responses = responses
      @requests = []
    end

    def request(**arguments)
      @requests << arguments
      @responses.shift || FeedMob::CLI::HTTP::Response.new(status: 200, headers: {}, data: {})
    end
  end

  class FakeCredentials
    def resolve(_service)
      FeedMob::CLI::Credential.new(value: 'pages-sentinel-token', source: 'keychain')
    end
  end

  class FakeRuntime
    attr_reader :credentials

    def initialize(credentials:, client:)
      @credentials = credentials
      @client = client
    end

    def service(name)
      FeedMob::CLI::Services.fetch(name, env: {})
    end

    def client(_service) = @client
  end

  def setup
    @previous_runtime = FeedMob::CLI.runtime
  end

  def teardown
    FeedMob::CLI.runtime = @previous_runtime
  end

  def test_pages_auth_status_uses_api_me
    client = FakeClient.new([response(data: { 'code' => 0, 'data' => { 'email' => 'pages@feedmob.test' } })])
    use_runtime(client:)

    stdout, = run_cli('--json', 'pages', 'auth', 'status')

    assert_equal({ method: :get, path: '/api/me', token: 'pages-sentinel-token' }, client.requests.fetch(0))
    assert_equal 'pages@feedmob.test', JSON.parse(stdout).dig('data', 'identity', 'data', 'email')
  end

  def test_list_encodes_query_parameters_and_unwraps_the_pages_envelope
    client = FakeClient.new([response(data: { 'code' => 0, 'data' => { 'items' => [{ 'id' => 'page-id' }] } })])
    use_runtime(client:)

    stdout, = run_cli('--json', 'pages', 'list', '--scope', 'mine', '--q', 'Q2 growth')

    assert_equal(
      { method: :get, path: '/api/pages?q=Q2+growth&scope=mine', token: 'pages-sentinel-token' },
      client.requests.fetch(0)
    )
    assert_equal 'page-id', JSON.parse(stdout).dig('data', 'response', 'items', 0, 'id')
  end

  def test_publish_reads_html_from_a_file_and_does_not_put_it_in_argv
    client = FakeClient.new([
                              response(data: { 'code' => 0, 'data' => {
                                         'id' => 'page-id', 'url' => 'https://pages.test/p/growth/q2'
                                       } })
                            ])
    use_runtime(client:)

    Tempfile.create(['pages', '.html']) do |file|
      file.write('<h1>Q2 report</h1>')
      file.flush
      stdout, = run_cli('--json', 'pages', 'publish', '--owner', 'growth', '--html-file', file.path,
                        '--tags', 'Reporting,AdOps', '--visibility', 'unlisted')

      request = client.requests.fetch(0)
      assert_equal :post, request[:method]
      assert_equal '/api/pages', request[:path]
      assert_equal 'pages-sentinel-token', request[:token]
      assert_equal(
        {
          owner: 'growth',
          html: '<h1>Q2 report</h1>',
          tags: %w[Reporting AdOps],
          visibility: 'unlisted'
        },
        request[:json]
      )
      assert_equal 'page-id', JSON.parse(stdout).dig('data', 'response', 'id')
    end
  end

  def test_update_rejects_html_and_edits_together_before_a_request
    client = FakeClient.new
    use_runtime(client:)

    Tempfile.create(['pages', '.html']) do |html|
      Tempfile.create(['pages-edits', '.json']) do |edits|
        html.write('<h1>New</h1>')
        html.flush
        edits.write('[]')
        edits.flush
        _stdout, stderr, status = run_cli(
          'pages', 'update', '183cbc20-0935-4ea4-ad67-74313bf89512',
          '--html-file', html.path, '--edits-file', edits.path
        )

        assert_equal 1, status
        assert_includes stderr, 'cannot be used together'
        assert_empty client.requests
      end
    end
  end

  def test_share_enable_and_revoke_use_only_the_supported_share_endpoints
    client = FakeClient.new([
                              response(data: { 'code' => 0, 'data' => { 'enabled' => true } }),
                              response(data: { 'code' => 0, 'data' => { 'enabled' => false } })
                            ])
    use_runtime(client:)
    page_id = '183cbc20-0935-4ea4-ad67-74313bf89512'

    run_cli('pages', 'share', 'enable', page_id, '--rotate')
    run_cli('pages', 'share', 'revoke', page_id)

    assert_equal "/api/pages/#{page_id}/share?rotate=true", client.requests.fetch(0).fetch(:path)
    assert_equal "/api/pages/#{page_id}/share", client.requests.fetch(1).fetch(:path)
    assert_equal :post, client.requests.fetch(0).fetch(:method)
    assert_equal :delete, client.requests.fetch(1).fetch(:method)
  end

  def test_asset_upload_builds_a_multipart_request_for_supported_images
    client = FakeClient.new([response(data: { 'full_url' => 'https://assets.test/chart.png' })])
    use_runtime(client:)

    Tempfile.create(['chart', '.png']) do |file|
      file.binmode
      file.write("\x89PNG\r\n")
      file.flush
      stdout, = run_cli('--json', 'pages', 'asset', 'upload', file.path)

      request = client.requests.fetch(0)
      assert_equal :post, request[:method]
      assert_equal '/api/assets/upload', request[:path]
      assert_match(%r{\Amultipart/form-data; boundary=----feedmob}, request.dig(:headers, 'Content-Type'))
      assert_includes request.fetch(:body), 'Content-Type: image/png'
      assert_includes request.fetch(:body), "\x89PNG\r\n".b
      assert_equal 'https://assets.test/chart.png', JSON.parse(stdout).dig('data', 'response', 'full_url')
    end
  end

  def test_excluded_page_lifecycle_commands_are_not_registered
    commands = FeedMob::CLI::Commands.get(['pages']).children.keys

    refute_includes commands, 'delete'
    refute_includes commands, 'restore'
    refute_includes commands, 'revert'
    refute_includes commands, 'claim'
  end

  private

  def response(data:)
    FeedMob::CLI::HTTP::Response.new(status: 200, headers: {}, data:)
  end

  def use_runtime(client:)
    FeedMob::CLI.runtime = FakeRuntime.new(credentials: FakeCredentials.new, client:)
  end

  def run_cli(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = FeedMob::CLI.start(arguments, stdout:, stderr:)
    [stdout.string, stderr.string, status]
  end
end
