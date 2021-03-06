#
# Copyright:: Copyright (c) Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative "../resource"
require_relative "helpers/cron_validations"
require "shellwords" unless defined?(Shellwords)
require_relative "../dist"

class Chef
  class Resource
    class CronD < Chef::Resource
      unified_mode true
      provides :cron_d

      introduced "14.4"
      description "Use the cron_d resource to manage cron definitions in /etc/cron.d. This is similar to the 'cron' resource, but it does not use the monolithic /etc/crontab file."
      examples <<~DOC
        To run a program on the fifth hour of the day
        ```ruby
        cron_d 'noop' do
          hour '5'
          minute '0'
          command '/bin/true'
        end
        ```

        To run an entry if a folder exists
        ```ruby
        cron_d 'ganglia_tomcat_thread_max' do
          command "/usr/bin/gmetric
            -n 'tomcat threads max'
            -t uint32
            -v '/usr/local/bin/tomcat-stat
            --thread-max'"
          only_if { ::File.exist?('/home/jboss') }
        end
        ```

        To run an entry every Saturday, 8:00 AM
        ```ruby
        cron_d 'name_of_cron_entry' do
          minute '0'
          hour '8'
          weekday '6'
          mailto 'admin@example.com'
          action :create
        end
        ```

        To run an entry at 8:00 PM, every weekday (Monday through Friday), but only in November
        ```ruby
        cron_d 'name_of_cron_entry' do
          minute '0'
          hour '20'
          day '*'
          month '11'
          weekday '1-5'
          action :create
        end
        ```
      DOC

      property :cron_name, String,
        description: "An optional property to set the cron name if it differs from the resource block's name.",
        name_property: true

      property :cookbook, String, desired_state: false

      property :predefined_value, String,
        description: "Schedule your cron job with one of the special predefined value instead of ** * pattern.",
        equal_to: %w{ @reboot @yearly @annually @monthly @weekly @daily @midnight @hourly }

      property :minute, [Integer, String],
        description: "The minute at which the cron entry should run (0 - 59).",
        default: "*", callbacks: {
          "should be a valid minute spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 0, 59) },
        }

      property :hour, [Integer, String],
        description: "The hour at which the cron entry is to run (0 - 23).",
        default: "*", callbacks: {
          "should be a valid hour spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 0, 23) },
        }

      property :day, [Integer, String],
        description: "The day of month at which the cron entry should run (1 - 31).",
        default: "*", callbacks: {
          "should be a valid day spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 1, 31) },
        }

      property :month, [Integer, String],
        description: "The month in the year on which a cron entry is to run (1 - 12, jan-dec, or *).",
        default: "*", callbacks: {
          "should be a valid month spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_month(spec) },
        }

      property :weekday, [Integer, String],
        description: "The day of the week on which this entry is to run (0-7, mon-sun, or *), where Sunday is both 0 and 7.",
        default: "*", callbacks: {
          "should be a valid weekday spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_dow(spec) },
        }

      property :command, String,
        description: "The command to run.",
        required: true

      property :user, String,
        description: "The name of the user that runs the command.",
        default: "root"

      property :mailto, String,
        description: "Set the MAILTO environment variable in the cron.d file."

      property :path, String,
        description: "Set the PATH environment variable in the cron.d file."

      property :home, String,
        description: "Set the HOME environment variable in the cron.d file."

      property :shell, String,
        description: "Set the SHELL environment variable in the cron.d file."

      property :comment, String,
        description: "A comment to place in the cron.d file."

      property :environment, Hash,
        description: "A Hash containing additional arbitrary environment variables under which the cron job will be run in the form of ``({'ENV_VARIABLE' => 'VALUE'})``.",
        default: lazy { {} }

      TIMEOUT_OPTS = %w{duration preserve-status foreground kill-after signal}.freeze
      TIMEOUT_REGEX = /\A\S+/.freeze

      property :time_out, Hash,
        description: "A Hash of timeouts in the form of ({'OPTION' => 'VALUE'}).
        Accepted valid options are:
        preserve-status (BOOL, default: 'false'),
        foreground (BOOL, default: 'false'),
        kill-after (in seconds),
        signal (a name like 'HUP' or a number)",
        default: lazy { {} },
        introduced: "15.7",
        coerce: proc { |h|
          if h.is_a?(Hash)
            invalid_keys = h.keys - TIMEOUT_OPTS
            unless invalid_keys.empty?
              error_msg = "Key of option time_out must be equal to one of: \"#{TIMEOUT_OPTS.join('", "')}\"!  You passed \"#{invalid_keys.join(", ")}\"."
              raise Chef::Exceptions::ValidationFailed, error_msg
            end
            unless h.values.all? { |x| x =~ TIMEOUT_REGEX }
              error_msg = "Values of option time_out should be non-empty string without any leading whitespaces."
              raise Chef::Exceptions::ValidationFailed, error_msg
            end
            h
          elsif h.is_a?(Integer) || h.is_a?(String)
            { "duration" => h }
          end
        }

      property :mode, [String, Integer],
        description: "The octal mode of the generated crontab file.",
        default: "0600"

      property :random_delay, Integer,
        description: "Set the RANDOM_DELAY environment variable in the cron.d file."

      # warn if someone passes the deprecated cookbook property
      def after_created
        raise ArgumentError, "The 'cookbook' property for the cron_d resource is no longer supported now that it ships as a core resource." if cookbook
      end

      action :create do
        description "Add a cron definition file to /etc/cron.d."

        create_template(:create)
      end

      action :create_if_missing do
        description "Add a cron definition file to /etc/cron.d, but do not update an existing file."

        create_template(:create_if_missing)
      end

      action :delete do
        description "Remove a cron definition file from /etc/cron.d if it exists."

        # cleanup the legacy named job if it exists
        file "legacy named cron.d file" do
          path "/etc/cron.d/#{new_resource.cron_name}"
          action :delete
        end

        file "/etc/cron.d/#{sanitized_name}" do
          action :delete
        end
      end

      action_class do
        # @return [String] cron_name property with . replaced with -
        def sanitized_name
          new_resource.cron_name.tr(".", "-")
        end

        def create_template(create_action)
          # cleanup the legacy named job if it exists
          file "#{new_resource.cron_name} legacy named cron.d file" do
            path "/etc/cron.d/#{new_resource.cron_name}"
            action :delete
            only_if { new_resource.cron_name != sanitized_name }
          end

          # @todo this is Chef 12 era cleanup. Someday we should remove it all
          template "/etc/cron.d/#{sanitized_name}" do
            source ::File.expand_path("../support/cron.d.erb", __FILE__)
            local true
            mode new_resource.mode
            variables(
              name: sanitized_name,
              predefined_value: new_resource.predefined_value,
              minute: new_resource.minute,
              hour: new_resource.hour,
              day: new_resource.day,
              month: new_resource.month,
              weekday: new_resource.weekday,
              command: new_resource.command,
              user: new_resource.user,
              mailto: new_resource.mailto,
              path: new_resource.path,
              home: new_resource.home,
              shell: new_resource.shell,
              comment: new_resource.comment,
              random_delay: new_resource.random_delay,
              environment: new_resource.environment
            )
            action create_action
          end
        end
      end
    end
  end
end
