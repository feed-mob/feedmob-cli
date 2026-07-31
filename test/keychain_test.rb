# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/keychain'
require 'feedmob/cli/services'

class KeychainTest < Minitest::Test
  FakeResult = Data.define(:stdout, :stderr, :success?)

  class FakeRunner
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def call(argv, stdin_data: nil)
      @calls << { argv:, stdin_data: }
      @results.shift
    end
  end

  def setup
    @service = FeedMob::CLI::Services.fetch('pixel', env: {})
  end

  def test_write_passes_token_on_stdin_instead_of_process_arguments
    runner = FakeRunner.new([FakeResult.new(stdout: '', stderr: '', success?: true)])
    keychain = FeedMob::CLI::Keychain.new(platform: 'darwin', runner:)

    keychain.write(@service, 'fmpat_secret')

    call = runner.calls.fetch(0)
    assert_equal '/usr/bin/security', call.fetch(:argv).first
    assert_equal '-w', call.fetch(:argv).last
    refute_includes call.fetch(:argv), 'fmpat_secret'
    assert_equal "fmpat_secret\n", call.fetch(:stdin_data)
  end

  def test_read_and_delete_use_service_specific_item
    runner = FakeRunner.new(
      [
        FakeResult.new(stdout: "fmpat_secret\n", stderr: '', success?: true),
        FakeResult.new(stdout: '', stderr: '', success?: true)
      ]
    )
    keychain = FeedMob::CLI::Keychain.new(platform: 'darwin', runner:)

    assert_equal 'fmpat_secret', keychain.read(@service)
    assert keychain.delete(@service)
    assert_includes runner.calls.first.fetch(:argv), 'com.feedmob.fm.pixel'
    assert_includes runner.calls.last.fetch(:argv), 'delete-generic-password'
  end

  def test_missing_keychain_item_returns_nil
    runner = FakeRunner.new(
      [FakeResult.new(stdout: '', stderr: 'The specified item could not be found in the keychain.', success?: false)]
    )

    assert_nil FeedMob::CLI::Keychain.new(platform: 'darwin', runner:).read(@service)
  end

  def test_non_macos_platform_reports_environment_variable_alternative
    keychain = FeedMob::CLI::Keychain.new(platform: 'linux', runner: FakeRunner.new([]))

    error = assert_raises(FeedMob::CLI::Error) { keychain.write(@service, 'fmpat_secret') }

    assert_equal 'keychain_unavailable', error.code
    assert_includes error.message, 'FEEDMOB_PIXEL_TOKEN'
  end
end
