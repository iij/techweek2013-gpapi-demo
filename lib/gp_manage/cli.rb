require "gp_manage/setting"
require "thor"
require "yaml/store"
require "iijapi"

module GpManage
  class CLIBase < Thor
    no_commands do
      def config
        @config ||= Setting.new(parent_options[:config])
        @config
      end

      def vm_store
        @vm_store ||= YAML::Store.new(parent_options[:vm_store])
        @vm_store
      end
    end
  end

  class CLI < Thor
    CONFIG_PATH = "config.yml"
    VM_STORE_PATH = "vmstore.yml"

    class_option :config, :type => :string, :aliases => '-c', :default => CONFIG_PATH, :desc => "config file path (default: #{CONFIG_PATH})"
    class_option :vm_store, :type => :string, :aliases => '-d', :default => VM_STORE_PATH
  end
end

require 'gp_manage/cli/vm'
require 'gp_manage/cli/lb'
