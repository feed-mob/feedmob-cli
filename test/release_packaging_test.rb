# frozen_string_literal: true

require_relative 'test_helper'
require 'bundler'
require 'digest'
require 'fileutils'
require 'json'
require 'rbconfig'
require 'tmpdir'

class ReleasePackagingTest < Minitest::Test
  PROJECT_ROOT = File.expand_path('..', __dir__)

  def test_prepare_release_root_contains_only_runtime_application_files
    Dir.mktmpdir('feedmob-cli-release-root') do |temporary_directory|
      destination = File.join(temporary_directory, 'root')
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/prepare-release-root'),
        destination,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal %w[Gemfile Gemfile.lock exe lib], Dir.children(destination).sort
      assert File.executable?(File.join(destination, 'exe/fm'))

      lockfile = Bundler::LockfileParser.new(File.read(File.join(destination, 'Gemfile.lock')))
      assert_equal %w[dry-cli fiddle], lockfile.dependencies.keys.sort
      assert_equal %w[dry-cli fiddle], lockfile.specs.map(&:name).sort
    end
  end

  def test_prepare_release_root_refuses_to_merge_into_a_nonempty_destination
    Dir.mktmpdir('feedmob-cli-release-root') do |temporary_directory|
      destination = File.join(temporary_directory, 'root')
      FileUtils.mkdir_p(destination)
      sentinel = File.join(destination, 'keep-me')
      File.write(sentinel, 'existing')

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/prepare-release-root'),
        destination,
        chdir: PROJECT_ROOT
      )

      refute_predicate status, :success?
      assert_includes stderr, 'Destination is not empty'
      assert_equal 'existing', File.read(sentinel)
      refute_path_exists File.join(destination, 'exe/fm')
    end
  end

  def test_release_artifact_validator_rejects_a_non_mach_o_file
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(PROJECT_ROOT, 'script/verify-release-artifact'),
      '--architecture', 'arm64',
      File.join(PROJECT_ROOT, 'exe/fm'),
      chdir: PROJECT_ROOT
    )

    refute_predicate status, :success?
    assert_includes stderr, 'is not a Mach-O executable'
  end

  def test_release_artifact_validator_rejects_the_wrong_architecture
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-thin-binary') do |temporary_directory|
      arm_binary = File.join(temporary_directory, 'arm64e-true')
      _stdout, stderr, status = Open3.capture3(
        'lipo', '/usr/bin/true', '-thin', 'arm64e', '-output', arm_binary
      )
      assert_predicate status, :success?, stderr

      _stdout, validator_stderr, validator_status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-release-artifact'),
        '--architecture', 'x86_64',
        arm_binary,
        chdir: PROJECT_ROOT
      )

      refute_predicate validator_status, :success?
      assert_includes validator_stderr, 'does not contain x86_64 code'
    end
  end

  def test_release_tree_validator_rejects_an_embedded_mach_o_for_the_wrong_architecture
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-release-tree') do |temporary_directory|
      embedded_binary = File.join(temporary_directory, 'embedded-arm64e')
      thin_system_binary('arm64e', embedded_binary)

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-release-tree'),
        '--architecture', 'x86_64',
        temporary_directory,
        chdir: PROJECT_ROOT
      )

      refute_predicate status, :success?
      assert_includes stderr, 'embedded-arm64e does not contain x86_64 code'
    end
  end

  def test_release_tree_validator_accepts_compatible_embedded_mach_o_files
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-release-tree') do |temporary_directory|
      embedded_binary = File.join(temporary_directory, 'embedded-x86_64')
      thin_system_binary('x86_64', embedded_binary)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-release-tree'),
        '--architecture', 'x86_64',
        temporary_directory,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, stderr
      assert_includes stdout, 'Embedded Mach-O files: 1'
    end
  end

  def test_release_artifact_validator_extracts_and_runs_a_version_smoke
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      architecture = `uname -m`.strip
      artifact = File.join(temporary_directory, 'fake-fm')
      compile_fake_tebako_artifact(architecture, artifact, temporary_directory)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-release-artifact'),
        '--architecture', architecture,
        artifact,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, stderr
      assert_includes stdout, 'Embedded Mach-O files: 0'
      assert_includes stdout, 'Version smoke: 0.1.0'
    end
  end

  def test_tebako_tool_verifier_accepts_a_binary_matching_the_pinned_digest
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-tebako-pin') do |temporary_directory|
      config = File.join(temporary_directory, 'release.yml')
      File.write(config, release_config(Digest::SHA256.file('/usr/bin/true').hexdigest))

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-tebako-tool'),
        '--config', config,
        '--architecture', 'arm64',
        '/usr/bin/true',
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, stderr
      assert_includes stdout, 'Tebako tool verified for macos-arm64'
    end
  end

  def test_tebako_tool_verifier_rejects_a_digest_mismatch
    skip 'macOS release validation only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-tebako-pin') do |temporary_directory|
      config = File.join(temporary_directory, 'release.yml')
      File.write(config, release_config('0' * 64))

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/verify-tebako-tool'),
        '--config', config,
        '--architecture', 'arm64',
        '/usr/bin/true',
        chdir: PROJECT_ROOT
      )

      refute_predicate status, :success?
      assert_includes stderr, 'SHA-256 mismatch'
    end
  end

  def test_press_release_artifact_consumes_pins_and_runs_the_full_validation_gate
    skip 'macOS release packaging only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-fake-tebako') do |temporary_directory|
      architecture = `uname -m`.strip
      tebako = File.join(temporary_directory, 'fake-tebako')
      log = File.join(temporary_directory, 'tebako-arguments')
      output = File.join(temporary_directory, 'artifacts/fm')
      config = File.join(temporary_directory, 'release.yml')
      compile_fake_tebako_artifact(architecture, tebako, temporary_directory)
      File.write(config, release_config(Digest::SHA256.file(tebako).hexdigest))

      stdout, stderr, status = Open3.capture3(
        { 'FM_FAKE_TEBAKO_LOG' => log },
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/press-release-artifact'),
        '--config', config,
        '--architecture', architecture,
        '--tebako', tebako,
        '--output', output,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_path_exists output
      assert_includes stdout, 'Version smoke: 0.1.0'
      arguments = File.readlines(log, chomp: true)
      assert_equal 'exe/fm', arguments.fetch(arguments.index('-e') + 1)
      assert_equal '4.0.1', arguments.fetch(arguments.index('-R') + 1)
      assert_equal 'fat', arguments.fetch(arguments.index('-m') + 1)
      assert_equal 'test-format', arguments.fetch(arguments.index('--tebako-version') + 1)
    end
  end

  def test_homebrew_release_packager_creates_two_single_binary_archives_and_checksums
    skip 'macOS release packaging only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-homebrew-release') do |temporary_directory|
      arm64_artifact = File.join(temporary_directory, 'fm-arm64')
      x86_64_artifact = File.join(temporary_directory, 'fm-x86_64')
      output = File.join(temporary_directory, 'release')
      compile_fake_tebako_artifact('arm64', arm64_artifact, temporary_directory)
      compile_fake_tebako_artifact('x86_64', x86_64_artifact, temporary_directory)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/package-homebrew-release'),
        '--arm64', arm64_artifact,
        '--x86-64', x86_64_artifact,
        '--output', output,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal %w[SHA256SUMS fm-darwin-arm64.tar.gz fm-darwin-x86_64.tar.gz],
                   Dir.children(output).sort

      expected_checksums = []
      { 'arm64' => 'fm-darwin-arm64.tar.gz', 'x86_64' => 'fm-darwin-x86_64.tar.gz' }.each do |architecture, name|
        archive = File.join(output, name)
        listing, listing_stderr, listing_status = Open3.capture3('tar', '-tzf', archive)
        assert_predicate listing_status, :success?, listing_stderr
        assert_equal ['fm'], listing.lines(chomp: true)

        extracted = File.join(temporary_directory, "extracted-#{architecture}")
        FileUtils.mkdir_p(extracted)
        _extract_stdout, extract_stderr, extract_status = Open3.capture3(
          'tar', '-xzf', archive, '-C', extracted
        )
        assert_predicate extract_status, :success?, extract_stderr
        binary = File.join(extracted, 'fm')
        assert File.executable?(binary)

        lipo_stdout, lipo_stderr, lipo_status = Open3.capture3('lipo', '-archs', binary)
        assert_predicate lipo_status, :success?, lipo_stderr
        compatible = architecture == 'arm64' ? %w[arm64 arm64e] : ['x86_64']
        assert lipo_stdout.split.intersect?(compatible)
        expected_checksums << "#{Digest::SHA256.file(archive).hexdigest}  #{name}"
      end

      assert_equal expected_checksums.sort,
                   File.readlines(File.join(output, 'SHA256SUMS'), chomp: true).sort
    end
  end

  def test_homebrew_release_packager_rejects_an_artifact_for_the_wrong_architecture
    skip 'macOS release packaging only runs on macOS' unless RUBY_PLATFORM.include?('darwin')

    Dir.mktmpdir('feedmob-cli-homebrew-release') do |temporary_directory|
      arm64_artifact = File.join(temporary_directory, 'fm-arm64')
      output = File.join(temporary_directory, 'release')
      compile_fake_tebako_artifact('arm64', arm64_artifact, temporary_directory)

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/package-homebrew-release'),
        '--arm64', arm64_artifact,
        '--x86-64', arm64_artifact,
        '--output', output,
        chdir: PROJECT_ROOT
      )

      refute_predicate status, :success?
      assert_includes stderr, 'does not contain x86_64 code'
      refute_path_exists output
    end
  end

  def test_homebrew_formula_renderer_selects_the_matching_private_release_asset
    Dir.mktmpdir('feedmob-cli-homebrew-formula') do |temporary_directory|
      formula = File.join(temporary_directory, 'fm.rb')
      arm64_sha = 'a' * 64
      x86_64_sha = 'b' * 64

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(PROJECT_ROOT, 'script/render-homebrew-formula'),
        '--version', '0.1.0',
        '--arm64-asset-id', '111',
        '--arm64-sha256', arm64_sha,
        '--x86-64-asset-id', '222',
        '--x86-64-sha256', x86_64_sha,
        '--output', formula,
        chdir: PROJECT_ROOT
      )

      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      syntax_stdout, syntax_stderr, syntax_status = Open3.capture3(RbConfig.ruby, '-c', formula)
      assert_predicate syntax_status, :success?, "#{syntax_stdout}\n#{syntax_stderr}"

      arm64_formula = evaluate_formula(formula, 'arm64')
      assert_equal 'https://api.github.com/repos/feed-mob/feedmob-cli/releases/assets/111', arm64_formula.fetch('url')
      assert_equal arm64_sha, arm64_formula.fetch('sha256')
      assert_equal 'fm', arm64_formula.fetch('installed')

      x86_64_formula = evaluate_formula(formula, 'x86_64')
      assert_equal 'https://api.github.com/repos/feed-mob/feedmob-cli/releases/assets/222', x86_64_formula.fetch('url')
      assert_equal x86_64_sha, x86_64_formula.fetch('sha256')
      assert_equal 'fm', x86_64_formula.fetch('installed')
    end
  end

  private

  def thin_system_binary(architecture, destination)
    _stdout, stderr, status = Open3.capture3(
      'lipo', '/usr/bin/true', '-thin', architecture, '-output', destination
    )
    assert_predicate status, :success?, stderr
  end

  def compile_fake_tebako_artifact(architecture, artifact, temporary_directory)
    source = File.join(temporary_directory, 'fake_fm.c')
    File.write(
      source,
      <<~'C'
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <sys/stat.h>

        static int copy_file(const char *source, const char *destination) {
          FILE *input = fopen(source, "rb");
          FILE *output = fopen(destination, "wb");
          char buffer[8192];
          size_t count;
          if (!input || !output) return 3;
          while ((count = fread(buffer, 1, sizeof(buffer), input)) > 0) {
            if (fwrite(buffer, 1, count, output) != count) return 4;
          }
          fclose(input);
          fclose(output);
          chmod(destination, 0755);
          return 0;
        }

        int main(int argc, char **argv) {
          if (argc == 3 && strcmp(argv[1], "--tebako-extract") == 0) return 0;
          if (argc == 3 && strcmp(argv[1], "--json") == 0 && strcmp(argv[2], "version") == 0) {
            puts("{\"ok\":true,\"data\":{\"version\":\"0.1.0\"}}");
            return 0;
          }
          if (argc > 1 && strcmp(argv[1], "press") == 0) {
            const char *log_path = getenv("FM_FAKE_TEBAKO_LOG");
            FILE *log = log_path ? fopen(log_path, "w") : NULL;
            const char *output_path = NULL;
            for (int index = 1; index < argc; index++) {
              if (log) fprintf(log, "%s\n", argv[index]);
              if (strcmp(argv[index], "-o") == 0 && index + 1 < argc) output_path = argv[index + 1];
            }
            if (log) fclose(log);
            return output_path ? copy_file(argv[0], output_path) : 5;
          }
          return 2;
        }
      C
    )

    _stdout, stderr, status = Open3.capture3(
      'xcrun', 'clang', '-arch', architecture, source, '-o', artifact
    )
    assert_predicate status, :success?, stderr
  end

  def release_config(sha256)
    <<~YAML
      tebako:
        release_version: "test-release"
        format_version: "test-format"
        ruby_version: "4.0.1"
        assets:
          macos-arm64:
            sha256: "#{sha256}"
    YAML
  end

  def evaluate_formula(path, architecture)
    evaluator = <<~RUBY
      require 'json'

      module Hardware
        module CPU
          def self.arm?
            ARGV.fetch(0) == 'arm64'
          end
        end
      end

      class Formula
        class BinStub
          attr_reader :installed

          def install(value)
            @installed = value
          end
        end

        class << self
          attr_reader :selected_url, :selected_sha256

          def desc(*) = nil
          def homepage(*) = nil
          def license(*) = nil
          def version(*) = nil
          def test(*) = nil

          def url(value, **) = @selected_url = value
          def sha256(value) = @selected_sha256 = value
        end

        def bin
          @bin ||= BinStub.new
        end

        def result
          {
            url: self.class.selected_url,
            sha256: self.class.selected_sha256,
            installed: bin.installed
          }
        end
      end

      ENV['HOMEBREW_GITHUB_API_TOKEN'] = 'test-token'
      load ARGV.fetch(1)
      formula = Fm.new
      formula.install
      puts JSON.generate(formula.result)
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', evaluator, architecture, path)
    assert_predicate status, :success?, stderr
    JSON.parse(stdout)
  end
end
