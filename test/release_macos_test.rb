# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'release_test_helpers'

class ReleaseMacosTest < Minitest::Test
  include ReleaseTestHelpers

  def setup
    skip 'macOS-only tests' unless host_os == 'macos'
  end

  def test_release_artifact_validator_inspects_and_runs_version_smoke
    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_artifact(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(temporary_directory)

      stdout, stderr, status = run_script(
        'verify-release-artifact', '--target', host_target_id, '--tebako', tebako, artifact
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_includes stdout, "Top-level target: #{host_target_id}"
      assert_includes stdout, 'Runtime provenance: ruby@4.0.1;tebako=0.16.4;'
      assert_includes stdout, 'Version smoke: 0.1.0'
    end
  end

  def test_release_artifact_validator_rejects_an_unexpected_runtime_ref
    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_artifact(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(
        temporary_directory,
        inspect_output: "  runtime_ref: ruby@3.3.7;tebako=0.15.9;sha256=#{'f' * 64}\n"
      )

      _stdout, stderr, status = run_script(
        'verify-release-artifact', '--target', host_target_id, '--tebako', tebako, artifact
      )

      refute_predicate status, :success?
      assert_includes stderr, 'unexpected runtime_ref'
    end
  end

  def test_package_artifact_creates_one_single_binary_archive
    Dir.mktmpdir('feedmob-cli-homebrew-artifact') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      output = File.join(temporary_directory, 'output')
      compile_fake_artifact(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(temporary_directory)

      stdout, stderr, status = run_script(
        'package-homebrew-artifact',
        '--target', host_target_id,
        '--artifact', artifact,
        '--tebako', tebako,
        '--output', output
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      name = "fm-darwin-#{host_architecture}.tar.gz"
      assert_equal [name, "#{name}.sha256"], Dir.children(output).sort
      listing, listing_stderr, listing_status = Open3.capture3('tar', '-tzf', File.join(output, name))
      assert_predicate listing_status, :success?, listing_stderr
      assert_equal ['fm'], listing.lines(chomp: true)
    end
  end

  def test_tebako_tool_verifier_rejects_a_non_macho_tool
    Dir.mktmpdir('feedmob-cli-verify-tebako') do |temporary_directory|
      tool = File.join(temporary_directory, 'tebako')
      File.write(tool, "#!/bin/sh\necho tebako\n")
      FileUtils.chmod(0o755, tool)

      _stdout, stderr, status = verify_tool_with_matching_sha(tool)

      refute_predicate status, :success?
      assert_includes stderr, 'is not a Mach-O executable'
    end
  end

  def test_tebako_tool_verifier_rejects_the_wrong_cpu_architecture
    Dir.mktmpdir('feedmob-cli-verify-tebako') do |temporary_directory|
      tool = File.join(temporary_directory, 'tebako')
      foreign = host_architecture == 'arm64' ? 'x86_64' : 'arm64'
      compile_fake_artifact(tool, temporary_directory, extra_flags: ['-arch', foreign])

      _stdout, stderr, status = verify_tool_with_matching_sha(tool)

      refute_predicate status, :success?
      assert_includes stderr, "does not contain #{host_architecture} code"
    end
  end

  def test_sign_macos_artifact_reports_missing_secrets
    Dir.mktmpdir('feedmob-cli-signing') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_artifact(artifact, temporary_directory)
      env = %w[
        DEVELOPER_ID_APPLICATION_P12 DEVELOPER_ID_APPLICATION_P12_PASSWORD
        NOTARYTOOL_API_KEY_P8 NOTARYTOOL_KEY_ID NOTARYTOOL_ISSUER
      ].to_h { |name| [name, nil] }

      _stdout, stderr, status = Open3.capture3(
        env,
        RbConfig.ruby, File.join(PROJECT_ROOT, 'script', 'sign-macos-artifact'),
        '--target', host_target_id, '--tebako', __FILE__, '--artifact', artifact
      )

      refute_predicate status, :success?
      assert_includes stderr, 'Missing signing secrets: DEVELOPER_ID_APPLICATION_P12'
    end
  end

  private

  def verify_tool_with_matching_sha(tool)
    config = valid_release_config do |c|
      c.dig('tebako', 'targets', host_target_id)['tebako_sha256'] = Digest::SHA256.file(tool).hexdigest
    end
    with_config_file(config) do |config_path|
      run_script('verify-tebako-tool', '--config', config_path, '--target', host_target_id, tool)
    end
  end
end
