require "gp_manage/worker/gp"
require "gp_manage/worker/gl"

module GpManage
  class CLI < Thor
    class VM < CLIBase
      namespace "vm"

      def self.banner(task, namespace = false, subcommand = false)
        "#{basename} vm #{task.formatted_usage(self, namespace, subcommand)}"
      end

      desc "status [VM]..", "get VM status"
      option :update, :type => :boolean, :description => "update cache", :default => false
      def status(*vm_list)
        vms = gp_worker.vms(options[:update])
        status_map = gp_worker.vm_status_map

        lines = vms.map do |gc_sc, vm|
          gc = config.gp_client.gc(gc_sc)
          if info = vm[:info]
            [vm[:role],
             gc.gp_service_code,
             gc.gc_service_code,
             info['VirtualMachineType'],
             info['GlobalAddress']['IPv4Address'],
             info['PrivateAddress']['IPv4Address'],
             status_map[gc_sc],
             info['Label']
           ].map{|v| if v.nil? or v.empty? then "-" else v end }
          else
            [vm[:role],
             gc.gp_service_code,
             gc.gc_service_code,
            ]
          end
        end

        print_table lines
      end

      desc "add <VM_TYPE> <OS_TYPE> <ROLE> <CONTRACT_NUM>", "Add virtual machine"
      option :disk1, :type => :string, :description => "disk option 1 (values: 100, 300, 500, HS300)"
      option :disk2, :type => :string, :description => "disk option 2 (values: 100, 300, 500, HS300)"
      option :location_l, :type => :numeric, :aliases => :L,
             :description => "# of VMs which will be created into location L"
      option :location_r, :type => :numeric, :aliases => :R,
             :description => "# of VMs which will be created into location L"
      option :start, :type => :boolean
      def add(vm_type, os_type, role, contract_num)
        gp = config.gp_client

        opts = {
          "VirtualMachineType" => vm_type,
          "OS" => os_type,
          "ContractNum" => contract_num
        }
        opts["DiskOption.1.DiskSpace"] = options[:disk1] if options[:disk1]
        opts["DiskOption.2.DiskSpace"] = options[:disk2] if options[:disk2]
        opts["LLocationNum"] = options[:location_l] if options[:location_l]
        opts["RLocationNum"] = options[:location_r] if options[:location_r]

        puts "Add virtual machines: #{opts.inspect}"

        res = gp.add_virtual_machines(opts)
        puts res
        new_gcs = res['GcServiceCodeList']

        new_gcs.each do |gc_sc|
          gp_worker.set_vm_role(gc_sc, role)
        end

        if options[:start]
          sleep 120

          gp_worker.wait_for_in_service_list(new_gcs)

          new_gcs.each do |gc_sc|
            do_import_ssh_pubkey(gc_sc)
          end

          gp_worker.wait_for(proc {|status| status == "Stopped" }, new_gcs)

          puts "Starting virtual machines..."
          new_gcs.each do |gc_sc|
            gc = gp.gc(gc_sc)
            if gc.status! == 'Stopped'
              puts "Start virtual machine: #{gc.gp_service_code}:#{gc.gc_service_code}"
              gc.start
            end
          end

          gp_worker.wait_for_start(new_gcs)
        end
      end

      desc "set_role <GC_SERVICE_CODE> <ROLE>", "set vm role"
      def set_role(gc_sc, role)
        gp_worker.set_vm_role(gc_sc, role)
      end

      desc "update_labels", "update label"
      def update_labels
        vms = gp_worker.vms
        vms.each do |gc_sc, vm|
          if vm[:info] and vm[:role]
            gp_worker.set_vm_label(gc_sc, vm[:role])
          end
        end
      end

      desc "import_ssh_pubkey <GC_SERVICE_CODE>", "import root ssh public key"
      def import_ssh_pubkey(gc_sc)
        do_import_ssh_pubkey(gc_sc)
      end

      desc "change_type <GC_SERVICE_CODE> <VM_TYPE>", "change virtual machine type"
      def change_type(gc_sc, vm_type)
        gc = config.gp_client.gc(gc_sc)
        vms = gp_worker.vms
        if vm = vms[gc_sc]
          private_ip = vm[:info]['PrivateAddress']['IPv4Address']
          detach_from_pools(vm[:role], private_ip)

          puts "Change virtual machine type: #{gc.gp_service_code}:#{gc.gc_service_code} #{vm_type}"
          gc.change_vm_type(vm_type)

          sleep(120)
          gc.wait_while(proc { gc.status! == "Configuring" }) {|status| puts "-- #{gc.gp_service_code}:#{gc.gc_service_code}: #{gc.status}" }

          if gc.status! == "Stopped"
            puts "Start virtual machine: #{gc.gp_service_code}:#{gc.gc_service_code}"
            gc.start
            gc.wait_for_start { puts "-- #{gc.gp_service_code}:#{gc.gc_service_code}: #{gc.status}" }
          end

          attach_to_pools(vm[:role], private_ip)
        else
          STDERR.puts "Unknown VM: #{gc_sc}"
        end
      end

      desc "attach_fwlb <GC_SERVICE_CODE> <GL_SERVICE_CODE>", "Attach VM to FW+LB option"
      def attach_fwlb(gc_sc, gl_sc = nil)
        gl_sc ||= config.fetch("default_fw")
        if gl_sc
          gp_worker.attach_fwlb(gc_sc, gl_sc)
        else
          STDERR.puts "missing gl service code"
        end
      end

      desc "detach_fwlb <GC_SERVICE_CODE> <GL_SERVICE_CODE>", "Detach VM to FW+LB option"
      def detach_fwlb(gc_sc, gl_sc = nil)
        gl_sc ||= config.fetch("default_fw")
        if gl_sc
          gp_worker.detach_fwlb(gc_sc, gl_sc)
        else
          STDERR.puts "missing gl service code"
        end
      end

      desc "clone <NUM> <VM_TYPE> <ROLE>", "clone virtual machine"
      option :wait, :type => :boolean, :default => false, :desc => "wait until VM contracts are completed"
      option :start, :type => :boolean, :default => false, :desc => "start VMs after contracts were completed"
      option :attach_fwlb, :type => :boolean, :default => false, :desc => "attach to FW+LB option"
      def clone(num, vm_type, role)
        gp = config.gp_client

        new_gcs = do_clone(num, vm_type, role)

        # wait for InService
        gp_worker.wait_for_in_service_list(new_gcs) if options[:wait] or options[:start]

        # attach to fwlb
        if options[:attach_fwlb]
          if gl_sc = config.fetch("default_fw")
            new_gcs.each do |gc_sc|
              gp_worker.attach_fwlb(gc_sc, gl_sc)
            end
          else
            STDERR.puts "`default_fw' setting is missing. ignoring --attach-fwlb option."
          end

          sleep(120) # avoid cached result
          gp_worker.wait_for(proc {|status| status != 'Configuring'}, new_gcs)
        end

        if options[:start]
          new_gcs.each do |gc_sc|
            gc = gp.gc(gc_sc)
            if gc.status == 'Stopped'
              puts "Start virtual machine: #{gc.gp_service_code}:#{gc.gc_service_code}"
              gc.start
            end
          end

          gp_worker.wait_for_start(new_gcs)
        end
      end

      no_commands do
        def gp_worker
          @gp_worker ||= GpManage::Worker::Gp.new(config, vm_store)
          @gp_worker
        end

        def do_import_ssh_pubkey(gc_sc)
          gc = config.gp_client.gc(gc_sc)
          ssh_key = config.fetch("ssh_public_key")

          puts "[#{gc_sc}] Importing ssh public key: #{ssh_key}"
          gc.import_ssh_public_key(ssh_key)
        end

        def do_clone(num, vm_type, role)
          gp = config.gp_client
          source_vm = config.fetch("source_vm")

          clone_opts = {
            "SrcGcServiceCode" => source_vm,
            "ContractNum" => num.to_s,
            "VirtualMachineType" => vm_type
          }
          p clone_opts
          res = gp.add_clone_virtual_machines(clone_opts)
          new_gcs = res["GcServiceCodeList"]

          puts "response: #{new_gcs.inspect}"

          new_gcs.each do |gc_sc|
            gp_worker.set_vm_role(gc_sc, role)
          end

          new_gcs
        end

        def attach_to_pools(role, private_ip)
          gp_worker.lbs.each do |gl_sc, info|
            if info
              gl = config.gp_client.gl(gl_sc)
              gl_worker = GpManage::Worker::Gl.new(gl)

              config.fetch('lb')['pools'].each do |pool_setting|
                if pool_setting['roles'].include? role
                  begin
                    gl_worker.attach_to_pool(pool_setting['name'], pool_setting['port'], private_ip)
                  rescue => e
                    puts "[#{gl_sc}] Failed to attach #{private_ip} to the pool #{pool_setting['name']}."
                    puts e.inspect
                    puts e.backtrace
                  end
                end
              end
            else
              STDERR.puts "[#{gl_sc}] Fetching information failed. skip.."
            end
          end
        end

        def detach_from_pools(role, private_ip)
          gp_worker.lbs.each do |gl_sc, info|
            if info
              gl = config.gp_client.gl(gl_sc)
              gl_worker = GpManage::Worker::Gl.new(gl)

              config.fetch('lb')['pools'].each do |pool_setting|
                if pool_setting['roles'].include? role
                  begin
                    gl_worker.detach_from_pool(pool_setting['name'], pool_setting['port'], private_ip)
                  rescue => e
                    puts "[#{gl_sc}] Failed to detach #{private_ip} from the pool #{pool_setting['name']}."
                    puts e.inspect
                    puts e.backtrace
                  end
                end
              end
            else
              STDERR.puts "[#{gl_sc}] Fetching information failed. skip.."
            end
          end
        end
      end
    end

    register(VM, 'vm', 'vm [COMMAND]', 'commands for managing VMs')
  end
end
