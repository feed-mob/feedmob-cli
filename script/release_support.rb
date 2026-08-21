# frozen_string_literal: true

require 'digest'
require 'open3'
require 'rbconfig'
require 'uri'
require 'yaml'

module FeedMobRelease # rubocop:disable Metrics/ModuleLength
  TARGET_IDS = %w[macos-arm64 macos-x86_64 linux-arm64 linux-x86_64].freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  VERSION_PATTERN = /\A\d+\.\d+(?:\.\d+)?\z/

  module_function

  def load_config(path)
    config = YAML.safe_load_file(path, aliases: false).fetch('tebako')
    %w[release_version format_version ruby_version targets].each { |key| config.fetch(key) }
    abort 'release.yml targets must be a mapping' unless config['targets'].is_a?(Hash)
    unless config['targets'].keys.sort == TARGET_IDS.sort
      abort "release.yml targets must be exactly: #{TARGET_IDS.join(', ')}"
    end

    config['targets'].each do |id, target|
      validate_target!(id, target)
    end
    config
  rescue KeyError => e
    abort "Invalid release configuration: missing #{e.key}"
  rescue Psych::Exception => e
    abort "Invalid release configuration: #{e.message}"
  end

  def target!(config, id)
    abort "Unknown release target: #{id}" unless TARGET_IDS.include?(id)

    config.fetch('targets').fetch(id)
  end

  def current_os
    case RbConfig::CONFIG.fetch('host_os')
    when /darwin/i then 'macos'
    when /linux/i then 'linux'
    else
      abort "Unsupported release host OS: #{RbConfig::CONFIG.fetch('host_os')}"
    end
  end

  def current_architecture
    machine = RbConfig::CONFIG.fetch('host_cpu').downcase
    return 'arm64' if %w[arm64 aarch64].include?(machine)
    return 'x86_64' if %w[x86_64 amd64].include?(machine)

    abort "Unsupported release host architecture: #{machine}"
  end

  def assert_native_target!(id, target)
    actual = "#{current_os}-#{current_architecture}"
    return if target.fetch('os') == current_os && target.fetch('architecture') == current_architecture

    abort "Release target #{id} requires #{target.fetch('os')}-#{target.fetch('architecture')}, running on #{actual}"
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def elf?(path)
    File.binread(path, 4) == "\x7FELF"
  rescue Errno::ENOENT, Errno::EISDIR
    false
  end

  def macho_architectures(path)
    stdout, _stderr, status = Open3.capture3('lipo', '-archs', path)
    return nil unless status.success?

    stdout.split
  end

  def validate_binary_format!(path, target)
    return validate_macho!(path, target) if target.fetch('os') == 'macos'

    validate_elf!(path, target)
  end

  def validate_macho!(path, target)
    architectures = macho_architectures(path)
    abort "#{path} is not a Mach-O executable" unless architectures

    compatible = target.fetch('architecture') == 'arm64' ? %w[arm64 arm64e] : ['x86_64']
    return if architectures.intersect?(compatible)

    abort "#{path} does not contain #{target.fetch('architecture')} code (found: #{architectures.join(', ')})"
  end

  def validate_elf!(path, target)
    abort "#{path} is not an ELF executable" unless elf?(path)

    machine = elf_machine(path)
    expected = target.fetch('architecture') == 'arm64' ? 'AArch64' : 'Advanced Micro Devices X86-64'
    return if machine == expected

    abort "#{path} does not contain #{target.fetch('architecture')} code (found: #{machine || 'unknown'})"
  end

  def elf_machine(path)
    stdout, _stderr, status = Open3.capture3('readelf', '-h', path)
    return nil unless status.success?

    stdout[/^\s*Machine:\s*(.+)$/i, 1]&.strip
  end

  def glibc_versions(path)
    stdout, _stderr, status = Open3.capture3('readelf', '--version-info', path)
    return [] unless status.success?

    stdout.scan(/GLIBC_(\d+\.\d+)/).flatten.uniq.map { |version| version.split('.').map(&:to_i) }
  end

  def version_at_most?(actual, maximum)
    (actual <=> maximum.split('.').map(&:to_i)) <= 0
  end

  def verify_glibc_requirement!(path, target)
    return unless target.fetch('os') == 'linux'

    maximum = target.fetch('glibc_max')
    offending = glibc_versions(path).reject { |version| version_at_most?(version, maximum) }
    return if offending.empty?

    formatted = offending.map { |version| version.join('.') }.sort.join(', ')
    abort "#{path} requires GLIBC_#{formatted}, exceeding configured GLIBC_#{maximum}"
  end

  def verify_dynamic_dependencies!(path)
    stdout, stderr, status = Open3.capture3('ldd', path)
    output = "#{stdout}#{stderr}"
    return if output.match?(/not a dynamic executable|statically linked/i)

    abort "Could not inspect dynamic dependencies for #{path}: #{output}" unless status.success?
    abort "Missing dynamic dependency for #{path}: #{output}" if output.match?(/not found/i)
  end

  def validate_target!(id, target)
    abort "release.yml target #{id} must be a mapping" unless target.is_a?(Hash)

    validate_target_identity!(id, target)
    validate_target_archive!(id, target)
    validate_target_tebako!(id, target)
    validate_target_glibc!(id, target)
  rescue KeyError => e
    abort "release.yml target #{id} is missing #{e.key}"
  end

  def validate_target_identity!(id, target)
    expected_os, expected_architecture = id.split('-', 2)
    abort "release.yml target #{id} has invalid os" unless target['os'] == expected_os
    abort "release.yml target #{id} has invalid architecture" unless target['architecture'] == expected_architecture
  end

  def validate_target_archive!(id, target)
    expected_os, expected_architecture = id.split('-', 2)
    expected_archive = "fm-#{expected_os == 'macos' ? 'darwin' : 'linux'}-#{expected_architecture}.tar.gz"
    abort "release.yml target #{id} has invalid archive" unless target['archive'] == expected_archive
  end

  def validate_target_tebako!(id, target)
    abort "release.yml target #{id} has invalid Tebako URL" unless URI(target.fetch('tebako_url')).is_a?(URI::HTTPS)
    return if target.fetch('tebako_sha256').match?(SHA256_PATTERN)

    abort "release.yml target #{id} has invalid Tebako SHA-256"
  end

  def validate_target_glibc!(id, target)
    expected_os, = id.split('-', 2)
    if expected_os == 'linux'
      abort "release.yml target #{id} requires glibc_max" unless target['glibc_max'].to_s.match?(VERSION_PATTERN)
    elsif target.key?('glibc_max')
      abort "release.yml target #{id} must not define glibc_max"
    end
  end
end
