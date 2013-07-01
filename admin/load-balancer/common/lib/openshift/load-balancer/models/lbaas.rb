require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == Load-balancer model class for an LBaaS load balancer.
  #
  # Presents direct access to a load balancer using the LBaaS REST API.
  #
  # This class contains minimal logic and no error checking; its sole
  # purpose is to hide REST calls behind a more convenient interface.
  class LBaaSLoadBalancerModel < LoadBalancerModel

    # Parses the response from a RestClient request to LBaaS and returns an
    # array of job ids.
    # String -> [String]
    def parse_jobids response
      begin
        JSON.parse(response)['Lb_Job_List']['jobIds']
      rescue => e
        $stderr.puts "Got exception parsing response: #{e.message}"
        $stderr.puts "Backtrace: #{e.backtrace}"
        $stderr.puts "Response: #{response}"
        []
      end
    end

    # Returns [String] of pool names.
    def get_pool_names
      JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['tenantpools']['pools']
    end

    # Returns [String] of job ids.
    def create_pool pool_name, monitor_name=nil
      monitor_name ||= 'http'

      response = RestClient.put("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}",
                                {
                                  :pool => {
                                    :name => pool_name,
                                    :method => 'LeastConnection',
                                    :port => '80',
                                    :enabled => 'true',
                                    :monitors => [monitor_name]
                                  }
                                }.to_json,
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of job ids.
    def delete_pool pool_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
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
                                    :rule => "{ when HTTP_REQUEST { if { [HTTP::uri] contains \"/webapps#{path}\" } { if { [string first -nocase \"/webapps\" [HTTP::uri]] == 3 } { scan [HTTP::uri] {/%[^/]%s} country final_uri; HTTP::header insert SPARTA_PRE_APP_CONTEXT $country; HTTP::uri $final_uri; }; pool #{pool_name}; } } }"
                                  }
                                }.to_json,
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    def attach_routes route_names, virtual_server_names
      # LBaaS supports adding multiple routes at once, but only to one virtual
      # server at a time.
      (virtual_server_names.zip route_names).group_by {|v,r| v}.map do |v,r|
        response = RestClient.post("http://#{@host}/loadbalancers/tenant/#{@tenant}/vips/#{v}/policies",
                                   {
                                     :policies => r.map {|v,r| {:name => r}}
                                   }.to_json,
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
        raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202
  
        parse_jobids response
      end.flatten 1
    end

    def detach_route route_name, virtual_server_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/vips/#{virtual_server_name}/policies/#{route_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of job ids.
    def delete_route pool_name, route_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/policies/#{route_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of monitor names.
    def get_monitor_names
      (JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/monitors/", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['monitor'] || []).map {|m| m['name']}
    end

    # Returns [String] of job ids.
    def create_monitor monitor_name, path, up_code
      response = RestClient.put("http://#{@host}/loadbalancers/tenant/#{@tenant}/monitors/#{monitor_name}",
                                {
                                  :monitor => {
                                    :name => monitor_name,
                                    :type => 'HTTP-ECV',
                                    :send => "GET #{path}",
                                    :rcv => up_code,
                                    :interval => '30',
                                    :timeout => '5',
                                    :downtime => '12'
                                  }
                                }.to_json,
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of job ids.
    def delete_monitor monitor_name
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/monitors/#{monitor_name}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of pool names.
    def get_pool_members pool_name
      begin
        (JSON.parse(RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}", :content_type => :json, :accept => :json, :'X-Auth-Token' => @keystone_token))['pool']['services'] || []).map {|p| p['name']}
      rescue => e
        $stderr.puts "Got exception while getting pool members: #{e.message}"
        $stderr.puts 'Backtrace:', e.backtrace
        []
      end
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
                                         :enabled => 'true',
                                         :name => address + ':' + port.to_s,
                                         :weight => "10",
                                         :port => port
                                       } end,
                                       :name => pool_name
                                     } end
                                 }.to_json,
                                 :content_type => :json,
                                 :accept => :json,
                                 :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 202 but got #{response.code} instead" unless response.code == 202

      parse_jobids response
    end

    # Returns [String] of job ids.
    def delete_pool_member pool_name, address, port
      response = RestClient.delete("http://#{@host}/loadbalancers/tenant/#{@tenant}/pools/#{pool_name}/services/#{address + '%3a' + port.to_s}",
                                   :content_type => :json,
                                   :accept => :json,
                                   :'X-Auth-Token' => @keystone_token)
      case response.code
      when 202
        parse_jobids response
      when 204
        []
      else
        raise LBModelException.new "Expected HTTP 202 or 204 but got #{response.code} instead"
      end
    end

    # Returns Hash representing the JSON response from the load balancer.
    def get_job_status id
      response = RestClient.get("http://#{@host}/loadbalancers/tenant/#{@tenant}/jobs/#{id}",
                                :content_type => :json,
                                :accept => :json,
                                :'X-Auth-Token' => @keystone_token)
      raise LBModelException.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

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
      raise LBModelException.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      temp_token = JSON.parse(response)['access']['token']['id']

      response = RestClient.get("http://#{host}/v2.0/tenants",
                                 :content_type => :json,
                                 :accept => :json,
                                 :'X-Auth-Token' => temp_token)
      raise LBModelException.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

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
      raise LBModelException.new "Expected HTTP 200 but got #{response.code} instead" unless response.code == 200

      @keystone_token = JSON.parse(response)['access']['token']['id']
    end

    def initialize host, user=nil, passwd=nil, tenant=nil
      @host, @user, @passwd, @tenant = host, user, passwd, tenant
    end

  end

end
