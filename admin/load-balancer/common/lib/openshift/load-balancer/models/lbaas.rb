require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == Load-balancer model class for an LBaaS load balancer.
  #
  # Presents direct access to a load balancer using the LBaaS REST API.
  #
  # This class contains minimal logic and no error checking; its sole
  # purpose is to hide REST calls behind a more convenient interface.
  class LBaaSLoadBalancerModel < LoadBalancerModel

    # Returns [String] of pool names.
    def get_pool_names
      JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['tenantpools']['pools']
    end

    # Returns [String] of job ids.
    def create_pool pool_name, monitor_name='http'
      response = RestClient.put("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}",
                                {
                                  :pool => {
                                    :name => pool_name,
                                    :method => 'LeastConnection',
                                    :port => '80',
                                    :enabled => false,
                                    :monitors => [monitor_name]
                                  }
                                }.to_json,
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      JSON.parse(response)['Lb_Job_List']['jobIds']
    end

    # Returns [String] of job ids.
    def delete_pool pool_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      JSON.parse(response)['Lb_Job_List']['jobIds']
    end

    # Returns [String] of route names.
    def get_route_names
      JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/policies", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['policy'].map {|p| p['name']}
    end

    def get_active_route_names
      @bigip['LocalLB.VirtualServer'].get_httpclass_profile(['ose-vlan'])[0].map{|profile| profile.profile_name}
    end
    alias_method :get_active_route_names, :get_route_names

    # Returns [String] of job ids.
    def create_route pool_name, route_name, path
      response = RestClient.put("http://#{@host}/loadbalancers/tenant/#{@tenant}/policies/#{route_name}",
                                {
                                  :policy => {
                                    :name => route_name,
                                    :rule => "when HTTP_REQUEST { if {[HTTP::path] starts_with \"#{path}\"} {pool #{pool_name}} else {pool #{@default_pool}}}"
                                  }
                                }.to_json,
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      JSON.parse(response)['Lb_Job_List']['jobIds']
    end

    # Returns [String] of job ids.
    def delete_route pool_name, route_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/policies/#{route_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      JSON.parse(response)['Lb_Job_List']['jobIds']
    end

    # Returns [String] of pool names.
    def get_pool_members pool_name
      (JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['pool']['services'] || []).map {|p| p['href'].scan(%r[/loadbalancers/[^/]+/pools/[^/]+/services/(.*)]).first.first}
    end

    alias_method :get_active_pool_members, :get_pool_members

    # Returns [String] of job ids.
    def add_pool_members pool_names, member_lists
      response = RestClient.post("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools",
                                 {
                                   :pool =>
                                     (pool_names.zip member_lists).map do |pool_name, members| {
                                       :services => members.map do |address,port| {
                                         :ip => address,
                                         :enabled => false,
                                         :name => address + ':' + port.to_s,
                                         :weight => 10,
                                         :port => port
                                       } end,
                                       :name => pool_name
                                     } end
                                 }.to_json,
                                 :content_type => :json,
                                 :accept => :json,
                                 :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      JSON.parse(response)['Lb_Job_List']['jobIds']
    end

    # Returns [String] of job ids.
    def delete_pool_member pool_name, address, port
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/services/#{address + ':' + port.to_s}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      case response.code
      when 202
        JSON.parse(response)['Lb_Job_List']['jobIds']
      when 204
        []
      else
        raise Exception.new "Expected HTTP 202 or 204 but got #{response.code} instead"
      end
    end

    # Returns Hash representing the JSON response from the load balancer.
    def get_job_status id
      response = RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/jobs/#{id}",
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise Exception.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      JSON.parse(response)
    end

    # Returns String representing the keystone token and sets @keystone_token to
    # the same.  This method must be called before the others, which use
    # @keystone_token.
    def authenticate host, user=@user, passwd=@passwd, tenant=@tenant
      response = RestClient.post("http://#{host}/v2.0/tokens",
                                 {
                                   :auth => {
                                     :passwordCredentials => {
                                       :username => user,
                                       :password => passwd
                                     }
                                   }
                                 }.to_json,
                                 :content_type => :json,
                                 :accept => :json)
      raise Exception.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      temp_token = JSON.parse(response)['access']['token']['id']

      response = RestClient.get("http://#{host}/v2.0/tenants",
                                 :content_type => :json,
                                 :accept => :json,
                                 :'X-Auth-Token' => temp_token)
      raise Exception.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      tenant_id = JSON.parse(response)['tenants'].select {|t| t['name'] == user}.first['id']

      response = RestClient.post("http://#{host}/v2.0/tokens",
                                 {
                                   :auth => {
                                     :project => 'lbms',
                                     :passwordCredentials => {
                                       :username => user,
                                       :password => passwd
                                     },
                                     :tenantId => tenant_id
                                   }
                                 }.to_json,
                                 :content_type => :json,
                                 :accept => :json)
      raise Exception.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      @keystone_token = JSON.parse(response)['access']['token']['id']
    end

    def initialize host, user=nil, passwd=nil, tenant=nil
      @host, @user, @passwd, @tenant = host, user, passwd, tenant
      @default_pool = 'foo-443'
      # XXX: Dehardcode @default_pool.
    end

  end

end
