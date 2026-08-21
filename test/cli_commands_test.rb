# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli'
require 'feedmob/cli/services'

class CliCommandsTest < Minitest::Test
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
    attr_reader :stored, :deleted

    def initialize(credential: FeedMob::CLI::Credential.new(value: 'fmpat_saved', source: 'keychain'))
      @credential = credential
      @stored = []
      @deleted = []
    end

    def resolve(_service)
      @credential
    end

    def store(service, token)
      @stored << [service.name, token]
    end

    def validate_token!(_service, _token); end

    def storage_source = 'keychain'

    def storage_label = 'macOS Keychain'

    def delete(service)
      @deleted << service.name
    end
  end

  class FakeRuntime
    attr_reader :credentials

    def initialize(credentials:, clients:, token: 'fmpat_from_stdin')
      @credentials = credentials
      @clients = clients
      @token = token
    end

    def service(name)
      FeedMob::CLI::Services.fetch(name, env: {})
    end

    def services
      %w[pixel time-off].map { |name| service(name) }
    end

    def client(service)
      @clients.fetch(service.name)
    end

    def read_token_from_stdin
      @token
    end

    def read_token_interactively(_service)
      @token
    end
  end

  def setup
    @previous_runtime = FeedMob::CLI.runtime
  end

  def teardown
    FeedMob::CLI.runtime = @previous_runtime
  end

  def test_pixel_login_verifies_identity_then_saves_to_keychain
    credentials = FakeCredentials.new
    pixel_client = FakeClient.new(
      [FeedMob::CLI::HTTP::Response.new(status: 200, headers: {},
                                        data: { 'user' => { 'email' => 'cli@feedmob.com' } })]
    )
    use_runtime(credentials:, clients: { 'pixel' => pixel_client, 'time-off' => FakeClient.new })

    stdout, stderr, status = run_cli('--json', 'pixel', 'auth', 'login', '--token-stdin')

    assert_equal 0, status
    assert_empty stderr
    assert_equal [%w[pixel fmpat_from_stdin]], credentials.stored
    assert_equal(
      { method: :get, path: '/api/v1/cli/me', token: 'fmpat_from_stdin' },
      pixel_client.requests.fetch(0)
    )
    assert_equal(
      {
        'ok' => true,
        'data' => {
          'service' => 'pixel',
          'authenticated' => true,
          'source' => 'keychain',
          'identity' => { 'user' => { 'email' => 'cli@feedmob.com' } }
        }
      },
      JSON.parse(stdout)
    )
  end

  def test_time_off_status_uses_its_own_identity_endpoint_and_credential_source
    credentials = FakeCredentials.new(
      credential: FeedMob::CLI::Credential.new(value: 'fmtopat_from_environment', source: 'env')
    )
    time_off_client = FakeClient.new(
      [FeedMob::CLI::HTTP::Response.new(status: 200, headers: {},
                                        data: { 'user' => { 'email' => 'time-off@feedmob.com' } })]
    )
    use_runtime(credentials:, clients: { 'pixel' => FakeClient.new, 'time-off' => time_off_client })

    stdout, = run_cli('time-off', 'auth', 'status', '--json')

    assert_equal(
      { method: :get, path: '/api/v1/me', token: 'fmtopat_from_environment' },
      time_off_client.requests.fetch(0)
    )
    assert_equal 'env', JSON.parse(stdout).dig('data', 'source')
  end

  def test_pixel_logout_revokes_the_remote_token_then_deletes_local_keychain_value
    credentials = FakeCredentials.new
    pixel_client = FakeClient.new(
      [FeedMob::CLI::HTTP::Response.new(status: 204, headers: {}, data: nil)]
    )
    use_runtime(credentials:, clients: { 'pixel' => pixel_client, 'time-off' => FakeClient.new })

    stdout, = run_cli('--json', 'pixel', 'auth', 'logout')

    assert_equal ['pixel'], credentials.deleted
    assert_equal(
      { method: :delete, path: '/api/v1/cli/token', token: 'fmpat_saved' },
      pixel_client.requests.fetch(0)
    )
    assert_equal true, JSON.parse(stdout).dig('data', 'remote_revoked')
  end

  def test_time_off_logout_only_deletes_the_local_credential
    credentials = FakeCredentials.new(
      credential: FeedMob::CLI::Credential.new(value: 'fmtopat_saved', source: 'keychain')
    )
    time_off_client = FakeClient.new
    use_runtime(credentials:, clients: { 'pixel' => FakeClient.new, 'time-off' => time_off_client })

    stdout, = run_cli('time-off', 'auth', 'logout', '--json')

    assert_equal ['time-off'], credentials.deleted
    assert_empty time_off_client.requests
    assert_equal false, JSON.parse(stdout).dig('data', 'remote_revoked')
  end

  def test_environment_credential_logout_names_the_variable_to_unset
    credentials = FakeCredentials.new(
      credential: FeedMob::CLI::Credential.new(value: 'fmpat_from_environment', source: 'env')
    )
    pixel_client = FakeClient.new(
      [FeedMob::CLI::HTTP::Response.new(status: 204, headers: {}, data: nil)]
    )
    use_runtime(credentials:, clients: { 'pixel' => pixel_client, 'time-off' => FakeClient.new })

    stdout, = run_cli('pixel', 'auth', 'logout', '--json')

    refute credentials.deleted.any?
    assert_equal 'FEEDMOB_PIXEL_TOKEN', JSON.parse(stdout).dig('data', 'environment_variable')
    assert_equal true, JSON.parse(stdout).dig('data', 'remote_revoked')
  end

  def test_request_get_uses_service_credential_and_returns_api_body
    credentials = FakeCredentials.new
    pixel_client = FakeClient.new(
      [FeedMob::CLI::HTTP::Response.new(status: 200, headers: {}, data: { 'items' => [1, 2] })]
    )
    use_runtime(credentials:, clients: { 'pixel' => pixel_client, 'time-off' => FakeClient.new })

    stdout, = run_cli('pixel', 'request', 'get', '/api/v1/events', '--json')

    assert_equal(
      { method: :get, path: '/api/v1/events', token: 'fmpat_saved' },
      pixel_client.requests.fetch(0)
    )
    assert_equal({ 'items' => [1, 2] }, JSON.parse(stdout).dig('data', 'response'))
  end

  def test_doctor_reports_missing_credentials_without_calling_a_service
    credentials = FakeCredentials.new(credential: FeedMob::CLI::Credential.new(value: nil, source: 'missing'))
    pixel_client = FakeClient.new
    time_off_client = FakeClient.new
    use_runtime(credentials:, clients: { 'pixel' => pixel_client, 'time-off' => time_off_client })

    stdout, stderr, status = run_cli('doctor', '--json')

    assert_equal 0, status
    assert_empty stderr
    assert_empty pixel_client.requests
    assert_empty time_off_client.requests
    assert_equal false, JSON.parse(stdout).dig('data', 'services', 0, 'authenticated')
    assert_equal 'missing', JSON.parse(stdout).dig('data', 'services', 1, 'credential_source')
  end

  def test_missing_credential_uses_the_json_error_envelope
    credentials = FakeCredentials.new(credential: FeedMob::CLI::Credential.new(value: nil, source: 'missing'))
    use_runtime(credentials:, clients: { 'pixel' => FakeClient.new, 'time-off' => FakeClient.new })

    stdout, stderr, status = run_cli('pixel', 'auth', 'status', '--json')

    assert_equal 1, status
    assert_empty stderr
    assert_equal(
      {
        'ok' => false,
        'error' => {
          'code' => 'credential_missing',
          'message' => 'No Pixel credential is configured. Set FEEDMOB_PIXEL_TOKEN or run fm pixel auth login.'
        }
      },
      JSON.parse(stdout)
    )
  end

  private

  def use_runtime(credentials:, clients:)
    FeedMob::CLI.runtime = FakeRuntime.new(credentials:, clients:)
  end

  def run_cli(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = FeedMob::CLI.start(arguments, stdout:, stderr:)
    [stdout.string, stderr.string, status]
  end
end
