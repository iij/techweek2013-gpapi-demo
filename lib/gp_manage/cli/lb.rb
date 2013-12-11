# -*- coding: utf-8 -*-
require "gp_manage/worker/gp"

module GpManage
  class CLI < Thor
    class LB < CLIBase
      namespace :LB

      def self.banner(task, namespace = false, subcommand = false)
        "#{basename} lb #{task.formatted_usage(self, namespace, subcommand)}"
      end

      desc "add <LB_TYPE>", "Add FW+LB option"
      option :clustered, :type => :boolean, :default => false
      option :init, :type => :boolean, :default => false, :desc => "wait until FW+LB contracts are completed, then setting up vservers and pools."
      def add(type)
        new_gl_sc = do_add_fwlb(type, options[:clustered])
        gp = config.gp_client
        gl = gp.gl(new_gl_sc)

        if options[:init]
          sleep 120
          gp_worker.wait_for_in_service(gl) do |status|
            puts "-- #{gl.gp_service_code}:#{gl.gl_service_code}: #{status}"
          end

          do_update_setting(new_gl_sc)
        end
      end

      desc "update_setting [GL_SERVICE_CODE]", "update FW+LB option setting"
      def update_setting(gl_sc = nil)
        if gl_sc
          do_update_setting(gl_sc)
        else
          gp_worker.lbs.each do |gl_sc, info|
            if lb_info = info[:lb_info]
              do_update_setting(gl_sc)
            end
          end
        end
      end

      desc "info", "Fetch FW+LB option setting"
      option :update, :type => :boolean, :description => "update cache"
      def info
        gp_worker.lbs(options[:update]).each do |gl_sc, info|
          gl = config.gp_client.gl(gl_sc)
          if lb_info = info[:lb_info]
            puts "===== #{gl.gp_service_code} : #{gl.gl_service_code} ====="
            puts "label: #{lb_info['Label']}"
            puts "type: #{lb_info['Type']}"

            puts "traffic ip:"
            lb_info['TrafficIpList'].each do |traffic_ip|
              v4 = traffic_ip['IPv4']
              puts ["", v4['TrafficIpName'], v4['TrafficIpAddress']].join("\t")

              v6 = traffic_ip['IPv6']
              puts ["", v6['TrafficIpName'], v6['TrafficIpAddress']].join("\t")
            end

            puts "virtual server:"
            lb_info['VirtualServerList'].each do |vserver|
              puts ["", vserver['Name'], vserver['Protocol'], vserver['Port'], vserver['Pool'], vserver['TrafficIpNameList'].join(',')].join("\t")
            end

            puts "pool:"
            lb_info['PoolList'].each do |pool|
              pool['NodeList'].each do |node|
                puts ["", pool['Name'], "#{node['IpAddress']}:#{node['Port']}", node['Status']].join("\t")
              end
            end
          end
        end
      end

      desc "change_type <GL_SERVICE_CODE> <LB_TYPE>", "Change FW+LB option type"
      def change_type(gl_sc, lb_type)
        gl = config.gp_client.gl(gl_sc)

        puts "Change FW+LB option type: #{gl.gp_service_code}:#{gl.gl_service_code} #{lb_type}"
        gl.change_fw_lb_option_type(lb_type)
      end


      no_commands do
        def gp_worker
          @gp_worker ||= GpManage::Worker::Gp.new(config, vm_store)
          @gp_worker
        end

        def do_add_fwlb(type, is_clustered)
          gp = config.gp_client

          opts = {
            "Type" => type,
            "Redundant" => (is_clustered ? 'Yes' : 'No')
          }
          puts "Add FW+LB option: #{opts.inspect}"
          res = gp.add_fw_lb_option(opts)
          new_gl_sc = res["GlServiceCode"]

          puts "Added FW+LB option: #{new_gl_sc}"

          new_gl_sc
        end

        def do_update_setting(gl_sc)
          gl = config.gp_client.gl(gl_sc)

          config.fetch('lb')['pools'].each do |pool_setting|
            p pool_setting
            private_ip_list = get_private_ip_list(pool_setting['roles'])
            if private_ip_list.empty?
              p private_ip_list
              puts "[#{gl_sc}] There are no active VMs with role:#{pool_setting['roles'].inspect}"
              next
            end
            add_or_update_pool(gl, pool_setting, private_ip_list)
          end

          config.fetch('lb')['virtual_servers'].each do |vserver_setting|
            add_or_update_virtual_server(gl, vserver_setting)
          end
        end

        def add_or_update_pool(gl, pool_setting, private_ip_list)
          nodes = private_ip_list.map{|ip| [ip, pool_setting['port'].to_s] }
          puts "[#{gl.gl_service_code}] Setting up of the pool #{pool_setting['name']}.."
          puts "[#{gl.gl_service_code}]   nodes: #{nodes.inspect}"

          begin
            gl.add_or_update_pool(pool_setting['name'], nodes)
            puts "[#{gl.gl_service_code}] Setup completed."
          rescue => e
            puts "[#{gl.gl_service_code}] Failed to initialize the pool #{pool_setting['name']}.."
            puts e.inspect
            puts e.backtrace
          end
        end

        def add_or_update_virtual_server(gl, vserver_setting)
          puts "[#{gl.gl_service_code}] Setting up of the virtual server #{vserver_setting['name']}.."
          begin
            traffic_ip_list = if gl.lb_info['Redundant'] == "Yes"
                                vserver_setting['traffic_ip_list']
                              else
                                nil
                              end

            gl.add_or_update_virtual_server(vserver_setting['name'],
                                            vserver_setting['port'],
                                            vserver_setting['protocol'],
                                            vserver_setting['pool'],
                                            traffic_ip_list
                                            )
          rescue => e
            puts "[#{gl.gl_service_code}] Failed to set up the vserver #{vserver_setting['name']}.."
            puts e.inspect
            puts e.backtrace
          end
        end

        def running_gc_list(roles = nil)
          roles = [roles] if roles.kind_of? String

          gp = config.gp_client
          puts "Getting contract information"
          contracted = gp.contract_information['VirtualMachineList']
            .select{|vm| vm['Status'] == "InService" }
            .map{|vm| vm['GcServiceCode'] }
          vms = gp_worker.vms

          if roles
            contracted = contracted.select do |gc_sc|
              roles.include? vms.fetch(gc_sc, {})[:role]
            end
          end

          return [] if contracted.nil? or contracted.empty?

          puts "Getting virtual machine status"
          status_list = gp.get_virtual_machine_status_list(contracted)['VirtualMachineStatusList']
          status_list.each do |status|
            puts "-- #{status['GcServiceCode']} #{status['Status']}"
          end

          status_list.select{|vm| vm["Status"] == "Running" }.map{|vm| vm["GcServiceCode"] }
        end

        def get_private_ip_list(roles)
          gp = config.gp_client

          puts "Fetching Private IP Address information"
          vms = gp_worker.vms
          private_ip_list = running_gc_list(roles).map do |gc_sc|
            vms[gc_sc][:info]['PrivateAddress']['IPv4Address']
          end.compact
        end
      end
    end

    register(LB, 'lb', 'lb [COMMAND]', 'commands for managing FW+LB options')
  end
end
