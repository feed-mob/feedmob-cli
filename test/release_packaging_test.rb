# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'release_test_helpers'
require 'bundler'

class ReleasePackagingTest < Minitest::Test
  include ReleaseTestHelpers

  def test_release_configuration_declares_all_native_targets
    output, _stderr, status = run_release_support(
      'config = FeedMobRelease.load_config("packaging/release.yml"); puts config.fetch("targets").keys.sort'
    )

    assert_predicate status, :success?
    assert_equal TARGET_IDS.sort, output.lines(chomp: true)
  end

  def test_release_configuration_requires_top_level_versions
    %w[release_version format_version ruby_version].each do |key|
      config = valid_release_config { |c| c.fetch('tebako').delete(key) }
      assert_config_invalid config, "missing #{key}"
    end
  end

  def test_release_configuration_rejects_unknown_targets
    config = valid_release_config do |c|
      c.fetch('tebako').fetch('targets')['linux-arm32'] = c.fetch('tebako').fetch('targets').delete('linux-arm64')
    end

    assert_config_invalid config, 'targets must be exactly'
  end

  def test_release_configuration_rejects_a_target_os_mismatch
    config = valid_release_config { |c| c.dig('tebako', 'targets', 'macos-arm64')['os'] = 'linux' }

    assert_config_invalid config, 'macos-arm64 has invalid os'
  end

  def test_release_configuration_rejects_a_target_architecture_mismatch
    config = valid_release_config { |c| c.dig('tebako', 'targets', 'linux-x86_64')['architecture'] = 'arm64' }

    assert_config_invalid config, 'linux-x86_64 has invalid architecture'
  end

  def test_release_configuration_rejects_duplicate_or_unexpected_archive_names
    config = valid_release_config do |c|
      c.dig('tebako', 'targets', 'linux-arm64')['archive'] = 'fm-linux-x86_64.tar.gz'
    end

    assert_config_invalid config, 'linux-arm64 has invalid archive'
  end

  def test_release_configuration_requires_https_tebako_urls
    config = valid_release_config do |c|
      c.dig('tebako', 'targets', 'macos-arm64')['tebako_url'] = 'http://example.com/tebako'
    end

    assert_config_invalid config, 'macos-arm64 has invalid Tebako URL'
  end

  def test_release_configuration_requires_a_lowercase_sha256
    config = valid_release_config do |c|
      c.dig('tebako', 'targets', 'linux-x86_64')['tebako_sha256'] = 'A' * 64
    end

    assert_config_invalid config, 'linux-x86_64 has invalid Tebako SHA-256'
  end

  def test_release_configuration_requires_glibc_max_only_for_linux_targets
    missing = valid_release_config { |c| c.dig('tebako', 'targets', 'linux-arm64').delete('glibc_max') }
    assert_config_invalid missing, 'linux-arm64 requires glibc_max'

    forbidden = valid_release_config { |c| c.dig('tebako', 'targets', 'macos-arm64')['glibc_max'] = '2.35' }
    assert_config_invalid forbidden, 'macos-arm64 must not define glibc_max'
  end

  def test_native_target_mismatch_reports_expected_and_actual_without_environment
    foreign = TARGET_IDS.reject { |id| id == host_target_id }.first
    with_config_file(valid_release_config) do |path|
      _stdout, stderr, status = run_release_support(
        'config = FeedMobRelease.load_config(ARGV.fetch(0)); ' \
        'FeedMobRelease.assert_native_target!(ARGV.fetch(1), FeedMobRelease.target!(config, ARGV.fetch(1)))',
        path, foreign
      )

      refute_predicate status, :success?
      assert_includes stderr, "requires #{foreign}"
      assert_includes stderr, "running on #{host_target_id}"
      refute_includes stderr, Dir.home
    end
  end

  def test_fetch_tebako_tool_refuses_to_replace_a_non_matching_existing_file
    Dir.mktmpdir('feedmob-cli-fetch-tebako') do |temporary_directory|
      output = File.join(temporary_directory, 'tebako')
      File.write(output, 'unexpected content')

      _stdout, stderr, status = run_script(
        'fetch-tebako-tool', '--target', host_target_id, '--output', output
      )

      refute_predicate status, :success?
      assert_includes stderr, 'Refusing to replace existing non-matching Tebako tool'
      assert_equal 'unexpected content', File.read(output)
    end
  end

  def test_smoke_release_auth_only_runs_on_linux
    skip 'Linux hosts run the full smoke in the release workflow' if host_os == 'linux'

    _stdout, stderr, status = run_script('smoke-release-auth', '--artifact', __FILE__)

    refute_predicate status, :success?
    assert_includes stderr, 'only runs on Linux'
  end

  def test_publish_release_requires_a_token
    _stdout, stderr, status = Open3.capture3(
      { 'GH_TOKEN' => nil },
      RbConfig.ruby, File.join(PROJECT_ROOT, 'script', 'publish-release'),
      '--version', '0.1.0', '--input', __dir__
    )

    refute_predicate status, :success?
    assert_includes stderr, 'GH_TOKEN is not set'
  end

  def test_publish_release_rejects_a_manifest_version_mismatch
    Dir.mktmpdir('feedmob-cli-publish') do |temporary_directory|
      File.write(
        File.join(temporary_directory, 'release-assets.json'),
        JSON.generate('version' => '9.9.9', 'assets' => {})
      )

      _stdout, stderr, status = Open3.capture3(
        { 'GH_TOKEN' => 'unused' },
        RbConfig.ruby, File.join(PROJECT_ROOT, 'script', 'publish-release'),
        '--version', '0.1.0', '--input', temporary_directory
      )

      refute_predicate status, :success?
      assert_includes stderr, 'does not match 0.1.0'
    end
  end

  def test_prepare_release_root_contains_only_runtime_application_files
    Dir.mktmpdir('feedmob-cli-release-root') do |temporary_directory|
      destination = File.join(temporary_directory, 'root')
      stdout, stderr, status = run_script('prepare-release-root', destination)

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal %w[Gemfile Gemfile.lock exe lib], Dir.children(destination).sort
      assert File.executable?(File.join(destination, 'exe/fm'))

      lockfile = Bundler::LockfileParser.new(File.read(File.join(destination, 'Gemfile.lock')))
      assert_equal %w[dry-cli fiddle], lockfile.dependencies.keys.sort
      assert_equal %w[dry-cli fiddle], lockfile.specs.map(&:name).sort
    end
  end

  def test_formula_renderer_emits_four_os_and_cpu_branches
    with_rendered_formula(formula_manifest) do |rendered, formula|
      syntax_stdout, syntax_stderr, syntax_status = Open3.capture3(RbConfig.ruby, '-c', formula)
      assert_predicate syntax_status, :success?, "#{syntax_stdout}\n#{syntax_stderr}"
      assert_includes rendered, 'on_macos do'
      assert_includes rendered, 'on_linux do'
      assert_equal 2, rendered.scan('on_arm do').length
      assert_equal 2, rendered.scan('on_intel do').length
      formula_manifest.fetch('assets').each_value do |asset|
        assert_includes rendered, "/releases/download/v0.1.0/#{asset.fetch('name')}"
        assert_includes rendered, asset.fetch('sha256')
      end
      refute_includes rendered, 'HOMEBREW_GITHUB_API_TOKEN'
    end
  end

  def test_formula_renderer_places_each_asset_in_its_os_and_cpu_branch
    with_rendered_formula(formula_manifest) do |rendered, _formula|
      assets = formula_manifest.fetch('assets')
      url = ->(id) { "/releases/download/v0.1.0/#{assets.fetch(id).fetch('name')}" }
      intel_blocks = rendered.enum_for(:scan, 'on_intel do').map { Regexp.last_match.begin(0) }

      assert rendered.index('on_macos do') < rendered.index(url.call('macos-arm64'))
      assert rendered.index(url.call('macos-arm64')) < intel_blocks.fetch(0)
      assert intel_blocks.fetch(0) < rendered.index(url.call('macos-x86_64'))
      assert rendered.index(url.call('macos-x86_64')) < rendered.index('on_linux do')
      assert rendered.index('on_linux do') < rendered.index(url.call('linux-arm64'))
      assert rendered.index(url.call('linux-arm64')) < intel_blocks.fetch(1)
      assert intel_blocks.fetch(1) < rendered.index(url.call('linux-x86_64'))
    end
  end

  def test_formula_renderer_refuses_an_incomplete_manifest
    broken = formula_manifest
    broken.fetch('assets').delete('linux-arm64')

    assert_formula_rejected broken, 'targets must be exactly'
  end

  def test_formula_renderer_refuses_a_version_mismatch
    broken = formula_manifest
    broken['version'] = '0.2.0'

    assert_formula_rejected broken, 'version does not match'
  end

  def test_formula_renderer_refuses_an_invalid_sha256
    broken = formula_manifest
    broken.dig('assets', 'linux-x86_64')['sha256'] = 'not-a-sha'

    assert_formula_rejected broken, 'Invalid linux-x86_64 SHA-256'
  end

  def test_assembler_requires_exactly_four_archives_and_their_checksums
    Dir.mktmpdir('feedmob-cli-homebrew-assemble') do |temporary_directory|
      input = File.join(temporary_directory, 'input')
      output = File.join(temporary_directory, 'output')
      FileUtils.mkdir_p(input)
      archive_names.each do |name|
        archive = make_archive(input, name)
        File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{name}\n")
      end

      stdout, stderr, status = run_script('assemble-homebrew-release', '--input', input, '--output', output)

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      expected_files = %w[
        SHA256SUMS
        fm-darwin-arm64.tar.gz
        fm-darwin-x86_64.tar.gz
        fm-linux-arm64.tar.gz
        fm-linux-x86_64.tar.gz
        release-assets.json
      ]
      assert_equal expected_files, Dir.children(output).sort
      manifest = JSON.parse(File.read(File.join(output, 'release-assets.json')))
      assert_equal TARGET_IDS.sort, manifest.fetch('assets').keys.sort
      assert_equal '0.1.0', manifest.fetch('version')

      sums = File.read(File.join(output, 'SHA256SUMS'))
      assert_equal sums.lines.sort.join, sums
      assert sums.end_with?("\n")
    end
  end

  def test_assembler_rejects_a_missing_target_archive
    Dir.mktmpdir('feedmob-cli-homebrew-assemble') do |temporary_directory|
      input = File.join(temporary_directory, 'input')
      output = File.join(temporary_directory, 'output')
      FileUtils.mkdir_p(input)
      archive_names.first(3).each do |name|
        archive = make_archive(input, name)
        File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{name}\n")
      end

      _stdout, stderr, status = run_script('assemble-homebrew-release', '--input', input, '--output', output)

      refute_predicate status, :success?
      assert_includes stderr, 'Unexpected release input files'
      refute_path_exists output
    end
  end

  def test_assembler_rejects_a_checksum_mismatch
    Dir.mktmpdir('feedmob-cli-homebrew-assemble') do |temporary_directory|
      input = File.join(temporary_directory, 'input')
      output = File.join(temporary_directory, 'output')
      FileUtils.mkdir_p(input)
      archive_names.each do |name|
        archive = make_archive(input, name)
        File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{name}\n")
      end
      File.write(File.join(input, "#{archive_names.first}.sha256"), "#{'0' * 64}  #{archive_names.first}\n")

      _stdout, stderr, status = run_script('assemble-homebrew-release', '--input', input, '--output', output)

      refute_predicate status, :success?
      assert_includes stderr, "Checksum mismatch for #{archive_names.first}"
      refute_path_exists output
    end
  end

  private

  def assert_config_invalid(config, message)
    with_config_file(config) do |path|
      _stdout, stderr, status = run_release_support('FeedMobRelease.load_config(ARGV.fetch(0))', path)

      refute_predicate status, :success?
      assert_includes stderr, message
    end
  end

  def with_rendered_formula(manifest)
    Dir.mktmpdir('feedmob-cli-homebrew-formula') do |temporary_directory|
      manifest_path = File.join(temporary_directory, 'assets.json')
      formula = File.join(temporary_directory, 'fm.rb')
      File.write(manifest_path, JSON.generate(manifest))

      stdout, stderr, status = run_script(
        'render-homebrew-formula',
        '--version', '0.1.0',
        '--assets-json', manifest_path,
        '--output', formula
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      yield File.read(formula), formula
    end
  end

  def assert_formula_rejected(manifest, message)
    Dir.mktmpdir('feedmob-cli-homebrew-formula') do |temporary_directory|
      manifest_path = File.join(temporary_directory, 'assets.json')
      formula = File.join(temporary_directory, 'fm.rb')
      File.write(manifest_path, JSON.generate(manifest))

      _stdout, stderr, status = run_script(
        'render-homebrew-formula',
        '--version', '0.1.0',
        '--assets-json', manifest_path,
        '--output', formula
      )

      refute_predicate status, :success?
      assert_includes stderr, message
      refute_path_exists formula
    end
  end

  def formula_manifest
    {
      'version' => '0.1.0',
      'assets' => TARGET_IDS.each_with_index.to_h do |target, index|
        archive = archive_names.fetch(index)
        [target, { 'name' => archive, 'sha256' => (('a'.ord + index).chr * 64) }]
      end
    }
  end

  def archive_names
    %w[fm-darwin-arm64.tar.gz fm-darwin-x86_64.tar.gz fm-linux-arm64.tar.gz fm-linux-x86_64.tar.gz]
  end

  def make_archive(directory, name)
    staging = File.join(directory, "staging-#{name}")
    FileUtils.mkdir_p(staging)
    File.write(File.join(staging, 'fm'), '#!/bin/sh\necho fm\n')
    FileUtils.chmod(0o755, File.join(staging, 'fm'))
    archive = File.join(directory, name)
    _stdout, stderr, status = Open3.capture3('tar', '-czf', archive, '-C', staging, 'fm')
    assert_predicate status, :success?, stderr
    FileUtils.rm_rf(staging)
    archive
  end
end
