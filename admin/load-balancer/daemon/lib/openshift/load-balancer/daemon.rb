require 'rubygems'
require 'logger'
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
    def read_config
      cfg = ParseConfig.new('/etc/openshift/load-balancer.conf')

      @user = cfg['ACTIVEMQ_USER'] || 'routinginfo'
      @password = cfg['ACTIVEMQ_PASSWORD'] || 'routinginfopasswd'
      @host = cfg['ACTIVEMQ_HOST'] || 'activemq.example.com'
      @port = (cfg['ACTIVEMQ_PORT'] || 61613).to_i
      @destination = cfg['ACTIVEMQ_TOPIC'] || '/topic/routinginfo'
      @pool_name_format = cfg['POOL_NAME'] || 'pool_ose_%a_%n_80'
      @route_name_format = cfg['ROUTE_NAME'] || 'irule_ose_%a_%n'
      @monitor_name_format = cfg['MONITOR_NAME']
      @monitor_path_format = cfg['MONITOR_PATH']
      @monitor_up_code = cfg['MONITOR_UP_CODE'] || '1'
      @monitor_type = cfg['MONITOR_TYPE'] || 'http-ecv'
      @monitor_interval = cfg['MONITOR_INTERVAL'] || '10'
      @monitor_timeout = cfg['MONITOR_TIMEOUT'] || '5'

      @update_interval = (cfg['UPDATE_INTERVAL'] || 5).to_i

      @logfile = cfg['LOGFILE'] || '/var/log/openshift/load-balancer-daemon.log'
      @loglevel = cfg['LOGLEVEL'] || 'debug'

      # @lb_model and instances thereof should not be used except to
      # pass an instance of @lb_model_class to an instance of
      # @lb_controller_class.
      case cfg['LOAD_BALANCER'].downcase
      when 'f5'
        require 'openshift/load-balancer/controllers/f5'
        require 'openshift/load-balancer/models/f5'

        @lb_model_class = OpenShift::F5LoadBalancerModel
        @lb_controller_class = OpenShift::F5LoadBalancerController
      when 'lbaas'
        require 'openshift/load-balancer/models/lbaas'
        require 'openshift/load-balancer/controllers/lbaas'

        @lb_model_class = OpenShift::LBaaSLoadBalancerModel
        @lb_controller_class = OpenShift::AsyncLoadBalancerController
      when 'dummy'
        require 'openshift/load-balancer/models/dummy'
        require 'openshift/load-balancer/controllers/f5'

        @lb_model_class = OpenShift::DummyLoadBalancerModel
        @lb_controller_class = OpenShift::F5LoadBalancerController
      when 'dummy_async'
        require 'openshift/load-balancer/models/dummy'
        require 'openshift/load-balancer/controllers/lbaas'

        @lb_model_class = OpenShift::DummyLoadBalancerModel
        @lb_controller_class = OpenShift::AsyncLoadBalancerController
      else
        raise StandardError.new 'No load-balancer configured.'
      end
    end

    def initialize
      read_config

      @logger = Logger.new @logfile
      @logger.level = case @loglevel
                      when 'debug'
                        Logger::DEBUG
                      when 'info'
                        Logger::INFO
                      when 'warn'
                        Logger::WARN
                      when 'error'
                        Logger::ERROR
                      when 'fatal'
                        Logger::FATAL
                      else
                        raise StandardError.new "Invalid LOGLEVEL value: #{@loglevel}"
                      end

      @logger.info "Initializing load-balancer controller..."
      @lb_controller = @lb_controller_class.new @lb_model_class, @logger
      @logger.info "Found #{@lb_controller.pools.length} pools:\n" +
                   @lb_controller.pools.map{|k,v|"  #{k} (#{v.members.length} members)"}.join("\n")

      @logger.info "Connecting to #{@host}:#{@port} as user #{@user}..."
      @aq = Stomp::Connection.open @user, @password, @host, @port, true

      @logger.info "Subscribing to #{@destination}..."
      @aq.subscribe @destination, { :ack => 'client' }

      @last_update = Time.now
    end

    def listen
      @logger.info "Listening..."
      while true
        begin
          msg = nil
          Timeout::timeout(@update_interval) { msg = @aq.receive }
          @logger.debug ['Received message:', '#v+', msg.body, '#v-'].join "\n"
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
        @logger.warn "Got an exception: #{e.message}"
        @logger.debug "Backtrace:\n#{e.backtrace.join "\n"}"
      end
    end

    def update
      @last_update = Time.now
      begin
        @lb_controller.update
      rescue => e
        @logger.warn "Got an exception: #{e.message}"
        @logger.debug "Backtrace:\n#{e.backtrace.join "\n"}"
      end
    end

    def generate_pool_name app_name, namespace
      @pool_name_format.gsub /%./, '%a' => app_name, '%n' => namespace
    end

    def generate_route_name app_name, namespace
      @route_name_format.gsub /%./, '%a' => app_name, '%n' => namespace
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
        @logger.info "Using existing monitor: #{monitor_name}"
      else
        monitor_path = generate_monitor_path app_name, namespace
        unless monitor_name.nil? or monitor_name.empty? or monitor_path.nil? or monitor_path.empty?
          @logger.info "Creating new monitor #{monitor_name} with path #{monitor_path}"
          @lb_controller.create_monitor monitor_name, monitor_path, @monitor_up_code, @monitor_type, @monitor_interval, @monitor_timeout
        end
      end

      @logger.info "Creating new pool: #{pool_name}"
      @lb_controller.create_pool pool_name, monitor_name

      route_name = generate_route_name app_name, namespace
      route = '/' + app_name
      @logger.info "Creating new routing rule #{route_name} for route #{route} to pool #{pool_name}"
      @lb_controller.create_route pool_name, route_name, route
    end

    def delete_application app_name, namespace
      pool_name = generate_pool_name app_name, namespace

      raise StandardError.new "Deleting application #{app_name} for which no pool exists" unless @lb_controller.pools.include? pool_name

      begin
        route_name = generate_route_name app_name, namespace
        @logger.info "Deleting routing rule: #{route_name}"
        @lb_controller.delete_route pool_name, route_name
      ensure
        @logger.info "Deleting empty pool: #{pool_name}"
        @lb_controller.delete_pool pool_name

        monitor_name = generate_monitor_name app_name, namespace
        # Check that the monitor exists and is specific to the
        # application (as indicated by having the application's name and
        # namespace in the monitor's name).
        if @lb_controller.monitors.include?(monitor_name) && @monitor_name_format.match(/%a/) && @monitor_name_format.match(/%n/)
          @logger.info "Deleting unused monitor: #{monitor_name}"
          @lb_controller.delete_monitor monitor_name
        end
      end
    end

    def add_gear app_name, namespace, gear_host, gear_port
      pool_name = generate_pool_name app_name, namespace
      @logger.info "Adding new member #{gear_host}:#{gear_port} to pool #{pool_name}"
      @lb_controller.pools[pool_name].add_member gear_host, gear_port.to_i
    end

    def remove_gear app_name, namespace, gear_host, gear_port
      pool_name = generate_pool_name app_name, namespace
      @logger.info "Deleting member #{gear_host}:#{gear_port} from pool #{pool_name}"
      @lb_controller.pools[pool_name].delete_member gear_host, gear_port.to_i
    end

  end

end
