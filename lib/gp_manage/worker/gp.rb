# -*- coding: utf-8 -*-
module GpManage
  module Worker
    class Gp
      def initialize(config, vm_store)
        @config = config
        @gp = config.gp_client
        @vm_store = vm_store
      end
      attr_reader :gp
      attr_reader :vm_store

      def vms(update_cache = false)
        cache = vm_store.transaction{|store| store[:vm_cache] } || {}
        vms = vm_store.transaction{|store| store[:vms] } || {}

        gc_sc_list = gp.service_code_list['GcServiceCodeList']
        ret = {}

        gc_sc_list.each do |gc_sc|
          info = cache[gc_sc]
          if update_cache or info.nil?
            # FIXME: InService でないものを除外すべきだが、握りつぶす
            info = gp.gc(gc_sc).describe_virtual_machine rescue nil
            vm_store.transaction do |store|
              store[:vm_cache] ||= {}
              store[:vm_cache][gc_sc] = info
            end
          end
          ret[gc_sc] = vms[gc_sc] || {}
          ret[gc_sc][:info] = info
        end

        ret
      end

      def vm_status_map
        contracts = contract_status_map
        gc_sc_list = gp.service_code_list['GcServiceCodeList']
          .select{|gc_sc| contracts[gc_sc]['Status'] == 'InService' }

        gp.get_virtual_machine_status_list(gc_sc_list)['VirtualMachineStatusList'].inject({}) do |stow, gc_status|
          stow[gc_status['GcServiceCode']] = gc_status['Status']
          stow
        end
      end

      def set_vm_role(gc_sc, role)
        vm_store.transaction do |store|
          store[:vms] ||= {}
          store[:vms][gc_sc] = { :role => role }
        end
      end

      def set_vm_label(gc_sc, label)
        gp.gc(gc_sc).label = label
      end

      def attach_fwlb(gc_sc, gl_sc)
        gp.gc(gc_sc).attach_fwlb(gl_sc)
      end

      def detach_fwlb(gc_sc, gl_sc)
        gp.gc(gc_sc).detach_fwlb(gl_sc)
      end

      def lbs(update_cache = false)
        cache = vm_store.transaction{|store| store[:lb_cache] } || {}
        lbs = vm_store.transaction{|store| store[:lbs] } || {}

        gl_sc_list = gp.service_code_list['GlServiceCodeList']
        ret = {}

        gl_sc_list.each do |gl_sc|
          info = cache[gl_sc]
          if update_cache or info.nil?
            begin
              # FIXME InService でないものを除外すべきだが握り潰す
              lb_info = gp.gl(gl_sc).describe_lb
              info = { :lb_info => lb_info }
            rescue => e
              info = nil
            end
            vm_store.transaction do |store|
              store[:lb_cache] ||= {}
              store[:lb_cache][gl_sc] = info
            end
          end
          ret[gl_sc] = (info || {}).merge(lbs[gl_sc] || {})
        end

        ret
      end

      def contract_status_map
        ret = {}

        contracts = gp.contract_information
        [
         [ 'VirtualMachineList', 'GcServiceCode' ],
         [ 'NASBOptionList', 'GnbServiceCode' ],
         [ 'VLANOptionList', 'GxServiceCode' ],
         [ 'FWLBOptionList', 'GlServiceCodeList' ],
         [ 'VPNTypeMOptionList', 'GvmServiceCode' ],
         [ 'VPNTypeSOptionList', 'GvsServiceCode' ],
         [ 'SMMOptionList', 'GomServiceCode' ]
        ].each do |key, sckey|
          contracts[key].each do |status|
            ret[status[sckey]] = status
          end
        end

        ret
      end

      def wait_for_in_service_list(sc_list, sleep_sec = 60)
        sc_list = [sc_list] unless sc_list.kind_of? Array
        loop do
          puts "Getting contract information.."
          status_map = contract_status_map
          sc_list.each do |sc|
            status = (status_map[sc] || {})['Status']
            puts "-- #{sc}: #{status}"
          end

          return if sc_list.all? {|sc| (status_map[sc] || {})['Status'] == "InService"  }

          sleep sleep_sec
        end
      end

      def wait_for_in_service(cli, sleep_sec = 60)
        while (cur = cli.get_contract_status) != "InService"
          yield cur if block_given?
          sleep sleep_sec
        end
      end

      def wait_for(checker, sc_list, sleep_sec = 60)
        loop do
          puts "Getting VM status.."
          status_list = gp.get_virtual_machine_status_list(sc_list)['VirtualMachineStatusList']
          status_list.each do |status|
            puts "-- #{status['GcServiceCode']}: #{status['Status']}"
          end

          return if status_list.all? {|status| checker.call(status['Status']) }

          sleep sleep_sec
        end
      end

      def wait_for_start(sc_list, sleep_sec = 60)
        wait_for(proc {|status| status == "Running"}, sc_list, sleep_sec)
      end
    end
  end
end
