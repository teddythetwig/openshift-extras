require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == Load-balancer model class for the F5 BIG-IP LTM load balancer.
  #
  # Presents direct access to an F5 BIG-IP LTM load balancer using the
  # iControl SOAP interface.
  #
  class F5LoadBalancerModel < LoadBalancerModel

    def get_pool_names
      @bigip['LocalLB.Pool'].get_list
    end

    def create_pools pool_names
      @bigip['LocalLB.Pool'].create pool_names, ['LB_METHOD_ROUND_ROBIN'], []
    end

    def delete_pools pool_names
      @bigip['LocalLB.Pool'].delete_pool pool_names
    end

    def get_route_names
      @bigip['LocalLB.ProfileHttpClass'].get_list
    end

    def get_active_route_names
      @bigip['LocalLB.VirtualServer'].get_httpclass_profile(['ose-vlan'])[0].map{|profile| profile.profile_name}
    end

    def create_routes pool_names, routes
      route_names, paths = routes.transpose
      priority = @bigip['LocalLB.VirtualServer'].get_httpclass_profile(['ose-vlan'])[0].map{|pri| pri.priority}.max || 0
      @bigip['LocalLB.ProfileHttpClass'].create route_names
      @bigip['LocalLB.ProfileHttpClass'].add_path_match_pattern route_names, paths.map {|path| [{:pattern=>path, :is_glob=>true}]}
      @bigip['LocalLB.ProfileHttpClass'].set_pool_name route_names, pool_names.map{|name| {:value=>name, :default_flag=>false}}
      @bigip['LocalLB.ProfileHttpClass'].set_rewrite_url route_names, route_names.map{|| {:value=>'/', :default_flag=>false}}
      @bigip['LocalLB.VirtualServer'].add_httpclass_profile ['ose-vlan'], [route_names.map {|name| {:profile_name=>name, :priority=>(priority += 1)}}]
    end

    def delete_routes pool_names, route_names
      @bigip['LocalLB.VirtualServer'].remove_httpclass_profile ['ose-vlan'], [route_names.map {|n| {:profile_name=>n, :priority=>0}}]
      @bigip['LocalLB.ProfileHttpClass'].delete_profile route_names
    end

    def get_pool_members pool_name
      @bigip['LocalLB.Pool'].get_member([pool_name])[0].collect do |pool_member|
          pool_member['address'] + ':' + pool_member['port'].to_s
        end
    end

    alias_method :get_active_pool_members, :get_pool_members

    def add_pool_members pool_names, member_lists
      @bigip['LocalLB.Pool'].add_member pool_names, member_lists.map {|members| members.map {|address,port| { 'address' => address, 'port' => port }}}
    end

    def delete_pool_members pool_names, member_lists
      @bigip['LocalLB.Pool'].remove_member pool_names, member_lists.map {|members| members.map {|address,port| { 'address' => address, 'port' => port }}}
    end

    def authenticate host=@host, user=@user, passwd=@passwd
      @bigip = F5::IControl.new(host, user, passwd,
                                ['System.Session', 'LocalLB.Pool', 'LocalLB.VirtualServer', 'LocalLB.ProfileHttpClass']).get_interfaces
    end

  end

end
