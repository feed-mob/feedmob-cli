# frozen_string_literal: true

require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class AuthLogin < Base
        desc 'Verify and securely save a service credential'
        option :token_stdin, type: :boolean, default: false, desc: 'Read the token from standard input'

        def call(token_stdin: false, **)
          token = token_stdin ? runtime.read_token_from_stdin : runtime.read_token_interactively(service)
          runtime.credentials.validate_token!(service, token)
          response = runtime.client(service).request(method: :get, path: service.identity_path, token:)
          runtime.credentials.store(service, token)
          source = runtime.credentials.storage_source

          output.success(
            authentication_payload(
              service: service.name,
              authenticated: true,
              source:,
              response:
            ),
            message: "Authenticated with #{service.label}; credential saved in #{runtime.credentials.storage_label}."
          )
        end
      end

      class AuthStatus < Base
        desc 'Check an authenticated service credential'

        def call(**)
          credential = credential!(service)
          response = runtime.client(service).request(method: :get, path: service.identity_path, token: credential.value)

          output.success(
            authentication_payload(
              service: service.name,
              authenticated: true,
              source: credential.source,
              response:
            ),
            message: "Authenticated with #{service.label} using #{credential.source}."
          )
        end
      end

      class AuthLogout < Base
        desc 'Remove the local credential and revoke it when the service supports revocation'

        def call(**)
          credential = runtime.credentials.resolve(service)
          if credential.source == 'missing'
            return output.success(
              {
                service: service.name,
                logged_out: false,
                credential_source: 'missing',
                remote_revoked: false
              },
              message: "No #{service.label} credential is stored locally."
            )
          end

          remote_revoked = !service.revoke_path.nil?
          local_removed = revoke_and_remove(credential, remote_revoked)
          payload = {
            service: service.name,
            logged_out: local_removed || remote_revoked,
            credential_source: credential.source,
            local_removed:,
            remote_revoked:
          }
          payload[:environment_variable] = service.token_env if credential.source == 'env'

          message = logout_message(service, credential.source, local_removed, remote_revoked)
          output.success(payload, message:)
        end

        private

        def revoke_and_remove(credential, remote_revoked)
          begin
            revoke_remote_token(service, credential.value) if remote_revoked
          rescue Error => e
            local_removed = remove_local_credential(credential)
            raise Error.new(
              code: e.code, message: "#{e.message} Local credential removed: #{local_removed}.",
              details: (e.details || {}).merge(local_removed:, remote_revoked: false), exit_status: e.exit_status
            )
          end
          remove_local_credential(credential)
        end

        def remove_local_credential(credential)
          local_credential_source?(credential.source) && runtime.credentials.delete(service)
        end

        def revoke_remote_token(service, token)
          runtime.client(service).request(method: :delete, path: service.revoke_path, token:)
        end

        def logout_message(service, source, local_removed, remote_revoked)
          if source == 'env'
            "#{service.label} token #{'was revoked and ' if remote_revoked}is set by #{service.token_env}; " \
              'unset it in your shell.'
          elsif local_removed
            "Removed the local #{service.label} credential#{' and revoked it remotely' if remote_revoked}."
          elsif remote_revoked
            "Revoked the #{service.label} credential remotely."
          else
            "No local #{service.label} credential was removed."
          end
        end

        def local_credential_source?(source)
          %w[keychain encrypted_file].include?(source)
        end
      end

      class PixelAuthLogin < AuthLogin
        desc 'Verify and securely save a Pixel credential'

        def service_name = 'pixel'
      end

      class PixelAuthStatus < AuthStatus
        desc 'Show the authenticated Pixel identity'

        def service_name = 'pixel'
      end

      class PixelAuthLogout < AuthLogout
        desc 'Revoke the Pixel credential and remove it locally'

        def service_name = 'pixel'
      end

      class TimeOffAuthLogin < AuthLogin
        desc 'Verify and securely save a Time Off credential'

        def service_name = 'time-off'
      end

      class TimeOffAuthStatus < AuthStatus
        desc 'Show the authenticated Time Off identity'

        def service_name = 'time-off'
      end

      class TimeOffAuthLogout < AuthLogout
        desc 'Remove the local Time Off credential'

        def service_name = 'time-off'
      end

      class FeminiAuthLogin < AuthLogin
        desc 'Verify and securely save a Femini bearer token'

        def service_name = 'femini'
      end

      class FeminiAuthStatus < AuthStatus
        desc 'Check the configured Femini bearer token'

        def service_name = 'femini'
      end

      class FeminiAuthLogout < AuthLogout
        desc 'Remove the local Femini bearer token'

        def service_name = 'femini'
      end

      class PagesAuthLogin < AuthLogin
        desc 'Verify and securely save a Pages API key'

        def service_name = 'pages'
      end

      class PagesAuthStatus < AuthStatus
        desc 'Show the authenticated Pages identity'

        def service_name = 'pages'
      end

      class PagesAuthLogout < AuthLogout
        desc 'Remove the local Pages API key'

        def service_name = 'pages'
      end

      class WorkspaceAuthLogin < AuthLogin
        desc 'Verify and securely save a FeedMob Workspace credential'

        def service_name = 'workspace'
      end

      class WorkspaceAuthStatus < AuthStatus
        desc 'Show the authenticated FeedMob Workspace identity'

        def service_name = 'workspace'
      end

      class WorkspaceAuthLogout < AuthLogout
        desc 'Remove the local FeedMob Workspace credential'

        def service_name = 'workspace'
      end
    end
  end
end
