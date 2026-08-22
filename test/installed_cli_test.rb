# frozen_string_literal: true

require_relative 'test_helper'
require 'rbconfig'
require 'tmpdir'

class InstalledCliTest < Minitest::Test
  def test_local_install_runs_from_a_different_working_directory
    project_root = File.expand_path('..', __dir__)

    Dir.mktmpdir('feedmob-cli-install') do |temporary_directory|
      prefix = File.join(temporary_directory, 'prefix')
      install_stdout, install_stderr, install_status = Open3.capture3(
        'make',
        'install-local',
        "PREFIX=#{prefix}",
        chdir: project_root
      )

      assert_predicate install_status, :success?, "#{install_stdout}\n#{install_stderr}"

      environment = {
        'BUNDLE_GEMFILE' => nil,
        'FEEDMOB_PIXEL_TOKEN' => nil,
        'FEEDMOB_TIME_OFF_TOKEN' => nil,
        'GEM_HOME' => nil,
        'GEM_PATH' => nil,
        'RUBYOPT' => nil,
        'PATH' => "#{File.join(prefix, 'bin')}:#{ENV.fetch('PATH')}"
      }
      Dir.mktmpdir('feedmob-cli-outside-source') do |outside_source|
        stdout, stderr, status = Open3.capture3(
          environment,
          '/bin/sh',
          '-c',
          'command -v fm && fm --json version',
          chdir: outside_source
        )

        assert_predicate status, :success?, stderr
        assert_equal File.join(prefix, 'bin', 'fm'), stdout.lines.first.strip
        assert_equal({ 'ok' => true, 'data' => { 'version' => FeedMob::CLI::VERSION } }, JSON.parse(stdout.lines.last))
      end
    end
  end

  def test_local_install_uses_path_ruby_when_rbenv_is_unavailable
    project_root = File.expand_path('..', __dir__)

    Dir.mktmpdir('feedmob-cli-ci-path') do |temporary_directory|
      runner_bin = File.join(temporary_directory, 'bin')
      Dir.mkdir(runner_bin)
      File.symlink(RbConfig.ruby, File.join(runner_bin, 'ruby'))
      File.symlink(File.join(File.dirname(RbConfig.ruby), 'gem'), File.join(runner_bin, 'gem'))

      prefix = File.join(temporary_directory, 'prefix')
      stdout, stderr, status = Open3.capture3(
        { 'PATH' => "#{runner_bin}:/usr/bin:/bin" },
        '/usr/bin/make',
        'install-local',
        "PREFIX=#{prefix}",
        chdir: project_root
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_path_exists File.join(prefix, 'bin', 'fm')
    end
  end
end
