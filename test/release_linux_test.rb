# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'release_test_helpers'

class ReleaseLinuxTest < Minitest::Test
  include ReleaseTestHelpers

  ELF_MACHINE_OFFSET = 18
  ELF_MACHINE_IDS = { 'x86_64' => 62, 'arm64' => 183 }.freeze

  def setup
    skip 'Linux-only tests' unless host_os == 'linux'
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
      assert_includes stdout, "Version smoke: #{FeedMob::CLI::VERSION}"
    end
  end

  def test_release_artifact_validator_rejects_the_wrong_elf_machine
    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_artifact(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(temporary_directory)
      foreign = host_architecture == 'arm64' ? 'x86_64' : 'arm64'
      patch_elf_machine(artifact, ELF_MACHINE_IDS.fetch(foreign))

      _stdout, stderr, status = run_script(
        'verify-release-artifact', '--target', host_target_id, '--tebako', tebako, artifact
      )

      refute_predicate status, :success?
      assert_includes stderr, "does not contain #{host_architecture} code"
    end
  end

  def test_release_artifact_validator_enforces_the_configured_glibc_baseline
    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_artifact(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(temporary_directory)
      config = valid_release_config do |c|
        c.dig('tebako', 'targets', host_target_id)['glibc_max'] = '2.0'
      end

      with_config_file(config) do |config_path|
        _stdout, stderr, status = run_script(
          'verify-release-artifact',
          '--config', config_path, '--target', host_target_id, '--tebako', tebako, artifact
        )

        refute_predicate status, :success?
        assert_includes stderr, 'exceeding configured GLIBC_2.0'
      end
    end
  end

  def test_release_artifact_validator_rejects_missing_dynamic_dependencies
    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_with_vanished_dependency(artifact, temporary_directory)
      tebako = write_fake_tebako_tool(temporary_directory)

      _stdout, stderr, status = run_script(
        'verify-release-artifact', '--target', host_target_id, '--tebako', tebako, artifact
      )

      refute_predicate status, :success?
      assert_includes stderr, 'Missing dynamic dependency'
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
      name = "fm-linux-#{host_architecture}.tar.gz"
      assert_equal [name, "#{name}.sha256"], Dir.children(output).sort
      listing, listing_stderr, listing_status = Open3.capture3('tar', '-tzf', File.join(output, name))
      assert_predicate listing_status, :success?, listing_stderr
      assert_equal ['fm'], listing.lines(chomp: true)
    end
  end

  def test_tebako_tool_verifier_rejects_a_non_elf_tool
    Dir.mktmpdir('feedmob-cli-verify-tebako') do |temporary_directory|
      tool = File.join(temporary_directory, 'tebako')
      File.write(tool, "#!/bin/sh\necho tebako\n")
      FileUtils.chmod(0o755, tool)
      config = valid_release_config do |c|
        c.dig('tebako', 'targets', host_target_id)['tebako_sha256'] = Digest::SHA256.file(tool).hexdigest
      end

      with_config_file(config) do |config_path|
        _stdout, stderr, status = run_script(
          'verify-tebako-tool', '--config', config_path, '--target', host_target_id, tool
        )

        refute_predicate status, :success?
        assert_includes stderr, 'is not an ELF executable'
      end
    end
  end

  private

  def patch_elf_machine(path, machine_id)
    bytes = File.binread(path).bytes
    bytes[ELF_MACHINE_OFFSET] = machine_id & 0xFF
    bytes[ELF_MACHINE_OFFSET + 1] = (machine_id >> 8) & 0xFF
    File.binwrite(path, bytes.pack('C*'))
  end

  def compile_with_vanished_dependency(artifact, temporary_directory)
    library_source = File.join(temporary_directory, 'fakedep.c')
    main_source = File.join(temporary_directory, 'main.c')
    library = File.join(temporary_directory, 'libfakedep.so')
    File.write(library_source, "int fakedep_symbol(void) { return 42; }\n")
    File.write(main_source, "extern int fakedep_symbol(void); int main(void) { return fakedep_symbol(); }\n")

    compiler = ENV.fetch('CC', 'cc')
    _out, stderr, status = Open3.capture3(compiler, '-shared', '-fPIC', library_source, '-o', library)
    assert_predicate status, :success?, stderr
    _out, stderr, status = Open3.capture3(
      compiler, main_source, '-o', artifact, "-L#{temporary_directory}", '-lfakedep',
      "-Wl,-rpath,#{temporary_directory}"
    )
    assert_predicate status, :success?, stderr
    FileUtils.rm(library)
  end
end
