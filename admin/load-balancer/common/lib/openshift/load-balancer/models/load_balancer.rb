module OpenShift

  # == Abstract load-balancer model class
  #
  # Presents direct access to a load balancer.  This is an abstract class.
  #
  class LoadBalancerModel

    def get_pool_names
    end

    # create_pool :: String -> undefined
    # Note: At least one of create_pool and create_pools must be implemented.
    def create_pool pool_name
    end

    # create_pools :: [String] -> undefined
    # Note: At least one of create_pool and create_pools must be implemented.
    def create_pools pool_names
      pool_names.map {|pool_name| create_pool pool_name}.flatten 1
    end

    # delete_pool :: String -> undefined
    # Note: At least one of delete_pool and delete_pools must be implemented.
    def delete_pool pool_name
    end

    # delete_pools :: [String] -> undefined
    # Note: At least one of delete_pool and delete_pools must be implemented.
    def delete_pools pool_names
      pool_names.map {|pool_name| delete_pool pool_name}.flatten 1
    end

    def get_route_names
    end

    def get_active_route_names
    end

    # create_route :: String, String, String -> undefined
    # Note: At least one of create_route and create_routes must be implemented.
    def create_route pool_name, route_name, path
      create_routes [pool_name], [[route_name, path]]
    end

    # create_routes :: [String], [[String,String]] -> undefined
    # Each route comprises a name and a path.
    # Note: At least one of create_route and create_routes must be implemented.
    def create_routes pool_names, routes
      (pool_names.zip routes).map {|pool,(route,path)| create_route pool, route, path}.flatten 1
    end

    # delete_route :: String, String -> undefined
    # Note: At least one of delete_route and delete_routes must be implemented.
    def delete_route pool_name, route_name
      delete_routes [pool_name], [route_name]
    end

    # delete_routes :: [String], [String] -> undefined
    # Note: At least one of delete_route and delete_routes must be implemented.
    def delete_routes pool_names, route_names
      (pool_names.zip route_names).map {|pool,route| delete_route pool, route}.flatten 1
    end

    # get_pool_members :: String -> [String]
    def get_pool_members pool_name
    end

    # get_active_pool_members :: String -> [String]
    def get_active_pool_members pool_name
    end

    # add_pool_member :: String, String, Integer -> undefined
    # Note: At least one of add_pool_member and add_pool_members must be
    # implemented.
    def add_pool_member pool_name, address, port
      add_pool_members [pool_name], [[address, port]]
    end

    # add_pool_members :: [String], [[[String,Integer]]] -> undefined
    # Each member comprises an IP address in dotted-quad representation and a port.
    # Note: At least one of add_pool_member and add_pool_members must be
    # implemented.
    def add_pool_members pool_names, member_lists
      (pool_names.zip member_lists).map do |pool,members|
        members.map {|address,port| add_pool_member pool, address, port}
      end.flatten 2
    end

    # delete_pool_member :: String, String, Integer -> undefined
    # Note: At least one of delete_pool_member and delete_pool_members must be
    # implemented.
    def delete_pool_member pool_name, address, port
      delete_pool_members [pool_name], [[address, port]]
    end

    # delete_pool_members :: [String], [[[String,Integer]]] -> undefined
    # Note: At least one of delete_pool_member and delete_pool_members must be
    # implemented.
    def delete_pool_members pool_names, member_lists
      (pool_names.zip member_lists).map do |pool,members|
        members.map {|address,port| delete_pool_member pool, address, port}
      end.flatten 2
    end

    # get_job_status :: String -> Object
    # This is only needed if the model is being used with
    # AsyncLoadBalancerController.
    def get_job_status id
    end

    def authenticate host=@host, user=@user, passwd=@passwd
    end

    def initialize host=nil, user=nil, passwd=nil
      @host, @user, @passwd = host, user, passwd
    end

  end

end
