# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'openssl'
require 'securerandom'
require_relative 'error'

module FeedMob
  module CLI
    # Fallback credential store for platforms without macOS Keychain. The
    # encryption key and ciphertext are both private to the current user; the
    # encryption protects against accidental disclosure of the credentials file
    # and detects tampering, while file permissions protect both artifacts.
    class EncryptedStore
      KEY_BYTES = 32
      NONCE_BYTES = 12
      TAG_BYTES = 16
      FILE_MODE = 0o600
      DIRECTORY_MODE = 0o700

      def initialize(env: ENV, config_dir: nil, platform: RUBY_PLATFORM)
        @config_dir = config_dir || default_config_dir(env)
        @platform = platform
      end

      def read(service)
        return nil unless File.exist?(credentials_path)

        with_lock do
          load_credentials.fetch(service.name, nil)
        end
      end

      def write(service, token)
        with_lock do
          values = load_credentials
          values[service.name] = token
          atomic_write(credentials_path, encrypt(JSON.generate(values)))
        end
      end

      def delete(service)
        return false unless File.exist?(credentials_path)

        with_lock do
          values = load_credentials
          return false unless values.delete(service.name)

          atomic_write(credentials_path, encrypt(JSON.generate(values)))
          true
        end
      end

      private

      def default_config_dir(env)
        root = env['XDG_CONFIG_HOME'].to_s.strip
        root = File.join(Dir.home, '.config') if root.empty?
        File.join(root, 'feedmob-cli')
      end

      def credentials_path = File.join(@config_dir, 'credentials.enc')

      def key_path = File.join(@config_dir, '.encryption_key')

      def lock_path = File.join(@config_dir, '.credentials.lock')

      def load_credentials
        return {} unless File.exist?(credentials_path)

        assert_regular_file!(credentials_path)
        parsed = JSON.parse(decrypt(File.binread(credentials_path)))
        return parsed if parsed.is_a?(Hash) && parsed.values.all?(String)

        raise store_error('The encrypted credential store has an invalid format.')
      rescue JSON::ParserError
        raise store_error('The encrypted credential store cannot be parsed.')
      end

      def encrypt(plaintext)
        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt
        cipher.key = encryption_key
        nonce = OpenSSL::Random.random_bytes(NONCE_BYTES)
        cipher.iv = nonce
        ciphertext = cipher.update(plaintext) + cipher.final
        nonce + cipher.auth_tag(TAG_BYTES) + ciphertext
      end

      def decrypt(payload)
        raise store_error('The encrypted credential store is truncated.') if payload.bytesize < NONCE_BYTES + TAG_BYTES

        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.decrypt
        cipher.key = encryption_key
        cipher.iv = payload.byteslice(0, NONCE_BYTES)
        cipher.auth_tag = payload.byteslice(NONCE_BYTES, TAG_BYTES)
        cipher.update(payload.byteslice((NONCE_BYTES + TAG_BYTES)..)) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        raise store_error('The encrypted credential store could not be authenticated.')
      end

      def encryption_key
        return read_key if File.exist?(key_path)

        key = OpenSSL::Random.random_bytes(KEY_BYTES)
        begin
          write_new_file(key_path, key.unpack1('H*'))
          key
        rescue Errno::EEXIST
          read_key
        end
      end

      def read_key
        assert_regular_file!(key_path)
        encoded_key = File.binread(key_path).strip
        return [encoded_key].pack('H*') if encoded_key.match?(/\A[0-9a-f]{#{KEY_BYTES * 2}}\z/)

        raise store_error('The credential encryption key has an invalid length.')
      end

      def with_lock
        ensure_directory!
        File.open(lock_path, File::RDWR | File::CREAT, FILE_MODE) do |lock|
          protect_file!(lock_path)
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN)
        end
      rescue SystemCallError => e
        raise store_error("Could not access the encrypted credential store: #{e.class.name}.")
      end

      def ensure_directory!
        FileUtils.mkdir_p(@config_dir, mode: DIRECTORY_MODE)
        File.chmod(DIRECTORY_MODE, @config_dir) if unix?
      end

      def atomic_write(path, content)
        temporary_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(8)}"
        write_new_file(temporary_path, content)
        File.rename(temporary_path, path)
      ensure
        File.delete(temporary_path) if defined?(temporary_path) && File.exist?(temporary_path)
      end

      def write_new_file(path, content)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, FILE_MODE) do |file|
          file.binmode
          file.write(content)
          file.flush
          file.fsync
        end
        protect_file!(path)
      end

      def assert_regular_file!(path)
        raise store_error('Credential storage must not use symbolic links.') if File.lstat(path).symlink?
      rescue Errno::ENOENT
        raise store_error('Credential storage disappeared while it was being read.')
      end

      def protect_file!(path)
        File.chmod(FILE_MODE, path) if unix?
      end

      def unix?
        !@platform.match?(/mswin|mingw|cygwin/i)
      end

      def store_error(message)
        Error.new(code: 'credential_store_error', message:)
      end
    end
  end
end
