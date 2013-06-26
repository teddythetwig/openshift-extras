require 'rubygems'
require 'openshift/load-balancer/controllers/f5'
require 'openshift/load-balancer/models/f5'
require 'openshift/load-balancer/controllers/lbaas'
require 'openshift/load-balancer/models/lbaas'
require 'parseconfig'
require 'stomp'
require 'timeout'
require 'yaml'

module OpenShift

  # == Load Balancer Configuration Daemon
  #
  # Represents a daemon that listens for routing updates on ActiveMQ and
  # configures a remote load-balancer in accordance with those updates.
  # The remote load balancer is represented by an
  # OpenShift::LoadBalancerModel object and controlled using an
  # OpenShift::LoadBalancerController object.
  #
  class LoadBalancerConfigurationDaemon
    attr_accessor :lb, :aq if @debug

    def read_config
      cfg = ParseConfig.new('/etc/openshift/load-balancer.conf')

      @user = cfg['ACTIVEMQ_USER'] || 'routinginfo'
      @password = cfg['ACTIVEMQ_PASSWORD'] || 'routinginfopasswd'
      @host = cfg['ACTIVEMQ_HOST'] || 'activemq.example.com'
      @port = (cfg['ACTIVEMQ_PORT'] || 61613).to_i
      @destination = cfg['ACTIVEMQ_TOPIC'] || '/topic/routinginfo'
      @monitor_name_format = cfg['MONITOR_NAME']
      @monitor_path_format = cfg['MONITOR_PATH']

      @update_interval = (cfg['UPDATE_INTERVAL'] || 5).to_i

      # @lb_model and instances thereof should not be used except to
      # pass an instance of @lb_model_class to an instance of
      # @lb_controller_class.
      case cfg['LOAD_BALANCER'].downcase
      when 'f5'
        @lb_model_class = OpenShift::F5LoadBalancerModel
        @lb_controller_class = OpenShift::F5LoadBalancerController
      when 'lbaas'
        @lb_model_class = OpenShift::LBaaSLoadBalancerModel
        @lb_controller_class = OpenShift::AsyncLoadBalancerController
      else
        raise StandardError.new 'No load-balancer configured.'
      end

      @debug = cfg['DEBUG'] == 'true'
    end

    def initialize
      read_config

      $stderr.print "Initializing load-balancer controller...\n"
      @lb_controller = @lb_controller_class.new @lb_model_class
      $stderr.print "Found #{@lb_controller.pools.length} pools:\n"
      $stderr.print @lb_controller.pools.map{|k,v|"  #{k} (#{v.members.length} members)\n"}.join

      $stderr.print "Connecting to #{@host}:#{@port} as user #{@user}...\n"
      @aq = Stomp::Connection.open @user, @password, @host, @port, true

      $stderr.print "Subscribing to #{@destination}...\n"
      @aq.subscribe @destination, { :ack => 'client' }

      @last_update = Time.now
    end

    def listen
      $stderr.print "Listening...\n"
      while true
        begin
          msg = nil
          Timeout::timeout(@update_interval) { msg = @aq.receive }
          puts 'Received message:', '#v+', msg.body, '#v-' if @debug
          handle YAML.load(msg.body)
          @aq.ack msg.headers['message-id']
          update if Time.now - @last_update >= @update_interval
        rescue Timeout::Error => e
          update
        end
      end
    end

    def handle event
      begin
        case event[:action]
        when :create_application
          create_application event[:app_name], event[:namespace]
        when :delete_application
          delete_application event[:app_name], event[:namespace]
        when :add_gear
          add_gear event[:app_name], event[:namespace], event[:public_address], event[:public_port]
        when :delete_gear
          remove_gear event[:app_name], event[:namespace], event[:public_address], event[:public_port]
        end
      rescue => e
        $stderr.puts "Got an exception: #{e.message}"
        $stderr.puts "Backtrace: #{e.backtrace}"
      end
    end

    def update
      @last_update = Time.now
      begin
        @lb_controller.update
      rescue => e
        $stderr.puts "Got an exception: #{e.message}"
        $stderr.puts "Backtrace: #{e.backtrace}"
      end
    end

    def generate_pool_name app_name, namespace
      "ose-#{app_name}-#{namespace}-80"
    end

    def generate_route_name app_name, namespace
      "ose-#{app_name}-#{namespace}"
    end

    def generate_monitor_name app_name, namespace
      return nil unless @monitor_name_format

      @monitor_name_format.gsub /%./, '%a' => app_name, '%n' => namespace
    end

    def generate_monitor_path app_name, namespace
      return nil unless @monitor_path_format

      @monitor_path_format.gsub /%./, '%a' => app_name, '%n' => namespace
    end

    def create_application app_name, namespace
      pool_name = generate_pool_name app_name, namespace

      raise StandardError.new "Creating application #{app_name} for which a pool already exists" if @lb_controller.pools.include? pool_name

      monitor_name = generate_monitor_name app_name, namespace
      if @lb_controller.monitors.include? monitor_name
        $stderr.print "Using existing monitor: #{monitor_name}"
      else
        monitor_path = generate_monitor_path app_name, namespace
        $stderr.print "Creating new monitor #{monitor_name} with path #{monitor_path}\n"
        @lb_controller.create_monitor monitor_name, monitor_path, '1'
      end

      $stderr.print "Creating new pool: #{pool_name}\n"
      @lb_controller.create_pool pool_name, monitor_name

      route_name = generate_route_name app_name, namespace
      route = '/' + app_name
      $stderr.print "Creating new routing rule #{route_name} for route #{route} to pool #{pool_name}\n"
      @lb_controller.create_route pool_name, route_name, route
    end

    def delete_application app_name, namespace
      pool_name = generate_pool_name app_name, namespace

      raise StandardError.new "Deleting application #{app_name} for which no pool exists" unless @lb_controller.pools.include? pool_name

      route_name = generate_route_name app_name, namespace
      $stderr.print "Deleting routing rule: #{route_name}\n"
      @lb_controller.delete_route pool_name, route_name

      $stderr.print "Deleting empty pool: #{pool_name}\n"
      @lb_controller.delete_pool pool_name
    end

    def add_gear app_name, namespace, gear_host, gear_port
      pool_name = generate_pool_name app_name, namespace
      $stderr.print "Adding new member #{gear_host}:#{gear_port} to pool #{pool_name}\n"
      @lb_controller.pools[pool_name].add_member gear_host, gear_port.to_i
    end

    def remove_gear app_name, namespace, gear_host, gear_port
      pool_name = generate_pool_name app_name, namespace
      $stderr.print "Deleting member #{gear_host}:#{gear_port} from pool #{pool_name}\n"
      @lb_controller.pools[pool_name].delete_member gear_host, gear_port.to_i
    end

  end

end
