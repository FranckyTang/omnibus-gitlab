require_relative 'object_proxy'
require_relative 'helpers/logging_helper'

module Gitlab
  class Deprecations
    class << self
      ATTRIBUTE_BLOCKS ||= %w[gitlab monitoring].freeze

      def list(existing_config = nil)
        # List of deprecations. Remember to convert underscores to hyphens for
        # the first level configurations (eg: gitlab_rails => gitlab-rails)
        #
        # `config_keys` represents a list of keys, which can be used to traverse
        # the configuration hash available from /opt/gitlab/embedded/nodes/{fqdn}json
        # to reach a specific configuration. For example %w(mattermost
        # log_file_directory) means `mattermost['log_file_directory']` setting.
        # Similarly, %w(gitlab nginx listen_addresses) means
        # `gitlab['nginx']['listen_addresses']`. We internally convert it to
        # nginx['listen_addresses'], which is what we use in /etc/gitlab/gitlab.rb
        deprecations = [
          {
            config_keys: %w(gitlab postgresql data_dir),
            deprecation: '11.6',
            removal: '14.0',
            note: "Please see https://docs.gitlab.com/omnibus/settings/database.html#store-postgresql-data-in-a-different-directory for how to use postgresql['dir']"
          },
          {
            config_keys: %w(gitlab sidekiq cluster),
            deprecation: '13.0',
            removal: '14.0',
            note: "Running sidekiq directly is deprecated. Please see https://docs.gitlab.com/ee/administration/operations/extra_sidekiq_processes.html for how to use sidekiq-cluster."
          },
          {
            config_keys: %w(roles redis-slave enable),
            deprecation: '13.0',
            removal: '14.0',
            note: 'Use redis_replica_role instead.'
          },
          {
            config_keys: %w(redis client_output_buffer_limit_slave),
            deprecation: '13.0',
            removal: '14.0',
            note: 'Use client_output_buffer_limit_replica instead'
          },
          {
            config_keys: %w(gitlab gitlab-pages http_proxy),
            deprecation: '13.1',
            removal: '14.0',
            note: "Set gitlab_pages['env']['http_proxy'] instead. See https://docs.gitlab.com/omnibus/settings/environment-variables.html"
          },
          {
            config_keys: %w(praefect failover_read_only_after_failover),
            deprecation: '13.3',
            removal: '14.0',
            note: "Read-only mode is repository specific and always enabled after suspected data loss. See https://docs.gitlab.com/ee/administration/gitaly/praefect.html#read-only-mode"
          },
          {
            config_keys: %w(gitlab geo-secondary db_fdw),
            deprecation: '13.3',
            removal: '14.0',
            note: "Geo does not require Foreign Data Wrapper (FDW) to be configured to replicate data."
          },
          {
            config_keys: %w(gitlab geo-postgresql fdw_external_user),
            deprecation: '13.3',
            removal: '14.0',
            note: "Geo does not require Foreign Data Wrapper (FDW) to be configured to replicate data."
          },
          {
            config_keys: %w(gitlab geo-postgresql fdw_external_password),
            deprecation: '13.3',
            removal: '14.0',
            note: "Geo does not require Foreign Data Wrapper (FDW) to be configured to replicate data."
          },
          {
            config_keys: %w(praefect virtual_storages primary),
            deprecation: '13.4',
            removal: '14.0',
            note: "Praefect no longer supports statically designating primary Gitaly nodes."
          },
          {
            config_keys: %w(gitlab gitlab-rails extra_piwik_site_id),
            deprecation: '13.7',
            removal: '14.0',
            note: "Piwik config keys have been renamed to reflect the rebranding to Matomo. Please update gitlab_rails['extra_piwik_site_id'] to gitlab_rails['extra_matomo_site_id']."
          },
          {
            config_keys: %w(gitlab gitlab-rails extra_piwik_url),
            deprecation: '13.7',
            removal: '14.0',
            note: "Piwik config keys have been renamed to reflect the rebranding to Matomo. Please update gitlab_rails['extra_piwik_url'] to gitlab_rails['extra_matomo_url']."
          },
          # Remove with https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/646
          {
            config_keys: %w(gitlab sidekiq-cluster experimental_queue_selector),
            deprecation: '13.6',
            removal: '14.0',
            note: 'The experimental_queue_selector option is now called queue_selector.'
          },
          {
            config_keys: %w(gitlab sidekiq experimental_queue_selector),
            deprecation: '13.6',
            removal: '14.0',
            note: 'The experimental_queue_selector option is now called queue_selector.'
          }
        ]

        deprecations
      end

      def identify_deprecated_config(existing_config, config_keys, allowed_keys, deprecation, removal, note = nil)
        # Method to simplify deprecating a bulk of configuration related to a
        # component. In short, it generates and returns a list of deprecated
        # configuration from the complete list using a smaller list of
        # supported keys. The output is formatted as a list of hashes, similar
        # to the one from `GitLab::Deprecations.list` above.
        # The parameters are
        # 1. existing_config: The high level configuration from fqdn.json file
        # 2. config_keys: The keys that make up the hash which contains
        #                 configuration to be deprecated. Check comment inside
        #                 `list` method above for more details.
        # 3. allowed_keys: List of allowed keys
        # 4. deprecation: Version since which were the configurations deprecated
        # 5. removal: Version in which were the configurations removed
        # 6. note: General note regarding removal
        matching_config = existing_config.dig(*config_keys)
        return [] unless matching_config

        deprecated_config = matching_config.select { |config| !allowed_keys.include?(config) }
        deprecated_config.keys.map do |key|
          {
            config_keys: config_keys + [key],
            deprecation: deprecation,
            removal: removal,
            note: note
          }
        end
      end

      def next_major_version
        version_manifest = JSON.parse(File.read("/opt/gitlab/version-manifest.json"))
        major_version = version_manifest['build_version'].split(".")[0]
        (major_version.to_i + 1).to_s
      rescue StandardError
        puts "Error reading /opt/gitlab/version-manifest.json. Please check if the file exists and JSON content in it is not malformed."
        puts "Checking for deprecated configuration failed."
      end

      def applicable_deprecations(incoming_version, existing_config, type)
        # Return the list of deprecations or removals that are applicable with
        # a given list of configuration for a specific version.
        incoming_version = next_major_version if incoming_version.empty?
        return [] unless incoming_version

        version = Gem::Version.new(incoming_version)

        # Getting settings from gitlab.rb that are in deprecations list and
        # has been removed in incoming or a previous version.
        current_deprecations = list(existing_config).select { |deprecation| version >= Gem::Version.new(deprecation[type]) }
        current_deprecations.select { |deprecation| !existing_config.dig(*deprecation[:config_keys]).nil? }
      end

      def check_config(incoming_version, existing_config, type = :removal)
        messages = []
        deprecated_config = applicable_deprecations(incoming_version, existing_config, type)
        deprecated_config.each do |deprecation|
          config_keys = deprecation[:config_keys].dup
          config_keys.shift if ATTRIBUTE_BLOCKS.include?(config_keys[0])
          key = if config_keys.length == 1
                  config_keys[0].tr("-", "_")
                elsif config_keys.first.eql?('roles')
                  "#{config_keys[1].tr('-', '_')}_role"
                else
                  "#{config_keys[0].tr('-', '_')}['#{config_keys.drop(1).join("']['")}']"
                end

          if type == :deprecation
            message = "* #{key} has been deprecated since #{deprecation[:deprecation]} and will be removed in #{deprecation[:removal]}."
          elsif type == :removal
            message = "* #{key} has been deprecated since #{deprecation[:deprecation]} and was removed in #{deprecation[:removal]}."
          end
          message += " " + deprecation[:note] if deprecation[:note]
          messages << message
        end
        messages
      end
    end

    class NodeAttribute < ObjectProxy
      def self.log_deprecations?
        @log_deprecations || false
      end

      def self.log_deprecations=(value = true)
        @log_deprecations = !!value
      end

      def initialize(target, var_name, new_var_name)
        @target = target
        @var_name = var_name
        @new_var_name = new_var_name
      end

      def method_missing(method_name, *args, &block) # rubocop:disable Style/MissingRespondToMissing
        deprecated_msg(caller[0..2]) if NodeAttribute.log_deprecations?
        super
      end

      private

      def deprecated_msg(*called_from)
        called_from = called_from.flatten
        msg = "Accessing #{@var_name} is deprecated. Support will be removed in a future release. \n" \
              "Please update your cookbooks to use #{@new_var_name} in place of #{@var_name}. Accessed from: \n"
        called_from.each { |l| msg << "#{l}\n" }
        LoggingHelper.deprecation(msg)
      end
    end
  end
end
