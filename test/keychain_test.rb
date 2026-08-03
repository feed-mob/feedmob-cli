# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/keychain'
require 'feedmob/cli/services'
require 'fiddle'

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

  class FakeNativeWriter
    attr_reader :writes

    def initialize(success: true)
      @success = success
      @writes = []
    end

    def write(account:, service:, password:)
      @writes << { account:, service:, password: }
      @success
    end
  end

  class FakeSecurityAPI
    attr_reader :calls

    def initialize(add_status:, find_result: nil, modify_status: nil)
      @add_status = add_status
      @find_result = find_result
      @modify_status = modify_status
      @calls = []
    end

    def add_generic_password(account:, service:, password:)
      @calls << { operation: :add, account:, service:, password: }
      @add_status
    end

    def find_generic_password(account:, service:)
      @calls << { operation: :find, account:, service: }
      @find_result
    end

    def modify_item(item, password:)
      @calls << { operation: :modify, item:, password: }
      @modify_status
    end

    def release(item)
      @calls << { operation: :release, item: }
    end
  end

  class FakeSecurityFunctions
    attr_reader :calls

    def initialize(status: 0, item_address: 0x1234)
      @status = status
      @item_address = item_address
      @calls = []
    end

    # These names mirror the Security.framework C symbols called through Fiddle.
    # rubocop:disable Naming/MethodName
    def SecKeychainAddGenericPassword(*arguments)
      @calls << { operation: :add, arguments: }
      @status
    end

    def SecKeychainFindGenericPassword(*arguments)
      @calls << { operation: :find, arguments: }
      item_output = arguments.last
      item_output[0, Fiddle::SIZEOF_VOIDP] = [@item_address].pack('J')
      @status
    end

    def SecKeychainItemModifyAttributesAndData(*arguments)
      @calls << { operation: :modify, arguments: }
      @status
    end

    def CFRelease(item)
      @calls << { operation: :release, arguments: [item] }
    end
    # rubocop:enable Naming/MethodName
  end

  def setup
    @service = FeedMob::CLI::Services.fetch('pixel', env: {})
  end

  def test_write_passes_token_to_the_native_writer_instead_of_a_command
    runner = FakeRunner.new([])
    native_writer = FakeNativeWriter.new
    keychain = FeedMob::CLI::Keychain.new(platform: 'darwin', runner:, native_writer:)

    keychain.write(@service, 'fmpat_secret')

    assert_empty runner.calls
    assert_equal(
      [{ account: 'fm', service: 'com.feedmob.fm.pixel', password: 'fmpat_secret' }],
      native_writer.writes
    )
  end

  def test_write_reports_a_keychain_error_when_the_native_write_fails
    keychain = FeedMob::CLI::Keychain.new(
      platform: 'darwin',
      runner: FakeRunner.new([]),
      native_writer: FakeNativeWriter.new(success: false)
    )

    error = assert_raises(FeedMob::CLI::Error) { keychain.write(@service, 'fmpat_secret') }

    assert_equal 'keychain_error', error.code
  end

  def test_native_writer_adds_a_new_generic_password
    api = FakeSecurityAPI.new(add_status: 0)
    writer = FeedMob::CLI::Keychain::NativeWriter.new(api:)

    assert writer.write(account: 'fm', service: 'com.feedmob.fm.time-off', password: 'fmtopat_secret')
    assert_equal(
      [{ operation: :add, account: 'fm', service: 'com.feedmob.fm.time-off', password: 'fmtopat_secret' }],
      api.calls
    )
  end

  def test_native_writer_updates_and_releases_an_existing_generic_password
    api = FakeSecurityAPI.new(add_status: -25_299, find_result: [0, :item_reference], modify_status: 0)
    writer = FeedMob::CLI::Keychain::NativeWriter.new(api:)

    assert writer.write(account: 'fm', service: 'com.feedmob.fm.time-off', password: 'fmtopat_updated')
    operations = api.calls.map { |call| call.fetch(:operation) }
    assert_equal %i[add find modify release], operations
    assert_equal 'fmtopat_updated', api.calls.fetch(2).fetch(:password)
  end

  def test_native_writer_reports_non_duplicate_security_errors
    api = FakeSecurityAPI.new(add_status: -50)
    writer = FeedMob::CLI::Keychain::NativeWriter.new(api:)

    refute writer.write(account: 'fm', service: 'com.feedmob.fm.time-off', password: 'fmtopat_secret')
    operations = api.calls.map { |call| call.fetch(:operation) }
    assert_equal [:add], operations
  end

  def test_security_framework_marshals_generic_password_operations
    functions = FakeSecurityFunctions.new
    api = FeedMob::CLI::Keychain::SecurityFramework.new(functions:)

    assert_equal 0, api.add_generic_password(
      account: 'fm', service: 'com.feedmob.fm.time-off', password: 'fmtopat_secret'
    )
    add_arguments = functions.calls.fetch(0).fetch(:arguments)
    assert_equal ['com.feedmob.fm.time-off'.bytesize, 'com.feedmob.fm.time-off'], add_arguments.values_at(1, 2)
    assert_equal ['fm'.bytesize, 'fm'], add_arguments.values_at(3, 4)
    assert_equal ['fmtopat_secret'.bytesize, 'fmtopat_secret'], add_arguments.values_at(5, 6)

    status, item = api.find_generic_password(account: 'fm', service: 'com.feedmob.fm.time-off')
    assert_equal 0, status
    assert_equal 0x1234, item.to_i
    assert_equal 0, api.modify_item(item, password: 'fmtopat_updated')
    api.release(item)

    operations = functions.calls.map { |call| call.fetch(:operation) }
    assert_equal %i[add find modify release], operations
    modify_arguments = functions.calls.fetch(2).fetch(:arguments)
    assert_equal ['fmtopat_updated'.bytesize, 'fmtopat_updated'], modify_arguments.values_at(2, 3)
    assert_equal 0x1234, functions.calls.fetch(3).fetch(:arguments).first.to_i
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
