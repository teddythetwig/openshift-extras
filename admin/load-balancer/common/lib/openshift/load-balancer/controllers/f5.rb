require 'rubygems'
require 'f5-icontrol'
require 'parseconfig'
require 'openshift/load-balancer/controllers/load_balancer'
require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == F5 Load Balancer Controller
  #
  # Represents the F5 load balancer for the OpenShift Enterprise
  # installation.  On initalization, the object queries the configured
  # F5 BIG-IP node for the configured pools and builds a table of Pool
  # objects.
  #
  class F5LoadBalancerController < LoadBalancerController

    # == F5 Pool object
    #
    # Represents the F5 pool.  On initialization, the object queries F5
    # BIG-IP using the F5LoadBalancerController object provided as bigip
    # to obtain the members of the pool named by pool_name.  These pool
    # members are stored in @members using one string of the form
    # address:port to represent each pool member.
    #
    class Pool < LoadBalancerController::Pool
      attr_reader :members

      def initialize lb_controller, lb_model, pool_name
        @lb_controller, @lb_model, @name = lb_controller, lb_model, pool_name
        @members = @lb_model.get_pool_members pool_name
      end

      # Add a member to the object's internal list of members.  This
      # method does not update F5; use the update method to send the
      # updated list of pool members to F5 BIG-IP.
      def add_member address, port
        member = address + ':' + port.to_s
        raise Exception.new "Adding gear #{member} to pool #{@name}, of which the gear is already a member" if @members.include? member
        @members.push member
        pending = [self.name, [address, port.to_s]]
        @lb_controller.pending_add_member_ops.push pending unless @lb_controller.pending_delete_member_ops.delete pending
      end

      # Remove a member from the object's internal list of members.
      # This method does not update F5; use the update method to force
      # an update.
      def delete_member address, port
        member = address + ':' + port.to_s
        raise Exception.new "Deleting gear #{member} from pool #{@name}, of which the gear is not a member" unless @members.include? member
        @members.delete member
        pending = [self.name, [address, port.to_s]]
        @lb_controller.pending_delete_member_ops.push pending unless @lb_controller.pending_add_member_ops.delete pending
      end
    end

    attr_reader :pending_add_member_ops, :pending_delete_member_ops
    attr_reader :routes, :active_routes
    attr_accessor :bigip if @debug

    def read_config
      cfg = ParseConfig.new('/etc/openshift/load-balancer.conf')

      @bigip_host = cfg['BIGIP_HOST'] || '127.0.0.1'
      @bigip_username = cfg['BIGIP_USERNAME'] || 'admin'
      @bigip_password = cfg['BIGIP_PASSWORD'] || 'passwd'

      @debug = cfg['DEBUG'] == 'true'
    end

    def create_pool pool_name
      raise Exception.new "Pool already exists: #{pool_name}" if @pools.include? pool_name

      @lb_model.create_pools [pool_name]

      @pools[pool_name] = Pool.new self, @lb_model, pool_name
    end

    def delete_pool pool_name
      raise Exception.new "Pool not found: #{pool_name}" unless @pools.include? pool_name

      update # in case we have pending delete operations for the pool.

      @lb_model.delete_pools [pool_name]

      @pools.delete pool_name
    end

    def create_route pool_name, profile_name, profile_path
      raise Exception.new "Profile already exists: #{profile_name}" if @routes.include? profile_name

      @lb_model.create_routes [pool_name], [[profile_name, profile_path]]

      @routes.push profile_name
      @active_routes.push profile_name
    end

    def delete_route pool_name, route_name
      raise Exception.new "Profile not found: #{route_name}" unless @routes.include? route_name

      @lb_model.delete_route [pool_name], [route_name] if @active_routes.include? route_name

      @routes.delete route_name
      @active_routes.delete route_name
    end

    def update
      adds = @pending_add_member_ops.inject(Hash.new {Array.new}) {|h,(k,v)| h[k] = h[k].push v; h}
      dels = @pending_delete_member_ops.inject(Hash.new {Array.new}) {|h,(k,v)| h[k] = h[k].push v; h}
      @lb_model.add_pool_members adds.keys, adds.values unless adds.empty?
      @lb_model.delete_pool_members dels.keys, dels.values unless dels.empty?
      @pending_add_member_ops = []
      @pending_delete_member_ops = []
    end

    def initialize lb_model
      read_config

      $stderr.print "Connecting to F5 BIG-IP at host #{@bigip_host}...\n"
      @lb_model = lb_model
      @lb_model.authenticate @bigip_host, @bigip_username, @bigip_password

      @pools = Hash[@lb_model.get_pool_names.map {|pool_name| [pool_name, Pool.new(self, @lb_model, pool_name)]}]
      @routes = @lb_model.get_route_names
      @active_routes = @lb_model.get_active_route_names

      @pending_add_member_ops = []
      @pending_delete_member_ops = []
    end
  end

end
