# frozen_string_literal: true

require_relative 'test_helper'

class CliHelpTest < Minitest::Test
  def test_top_level_help_lists_service_namespaces_and_doctor
    stdout, stderr, status = Open3.capture3(
      { 'BUNDLE_GEMFILE' => File.expand_path('../Gemfile', __dir__) },
      File.expand_path('../exe/fm', __dir__),
      '--help'
    )

    assert_predicate status, :success?, stderr
    assert_includes stdout, 'doctor'
    assert_includes stdout, 'femini'
    assert_includes stdout, 'pages'
    assert_includes stdout, 'pixel'
    assert_includes stdout, 'time-off'
    assert_includes stdout, 'workspace'
  end
end
