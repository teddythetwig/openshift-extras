require 'rubygems'
require 'json'
require 'rest_client'
require 'openshift/load-balancer/controllers/load_balancer'

module OpenShift

  # == Asynchronous Load Balancer Controller
  #
  # Controller for a load balancer that implements an asynchronous API.  On
  # initalization, the object queries the configured load balancer to ascertain
  # existing pools and build a table of Pool objects.
  #
  class AsyncLoadBalancerController < LoadBalancerController

    # == Pool object
    #
    # Represents a pool.  On initialization, the object queries the load
    # balancer using the LoadBalancerController object provided as lb_controller
    # to obtain the members of the pool named by pool_name.  These pool members
    # are stored in @members using one string of the form address:port to
    # represent each pool member.
    #
    # The initializer can optionally be passed false for its fourth
    # argument to prevent it from querying the load balancer for the
    # members of the pool.  It may be desirable to suppress the request
    # when the pool has only just been created on the load balancer.
    #
    class Pool < LoadBalancerController::Pool
      attr_reader :members, :name

      def initialize lb_controller, lb_model, pool_name, request_members=true
        @lb_controller, @lb_model, @name = lb_controller, lb_model, pool_name
        if request_members
          @members = @lb_model.get_pool_members pool_name
        else
          @members = Array.new
        end
      end

      # Add a member to the object's internal list of members.  This
      # method does not update the load balancer; use the update method
      # of AsyncLoadBalancerController to send the updated list of pool
      # members to the load balancer.
      def add_member address, port
        member = address + ':' + port.to_s

        raise LBControllerException.new "Adding gear #{member} to pool #{@name}, of which the gear is already a member" if @members.include? member

        # :add_pool_member blocks
        # if the corresponding pool is being created,
        # if the pool member being added is the same as one that is being deleted, or
        # if the pool member being added is the same as one that is being added
        #   (which can be the case if the same pool member is being added,
        #   deleted, and added again).
        @lb_controller.queue_op Operation.new(:add_pool_member, [self.name, address, port.to_s]), @lb_controller.ops.select {|op| (op.type == :create_pool && op.operands[0] == self.name) || ([:add_pool_member, :delete_pool_member].include?(op.type) && op.operands[0] == self.name && op.operands[1] == address && op.operands[2] == port.to_s)}

        @members.push member
      end

      # Remove a member from the object's internal list of members.
      # This method does not update the load balancer; use the update
      # method of AsyncLoadBalancerController to force an update.
      def delete_member address, port
        member = address + ':' + port.to_s

        raise LBControllerException.new "Deleting gear #{member} from pool #{@name}, of which the gear is not a member" unless @members.include? member

        # :delete_pool_member blocks
        # if the corresponding pool is being created,
        # if the pool member being deleted is the same as one that is being added, or
        # if the pool member being deleted is the same as one that is being deleted
        #   (which can be the case if the same pool member is being added,
        #   deleted, added, and deleted again).
        @lb_controller.queue_op Operation.new(:delete_pool_member, [self.name, address, port.to_s]), @lb_controller.ops.select {|op| (op.type == :create_pool && op.operands[0] == self.name) || ([:add_pool_member, :delete_pool_member].include?(op.type) && op.operands[0] == self.name && op.operands[1] == address && op.operands[2] == port.to_s)}

        @members.delete member
      end
    end

    # AsyncLoadBalancerController is designed to be used with a load balancer
    # that provide an asynchronous interface.  Operations such as creating and
    # deleting pools, pool members, and routing rules are submitted to the load
    # balancer, which returns a list of job ids and performs the operations
    # asynchronously.
    #
    # It is our responsibility to ensure that we defer operations that depend on
    # other operations until the load balancer reports that the latter
    # operations are complete.  To that end, we maintain a table of submitted
    # operations, where each Operation corresponds to an operation that is to be
    # or has been submitted to the load balancer.
    #
    # When we are told to carry out an operation, first we check whether it must
    # wait for any Operation in @ops.  We set @blocked_on_cnt of the new
    # Operation to the number of operations on which it must wait, append the
    # new Operation to the @blocked_ops of the corresponding Operation objects,
    # and add the new Operation to @ops.
    #
    # If an Operation has an empty jobids, then it has not been submitted to
    # the load balancer.  If an Operation has non-empty jobids, then it has
    # been submitted to the load balancer and is in progress.
    #
    # If an Operation has not been submitted to the load balancer but has a zero
    # @blocked_on_cnt, then it is ready to be submitted.
    #
    # We periodically submit all ready Operation objects in @ops (i.e., those
    # that have zero @blocked_on_cnt and empty @jobids) to the load balancer.
    # When an operation is submitted, we assign the job ids returned by the load
    # balancer to @jobids of the corresponding Operation objects.
    #
    # We can poll the load balancer using the poll_async_jobs method.  When the
    # load balancer reports that some job has finished, we delete that job from
    # @jobids of the Operation.  If @jobids is empty, then the Operation has
    # completed.
    #
    # When an Operation completes, we check its @blocked_ops attribute,
    # decrement the @blocked_on_cnt for each Operation therein, and delete the
    # completed Operation from @ops.
    #
    # Although we try to ensure that a given operation is not submitted to the
    # load balancer before the load balancer has completed all operations on
    # which the first operation depends, we do not necessarily handle
    # out-of-order events.  For example, if a pool is created and deleted and
    # then a route is added, the create-route operation may be submitted before
    # or after the delete-pool operation is performed.  (The create-route
    # operation will, in any case, be submitted to the load balancer _after_ the
    # create-pool operation is submitted.)
    #
    # Because we only ever make a new Operation block on existing Operation
    # objects, deadlocks are not possible.
    Operation = Struct.new :type, :operands, :blocked_on_cnt, :jobids, :blocked_ops
    # Symbol, [Object], [String], [Operation], Integer
    # XXX: All instances of Operation have a pool name (String) as the first
    # operand; it might be clearer to move this operand into a new unique
    # field of Operand.

    attr_reader :ops # [Operation]
    attr_reader :routes, :active_routes, :monitors

    def read_config
      cfg = ParseConfig.new('/etc/openshift/load-balancer.conf')

      @lbaas_host = cfg['LBAAS_HOST'] || '127.0.0.1'
      @lbaas_keystone_host = cfg['LBAAS_KEYSTONE_HOST'] || @lbaas_host
      @lbaas_username = cfg['LBAAS_USERNAME'] || 'admin'
      @lbaas_password = cfg['LBAAS_PASSWORD'] || 'passwd'
      @lbaas_tenant = cfg['LBAAS_TENANT'] || 'lbms'

      @virtual_server_name = cfg['VIRTUAL_SERVER']

      @debug = cfg['DEBUG'] == 'true'
    end

    # Set the @blocked_on_cnt of the given Operation to the size of the given
    # Array of Operations, add the Operation to @blocked_ops of each of those
    # operations, and finally add the Operation to @ops.
    #
    # Users of queue_op are responsible for computing the Array of Operations
    # that block the new Operation.  It is good practice to document how this
    # Array is computed for each invocation of queue_op.
    def queue_op newop, blocking_ops
      raise LBControllerException.new 'Got an operation with no type' unless newop.type
      newop.operands ||= []
      newop.blocked_on_cnt = blocking_ops.count
      newop.jobids ||= []
      newop.blocked_ops ||= []
      blocking_ops.each {|op| op.blocked_ops.push newop}
      @ops.push newop
    end

    def reap_op op
      op.blocked_ops.each {|blocked_op| blocked_op.blocked_on_cnt -= 1}
      @ops.delete op
    end

    def reap_op_if_no_remaining_tasks op
      if op.jobids.empty?
        $stderr.puts "Deleting completed operation: #{op.type}(#{op.operands.join ', '})."
        reap_op op
      end
    end

    def cancel_op op
      op.blocked_ops.each {|op| cancel_op op}
      $stderr.puts "Cancelling operation: #{op.type})(#{op.operands.join ', '})."
      @ops.delete op
    end

    def create_pool pool_name, monitor_name=nil
      raise LBControllerException.new "Pool already exists: #{pool_name}" if @pools.include? pool_name

      # :create_pool blocks
      # if the corresponding monitor is being created or
      # if the corresponding pool is being deleted
      #   (which can be the case if the same pool is being added, deleted, and added again).
      #
      # The pool does not depend on any other objects; we must ensure
      # only that we are not creating a pool at the same time that we
      # are deleting pool of the same name.
      queue_op Operation.new(:create_pool, [pool_name, monitor_name]), @ops.select {|op| (op.type == :delete_pool && op.operands[0] == pool_name) || (op.type == :create_monitor && op.operands[0] == monitor_name)}

      @pools[pool_name] = Pool.new self, @lb_model, pool_name, false
    end

    def delete_pool pool_name
      raise LBControllerException.new "Pool not found: #{pool_name}" unless @pools.include? pool_name

      raise LBControllerException.new "Deleting pool that is already being deleted: #{pool_name}" if @ops.detect {|op| op.type == :delete_pool && op.operands == [pool_name]}

      # :delete_pool blocks
      # if the corresponding pool is being created,
      # if the corresponding route is being deleted,
      # if members are being added to the pool, or
      # if members are being deleted from the pool.
      #
      # Hypothetically, it would cause a problem if we were trying to
      # delete a pool that is already being deleted, which can be the
      # case if the same pool is being added, deleted, added, and
      # deleted again.  However, because we block on :create_pool, we
      # will block on the :create_pool event that is blocking on the
      # previous :delete_pool event.
      #
      # Along similar lines, checking for :delete_route and
      # :delete_pool_member is sufficient; it is not necessary to check
      # for :create_route and :add_pool_member.
      #
      # The pool is not depended upon on by any other objects besides
      # routes and pool members 
      queue_op Operation.new(:delete_pool, [pool_name]), @ops.select {|op| [:delete_route, :delete_pool_member, :create_pool].include?(op.type) && op.operands[0] == pool_name}

      @pools.delete pool_name
    end

    def create_route pool_name, route_name, path
      raise LBControllerException.new "Pool not found: #{pool_name}" unless @pools.include? pool_name

      raise LBControllerException.new "Route already exists: #{route_name}" if @routes.include? route_name

      # :create_route blocks
      # if the corresponding pool is being created.
      #
      # For reasoning similar to that described above for :delete_pool,
      # it is sufficient to check just for :create_pool.
      queue_op Operation.new(:create_route, [pool_name, route_name, path]), @ops.select {|op| op.type == :create_pool && op.operands[0] == pool_name}

      # :attach_route blocks on the :create_route operation we just queued.
      queue_op Operation.new(:attach_route, [route_name, @virtual_server_name]), @ops.select {|op| op.type == :create_route && op.operands[1] == route_name} if @virtual_server_name

      @routes.push route_name
    end

    def delete_route pool_name, route_name
      raise LBControllerException.new "Pool not found: #{pool_name}" unless @pools.include? pool_name

      raise LBControllerException.new "Route not found: #{route_name}" unless @routes.include? route_name

      # :detach_route blocks
      # if the route is being attached, or
      # if the route is being detached
      #   (which can be the case if the same route is being created, attached, detached, deleted, created, attached, and detached).
      queue_op Operation.new(:detach_route, [route_name, @virtual_server_name]), @ops.select {|op| [:attach_route, :detach_route].include?(op.type) && op.operands[0] == route_name} if @virtual_server_name

      # :delete_route blocks
      # if the route is being detached,
      # if the route is being created,
      # if the corresponding pool is being created, or
      # if the route is being deleted
      #   (which can be the case if the same pool and route are being created, deleted, created, and deleted again).
      queue_op Operation.new(:delete_route, [pool_name, route_name]), @ops.select {|op| (op.type == :detach_route && op.operands[0] == route_name) || (op.type == :create_pool && op.operands[0] == pool_name) || (op.type == :create_route && op.operands[0] == pool_name && op.operands[1] == route_name)}

      @routes.delete route_name
    end

    def create_monitor monitor_name, path, up_code
      raise LBControllerException.new "Monitor already exists: #{monitor_name}" if @monitors.include? monitor_name

      # :create_monitor blocks
      # if a monitor of the same name is currently being deleted.
      queue_op Operation.new(:create_monitor, [monitor_name, path, up_code]), @ops.select {|op| op.type == :delete_monitor_pool && op.operands[0] == monitor_name}

      @monitors.push monitor_name
    end

    def delete_monitor monitor_name
      raise LBControllerException.new "Monitor not found: #{monitor_name}" unless @monitors.include? monitor_name

      # :delete_monitor blocks
      # if the monitor is being created.
      queue_op Operation.new(:delete_monitor, [pool_name, route_name]), @ops.select {|op| op.type == :create_monitor && op.operands[0] == monitor_name}

      @monitors.delete monitor_name
    end

    # Update the load balancer with any queued updates.
    def update
      # Check whether any previously submitted operations have completed.
      poll_async_jobs
      # TODO: Consider instead exposing poll_async_jobs for
      # LoadBalancerConfigurationDaemon to invoke directly.

      # Filter out operations that involve pools that are in the process
      # of being added to the load balancer, as denoted by the existence
      # of job ids associated with such pools, and jobs that are waiting
      # on other jobs.  Note that order is preserved.
      # [Operation] -> [Operation]
      ready_ops = @ops.select {|op| op.jobids.empty? && op.blocked_on_cnt.zero?}

      # Take ready_ops and translate it into a hash where the keys are the pool
      # names and the values are Operation objects.  Note that the order in
      # which Operation objects appear in ready_ops is preserved.
      # [Operation] -> {String => [Operation]}
      #pool_ready_ops = ready_ops.inject(Hash.new {Array.new}) {|h,(k,v)| h[k] = h[k].push v; h}
      # TODO: Delete pairs of Operation objects that cancel out (e.g.,
      # an :add_pool_member and a :delete_pool_member operation that
      # for the same member, when neither operation has been submitted
      # or blocks another operation).

      # Submit ready operations to the load balancer.
      # TODO: We can combine like operations.
      ready_ops.each do |op|
        op.jobids = @lb_model.send op.type, *op.operands
        $stderr.puts "Submitted operation to LBaaS: #{op.type}(#{op.operands.join ', '}); got back jobids #{op.jobids.join ', '}."

        # In case the operation generates no jobs and is immediately done, we
        # must reap it now because there will be no completion of a job to
        # trigger the reaping.
        reap_op_if_no_remaining_tasks op
      end
    end

    # Returns a Hash representing the JSON response from the load balancer.
    def get_job_status id
      @lb_model.get_job_status id
    end

    # Poll the load balancer for completion of submitted jobs and handle any
    # jobs that are completed.
    def poll_async_jobs
      submitted_ops = @ops.select {|op| not op.jobids.empty?}
      # [Operation] -> [Operation]

      jobs = submitted_ops.map {|op| op.jobids.map {|id| [op,id]}}.flatten(1)
      # [Operation] -> [[Operation,String]]

      jobs.each do |op,id|
        status = @lb_model.get_job_status id
        case status['Tenant_Job_Details']['status']
        when 'PENDING'
          # Nothing to do but wait some more.
        when 'COMPLETED'
          raise LBControllerException.new "Asked for status of job #{id}, load balancer returned status of job #{status['Tenant_Job_Details']['jobId']}" unless id == status['Tenant_Job_Details']['jobId']

          # TODO: validate that status['requestBody'] is consistent with op.

          $stderr.puts "LBaaS reports job #{id} completed."
          op.jobids.delete id
          reap_op_if_no_remaining_tasks op
        when 'FAILED'
          $stderr.puts "LBaaS reports that job #{id} failed.  Cancelling associated operation and any operations that it blocks..."

          cancel_op op

          $stderr.puts "Done."
        else
          raise LBControllerException.new "Got unknown status #{status['Tenant_Job_Details']['status']} for status job #{id}."
        end
      end
    end

    def initialize lb_model_class
      read_config

      @lb_model = lb_model_class.new @lbaas_host, @lbaas_username, @lbaas_password, @lbaas_tenant

      $stderr.print "Authenticating with keystone at host #{@lbaas_keystone_host}...\n"
      @lb_model.authenticate @lbaas_keystone_host, @lbaas_username, @lbaas_password, @lbaas_tenant

      # If the pool has been created or is being created in the load balancer, it will be in @pools.
      @pools = Hash[@lb_model.get_pool_names.map {|pool_name| [pool_name, Pool.new(self, @lb_model, pool_name)]}]

      # If the route is already created or is being created in the load balancer, it will be in @routes.
      @routes = @lb_model.get_active_route_names

      # If the monitor is already created or is being created in the load balancer, it will be in @monitors.
      @monitors = @lb_model.get_monitor_names

      # If an Operation has been created but not yet completed (whether
      # because it is blocked on one or more other Operations, because
      # it has not been submitted to the load balancer, or because it
      # has been submitted but the load balancer has not yet reported
      # completion), it will be in @ops.
      @ops = []
    end
  end

end
