module GpManage
  module Worker
    class Gl
      def initialize(gl)
        @gl = gl
      end
      attr_reader :gl

      def attach_to_pool(pool, port, private_ip)
        puts "[#{gl.gl_service_code}] Try to attach #{private_ip} to the pool #{pool}..."

        lb_pool = gl.lb_info['PoolList'].find{|lb_pool| lb_pool['Name'] == pool }
        if lb_pool
          puts "[#{gl.gl_service_code}] Attach #{private_ip}:#{port} to the pool #{pool}.."
          if lb_pool['NodeList'].find{|node| node['IpAddress'] == private_ip }
            puts "[#{gl.gl_service_code}] #{private_ip}:#{port} is already attached to the pool #{pool}. skip."
          else
            gl.add_lb_node(lb_pool['Name'], [private_ip, port])
          end
        end
      end

      def detach_from_pool(pool, port, private_ip)
        puts "[#{gl.gl_service_code}] Try to detach #{private_ip} from the pool #{pool}..."

        lb_pool = gl.lb_info['PoolList'].find{|lb_pool| lb_pool['Name'] == pool }
        if lb_pool
          puts "[#{gl.gl_service_code}] Detach #{private_ip}:#{port} from the pool #{pool}.."
          if lb_pool['NodeList'].find{|node| node['IpAddress'] == private_ip }
            gl.delete_lb_node(lb_pool['Name'], [private_ip, port])
          else
            puts "[#{gl.gl_service_code}] #{private_ip}:#{port} is not a member of the pool #{pool}. skip."
          end
        end
      end
    end
  end
end
