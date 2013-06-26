module OpenShift

  # == Example load-balancer model class
  #
  # Provides implements the LoadBalancerModel interface with dummy methods that
  # just print output to the terminal without actually taking action against a
  # load balancer.
  #
  class DummyLoadBalancerModel < LoadBalancerModel

    def get_pool_names
      puts "get pool names"
      []
    end

    def create_pool pool_name, monitor_name
      puts "create pool #{pool_name} with monitor #{monitor_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_pool pool_name
      puts "delete pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_route_names
      puts "get route names"
      [] # Return an array of String representing routes.
    end

    def get_active_route_names
      puts "get active route names"
      [] # Return an array of String representing routes.
    end

    def create_route pool_name, route_name, path
      puts "create route #{route_name} from path #{path} to pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def attach_route route_name, virtual_server_name
      puts "attach route #{route_name} to virtual server #{virtual_server_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def detach_route route_name, virtual_server_name
      puts "detach route #{route_name} from virtual server #{virtual_server_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_route pool_name, route_name
      puts "delete route #{route_name} associated with pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_monitor_names
      puts "get monitor names"
      [] # Return an array of String representing monitors.
    end

    def create_monitor monitor_name, path, up_code
      puts "create monitor #{monitor_name} using path #{path} where '#{up_code}' means up"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_monitor monitor_name
      puts "delete monitor #{monitor_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_pool_members pool_name
      puts "get members of pool #{pool_name}"
      [] # Return an array of String representing pool members.
    end

    def get_active_pool_members
      puts "get active members of pool #{pool_name}"
      [] # Return an array of String representing pool members.
    end

    def add_pool_member pool_name, address, port
      puts "add member #{address}:#{port} to pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_pool_members pool_name, address, port
      puts "delete member #{address}:#{port} from pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_job_status id
      puts "return status of job #{id}"
      "some JSON"
    end

    def authenticate host=@host, user=@user, passwd=@passwd
      puts "do some authentication stuff"

      @foo = "some temporary token or connection object"
    end

    def initialize host=nil, user=nil, passwd=nil
      @host, @user, @passwd = host, user, passwd
      puts "do initialization stuff"
    end

  end

end
