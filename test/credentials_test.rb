# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/credentials'
require 'feedmob/cli/services'

class CredentialsTest < Minitest::Test
  class FakeKeychain
    attr_reader :writes, :deletes

    def initialize(value = nil)
      @value = value
      @writes = []
      @deletes = []
    end

    def read(_service)
      @value
    end

    def write(service, token)
      @writes << [service.name, token]
    end

    def delete(service)
      @deletes << service.name
    end
  end

  def setup
    @service = FeedMob::CLI::Services.fetch('pixel', env: {})
  end

  def test_environment_credential_takes_precedence_over_keychain
    credentials = FeedMob::CLI::Credentials.new(
      env: { 'FEEDMOB_PIXEL_TOKEN' => 'fmpat_env' },
      keychain: FakeKeychain.new('fmpat_keychain')
    )

    credential = credentials.resolve(@service)

    assert_equal 'fmpat_env', credential.value
    assert_equal 'env', credential.source
  end

  def test_keychain_and_missing_sources_are_explicit
    keychain_credential = FeedMob::CLI::Credentials.new(
      env: {},
      keychain: FakeKeychain.new('fmpat_keychain')
    ).resolve(@service)
    missing_credential = FeedMob::CLI::Credentials.new(
      env: {},
      keychain: FakeKeychain.new
    ).resolve(@service)

    assert_equal 'keychain', keychain_credential.source
    assert_equal 'fmpat_keychain', keychain_credential.value
    assert_equal 'missing', missing_credential.source
    assert_nil missing_credential.value
  end

  def test_store_rejects_token_for_a_different_service
    credentials = FeedMob::CLI::Credentials.new(env: {}, keychain: FakeKeychain.new)

    error = assert_raises(FeedMob::CLI::Error) do
      credentials.store(@service, 'fmtopat_time_off_token')
    end

    assert_equal 'invalid_token_format', error.code
    refute_includes error.message, 'fmtopat_time_off_token'
  end

  def test_store_and_delete_delegate_to_keychain
    keychain = FakeKeychain.new
    credentials = FeedMob::CLI::Credentials.new(env: {}, keychain:)

    credentials.store(@service, 'fmpat_secret')
    credentials.delete(@service)

    assert_equal [%w[pixel fmpat_secret]], keychain.writes
    assert_equal ['pixel'], keychain.deletes
  end

  def test_femini_accepts_a_bearer_token_without_a_documented_prefix
    service = FeedMob::CLI::Services.fetch('femini', env: {})
    keychain = FakeKeychain.new
    credentials = FeedMob::CLI::Credentials.new(env: {}, keychain:)

    credentials.store(service, 'femini-bearer-token')

    assert_equal [%w[femini femini-bearer-token]], keychain.writes
  end
end
