module OpenShift

  class LBControllerException < StandardError; end

  # == Abstract load-balancer controller class
  #
  # Represents a load balancer for the OpenShift Enterprise
  # installation.  This is an abstract class.
  #
  class LoadBalancerController
    # == Abstract load-balancer pool controller object
    #
    # Represents a pool of a load balancer represented by an
    # OpenShift::LoadBalancerController object.  This is an abstract class.
    #
    class Pool
      attr_reader :name, :members

      # Add a member to the object's internal list of members.
      #
      # The arguments should be a String comprising an IP address in
      # dotted quad form and an Integer comprising a port number.
      #
      # This method does not necessarily update the load balancer
      # itself; use the update method of the corresponding
      # LoadBalancerController object to send the updated list of pool
      # members to the load balancer.
      def add_member address, port
      end

      # Remove a list of members from the object's internal list of
      # members.
      #
      # The arguments should be a String comprising an IP address in
      # dotted quad form and an Integer comprising a port number.
      #
      # This method does not necessarily update the load balancer
      # itself; use the update method of the corresponding
      # LoadBalancerController object to send the updated list of pool
      # members to the load balancer.
      def delete_member address, port
      end
    end

    # @pools is a hash that maps String to LoadBalancerPool.
    attr_reader :pools

    def create_pool pool_name, monitor_name=nil
    end

    def delete_pool pool_name
    end

    def create_route profile_name, profile_path, pool_name
    end

    def delete_route profile_name
    end

    # Push pending pool add_member and delete_member operations to the
    # load balancer.
    def update
    end
  end

end
