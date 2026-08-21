# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'test_helper'
require 'feedmob/cli/credentials'
require 'feedmob/cli/encrypted_store'
require 'feedmob/cli/services'

class EncryptedStoreTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('feedmob-cli-credentials')
    @store = FeedMob::CLI::EncryptedStore.new(config_dir: @directory, platform: 'linux')
    @pixel = FeedMob::CLI::Services.fetch('pixel', env: {})
    @time_off = FeedMob::CLI::Services.fetch('time-off', env: {})
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_round_trips_service_specific_values_without_writing_plaintext
    @store.write(@pixel, 'fmpat_secret_value')
    @store.write(@time_off, 'fmtopat_other_secret')

    assert_equal 'fmpat_secret_value', @store.read(@pixel)
    assert_equal 'fmtopat_other_secret', @store.read(@time_off)
    Dir.children(@directory).each do |entry|
      refute_includes File.binread(File.join(@directory, entry)), 'secret'
    end
  end

  def test_credentials_reports_the_encrypted_file_source_on_non_macos
    credentials = FeedMob::CLI::Credentials.new(
      env: {},
      keychain: FeedMob::CLI::Keychain.new(platform: 'linux', fallback_store: @store)
    )

    credentials.store(@pixel, 'fmpat_secret_value')
    credential = credentials.resolve(@pixel)

    assert_equal 'encrypted_file', credential.source
    assert_equal 'fmpat_secret_value', credential.value
    assert_equal 'encrypted local credential store', credentials.storage_label
  end

  def test_uses_restrictive_unix_permissions
    @store.write(@pixel, 'fmpat_secret_value')

    assert_equal 0o700, File.stat(@directory).mode & 0o777
    %w[.credentials.lock .encryption_key credentials.enc].each do |entry|
      assert_equal 0o600, File.stat(File.join(@directory, entry)).mode & 0o777
    end
  end

  def test_delete_only_removes_the_requested_service_value
    @store.write(@pixel, 'fmpat_secret_value')
    @store.write(@time_off, 'fmtopat_other_secret')

    assert @store.delete(@pixel)
    assert_nil @store.read(@pixel)
    assert_equal 'fmtopat_other_secret', @store.read(@time_off)
    refute @store.delete(@pixel)
  end

  def test_rejects_tampered_ciphertext
    @store.write(@pixel, 'fmpat_secret_value')
    path = File.join(@directory, 'credentials.enc')
    ciphertext = File.binread(path)
    ciphertext.setbyte(-1, ciphertext.getbyte(-1) ^ 1)
    File.binwrite(path, ciphertext)

    error = assert_raises(FeedMob::CLI::Error) { @store.read(@pixel) }

    assert_equal 'credential_store_error', error.code
    assert_includes error.message, 'could not be authenticated'
  end

  def test_rejects_a_symbolic_link_for_the_credential_file
    target = File.join(@directory, 'not-a-credential')
    File.binwrite(target, 'not encrypted')
    File.symlink(target, File.join(@directory, 'credentials.enc'))

    error = assert_raises(FeedMob::CLI::Error) { @store.read(@pixel) }

    assert_equal 'credential_store_error', error.code
    assert_includes error.message, 'symbolic links'
  end
end
