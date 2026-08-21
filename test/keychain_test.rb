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

  class FakeNativeReader
    attr_reader :reads

    def initialize(status: FeedMob::CLI::Keychain::NativeReader::SUCCESS, password: 'fmpat_secret')
      @status = status
      @password = password
      @reads = []
    end

    def read(account:, service:)
      @reads << { account:, service: }
      FeedMob::CLI::Keychain::NativeReader::Result.new(status: @status, password: @password)
    end
  end

  class FakeSecurityAPI
    attr_reader :calls

    def initialize(add_status: 0, find_result: nil, modify_status: nil, read_result: nil)
      @add_status = add_status
      @find_result = find_result
      @modify_status = modify_status
      @read_result = read_result
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

    def read_generic_password(account:, service:)
      @calls << { operation: :read, account:, service: }
      @read_result
    end

    def release(item)
      @calls << { operation: :release, item: }
    end
  end

  class FakeSecurityFunctions
    attr_reader :calls

    def initialize(status: 0, item_address: 0x1234, password: 'fmpat_secret')
      @status = status
      @item_address = item_address
      @password = password
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
      password_length_output, password_output, item_output = arguments.values_at(5, 6, 7)
      if password_length_output
        @password_data = Fiddle::Pointer.malloc(@password.bytesize)
        @password_data[0, @password.bytesize] = @password
        password_length_output[0, Fiddle::SIZEOF_INT] = [@password.bytesize].pack('I')
        password_output[0, Fiddle::SIZEOF_VOIDP] = [@password_data.to_i].pack('J')
      end
      item_output[0, Fiddle::SIZEOF_VOIDP] = [@item_address].pack('J')
      @status
    end

    def SecKeychainItemFreeContent(*arguments)
      @calls << { operation: :free_content, arguments: }
      0
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

  def test_native_reader_releases_the_keychain_item_reference
    api = FakeSecurityAPI.new(read_result: [0, 'fmpat_secret', :item_reference])
    reader = FeedMob::CLI::Keychain::NativeReader.new(api:)

    result = reader.read(account: 'fm', service: 'com.feedmob.fm.pixel')

    assert_equal 0, result.status
    assert_equal 'fmpat_secret', result.password
    operations = api.calls.map { |call| call.fetch(:operation) }
    assert_equal %i[read release], operations
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

  def test_security_framework_marshals_generic_password_reads_and_frees_returned_data
    functions = FakeSecurityFunctions.new(password: 'fmpat_native_read')
    api = FeedMob::CLI::Keychain::SecurityFramework.new(functions:)

    status, password, item = api.read_generic_password(account: 'fm', service: 'com.feedmob.fm.pixel')
    api.release(item)

    assert_equal 0, status
    assert_equal 'fmpat_native_read', password
    assert_equal 0x1234, item.to_i
    find_arguments = functions.calls.fetch(0).fetch(:arguments)
    assert_equal ['com.feedmob.fm.pixel'.bytesize, 'com.feedmob.fm.pixel'], find_arguments.values_at(1, 2)
    assert_equal ['fm'.bytesize, 'fm'], find_arguments.values_at(3, 4)
    assert_instance_of Fiddle::Pointer, find_arguments.fetch(5)
    assert_instance_of Fiddle::Pointer, find_arguments.fetch(6)
    operations = functions.calls.map { |call| call.fetch(:operation) }
    assert_equal %i[find free_content release], operations
  end

  def test_read_uses_the_native_reader_and_delete_uses_the_service_specific_item
    runner = FakeRunner.new([FakeResult.new(stdout: '', stderr: '', success?: true)])
    native_reader = FakeNativeReader.new
    keychain = FeedMob::CLI::Keychain.new(platform: 'darwin', runner:, native_reader:)

    assert_equal 'fmpat_secret', keychain.read(@service)
    assert keychain.delete(@service)
    assert_equal [{ account: 'fm', service: 'com.feedmob.fm.pixel' }], native_reader.reads
    assert_equal 1, runner.calls.length
    assert_includes runner.calls.first.fetch(:argv), 'com.feedmob.fm.pixel'
    assert_includes runner.calls.first.fetch(:argv), 'delete-generic-password'
  end

  def test_missing_keychain_item_returns_nil
    native_reader = FakeNativeReader.new(
      status: FeedMob::CLI::Keychain::NativeReader::ITEM_NOT_FOUND,
      password: nil
    )

    assert_nil FeedMob::CLI::Keychain.new(platform: 'darwin', native_reader:).read(@service)
  end

  def test_keychain_auth_failure_has_a_distinct_error_code
    native_reader = FakeNativeReader.new(
      status: FeedMob::CLI::Keychain::NativeReader::AUTH_FAILED,
      password: nil
    )
    keychain = FeedMob::CLI::Keychain.new(platform: 'darwin', native_reader:)

    error = assert_raises(FeedMob::CLI::Error) { keychain.read(@service) }

    assert_equal 'keychain_auth_failed', error.code
  end

  def test_non_macos_platform_uses_the_encrypted_fallback_store
    fallback_store = Object.new
    fallback_store.define_singleton_method(:write) { |service, token| [service.name, token] }
    fallback_store.define_singleton_method(:read) { |service| "fmpat_#{service.name}" }
    fallback_store.define_singleton_method(:delete) { |_service| true }
    keychain = FeedMob::CLI::Keychain.new(platform: 'linux', fallback_store:)

    assert_equal 'fmpat_pixel', keychain.read(@service)
    assert_equal %w[pixel fmpat_secret], keychain.write(@service, 'fmpat_secret')
    assert keychain.delete(@service)
    assert_equal 'encrypted_file', keychain.storage_source
    assert_equal 'encrypted local credential store', keychain.storage_label
  end
end
