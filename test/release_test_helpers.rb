# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

module ReleaseTestHelpers
  PROJECT_ROOT = File.expand_path('..', __dir__)
  TARGET_IDS = %w[macos-arm64 macos-x86_64 linux-arm64 linux-x86_64].freeze

  def valid_release_config
    targets = TARGET_IDS.to_h do |id|
      os, architecture = id.split('-', 2)
      target = {
        'os' => os,
        'architecture' => architecture,
        'archive' => "fm-#{os == 'macos' ? 'darwin' : 'linux'}-#{architecture}.tar.gz",
        'tebako_url' => "https://example.com/tebako-#{id}",
        'tebako_sha256' => format('%02x', TARGET_IDS.index(id)) * 32
      }
      target['glibc_max'] = '2.35' if os == 'linux'
      [id, target]
    end
    config = {
      'tebako' => {
        'release_version' => '0.1.9',
        'format_version' => '0.16.4',
        'ruby_version' => '4.0.1',
        'targets' => targets
      }
    }
    yield config if block_given?
    config
  end

  def with_config_file(config)
    Dir.mktmpdir('feedmob-cli-release-config') do |directory|
      path = File.join(directory, 'release.yml')
      File.write(path, YAML.dump(config))
      yield path
    end
  end

  def host_os
    RUBY_PLATFORM.include?('darwin') ? 'macos' : 'linux'
  end

  def host_architecture
    machine = RbConfig::CONFIG.fetch('host_cpu').downcase
    return 'arm64' if %w[arm64 aarch64].include?(machine)

    'x86_64'
  end

  def host_target_id
    "#{host_os}-#{host_architecture}"
  end

  def run_script(name, *)
    Open3.capture3(RbConfig.ruby, File.join(PROJECT_ROOT, 'script', name), *, chdir: PROJECT_ROOT)
  end

  def run_release_support(code, *)
    Open3.capture3(RbConfig.ruby, '-r', './script/release_support', '-e', code, *, chdir: PROJECT_ROOT)
  end

  def compile_fake_artifact(artifact, temporary_directory, extra_flags: [])
    source = File.join(temporary_directory, 'fake_fm.c')
    File.write(
      source,
      <<~'C'
        #include <stdio.h>
        #include <string.h>
        int main(int argc, char **argv) {
          if (argc == 3 && strcmp(argv[1], "--json") == 0 && strcmp(argv[2], "version") == 0) {
            puts("{\"ok\":true,\"data\":{\"version\":\"0.1.0\"}}");
            return 0;
          }
          return 2;
        }
      C
    )

    compiler = host_os == 'macos' ? %w[xcrun clang] : [ENV.fetch('CC', 'cc')]
    _stdout, stderr, status = Open3.capture3(*compiler, source, '-o', artifact, *extra_flags)
    assert_predicate status, :success?, stderr
  end

  FAKE_INSPECT_OUTPUT = <<~OUT.freeze
    package: fake-fm (tpkg v1, lean, launcher_abi 1)
      runtime_ref: ruby@4.0.1;tebako=0.16.4;image;sha256=#{'0' * 64} (resolution hint; lean)
  OUT

  def write_fake_tebako_tool(temporary_directory, inspect_output: FAKE_INSPECT_OUTPUT)
    output_path = File.join(temporary_directory, 'inspect-output.txt')
    File.write(output_path, inspect_output)
    tool = File.join(temporary_directory, 'fake-tebako')
    File.write(tool, "#!/bin/sh\n[ \"$1\" = inspect ] && cat '#{output_path}'\n")
    FileUtils.chmod(0o755, tool)
    tool
  end
end
