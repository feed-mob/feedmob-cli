# frozen_string_literal: true

require_relative 'test_helper'
require 'feedmob/cli/output'

class OutputTest < Minitest::Test
  def test_json_success_uses_stable_envelope
    stdout = StringIO.new
    output = FeedMob::CLI::Output.new(stdout:, stderr: StringIO.new, json: true)

    output.success(service: 'pixel', authenticated: true)

    assert_equal(
      { 'ok' => true, 'data' => { 'service' => 'pixel', 'authenticated' => true } },
      JSON.parse(stdout.string)
    )
  end

  def test_json_error_uses_stable_envelope_without_secret_details
    stdout = StringIO.new
    output = FeedMob::CLI::Output.new(stdout:, stderr: StringIO.new, json: true)

    output.error(code: 'credential_missing', message: 'No Pixel credential is configured.')

    assert_equal(
      {
        'ok' => false,
        'error' => {
          'code' => 'credential_missing',
          'message' => 'No Pixel credential is configured.'
        }
      },
      JSON.parse(stdout.string)
    )
  end

  def test_human_success_and_error_use_separate_streams
    stdout = StringIO.new
    stderr = StringIO.new
    output = FeedMob::CLI::Output.new(stdout:, stderr:, json: false)

    output.success(message: 'Authenticated as developer@feedmob.com')
    output.error(code: 'network_error', message: 'Pixel is unavailable.')

    assert_equal "Authenticated as developer@feedmob.com\n", stdout.string
    assert_equal "Error: Pixel is unavailable.\n", stderr.string
  end
end
