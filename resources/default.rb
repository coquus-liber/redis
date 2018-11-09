# To learn more about Custom Resources, see https://docs.chef.io/custom_resources.html

property :release, String, default: 'stable'
property :port, Integer, default: 6379
property :stable_path, String, default: 'redis-stable.tar.gz'
property :release_path, String, default: lazy { |r| "releases/redis-#{r.release}.tar.gz" }
property :is_stable, [true,false], default: lazy { |r| r.release == 'stable' }
property :src_path, String, default: lazy { |r| r.is_stable ? r.stable_path : r.release_path }
property :src_host, String, default: "http://download.redis.io/"
property :src, String, default: lazy { |r| r.src_host + r.src_path }
property :install_dir, String, default: '/opt/redis'
property :etc_dir, String, default: '/etc/redis'
property :var_dir, String, default: '/var/redis'
property :tar_file, String, default: 'redis.tar.gz'
property :tar_path, String, default: lazy { |r| ::File.join(r.install_dir, r.tar_file) }
property :src_dir, String, default: lazy { |r| ::File.join(r.install_dir, 'src') }
property :util_dir, String, default: lazy { |r| ::File.join(r.install_dir, 'utils') }
property :srv_bin, String, default: lazy { |r| ::File.join(r.src_dir, 'redis-server') }
property :init_src, String, default: lazy { |r| ::File.join(r.util_dir, 'redis_init_script') }
property :init_path, String, default: lazy { |r| "/etc/init.d/redis_#{r.port}" }
property :conf_src, String, default: lazy { |r| ::File.join(r.install_dir, 'redis.conf') }
property :conf_path, String, default: lazy { |r| ::File.join(r.etc_dir,"#{r.port}.conf") }
property :pid_file, String, default: lazy { |r| "/var/run/redis_#{r.port}.pid" }

# load the current state of the node from the system
load_current_value do 
end

# define methods that are available in the actions
action_class do
  def init_script init_src, port
    content = ::File.read(init_src)
    content.gsub!(/^# Default-(\w*):(.*)$/) do |m|
      b = m.sub('Default','Required').sub(/:.*$/,':')
      "#{m}\n#{b}"
    end
    content.gsub!(/\sredis_\d+/," redis_#{port}")
    content.gsub!(/^REDISPORT=\d+/,"REDISPORT=#{port}")
    content
  end
  def conf_file conf_src, port
    content = ::File.read(conf_src)
    content.gsub!(/^daemonize (?:yes|no)/, "daemonize yes")
    content.gsub!(/^pidfile\s.*$/,"pidfile /var/run/redis_#{port}.pid")
    content.gsub!(/^port \d+/,"port #{port}")
    content.gsub!(/^loglevel \w+$/, "loglevel notice")
    content.gsub!(/^logfile .*$/, "logfile /var/log/redis_#{port}.log")
    content.gsub!(/^dir .*$/, "dir /var/redis/#{port}")
  end
end 

action :install do
  directory new_resource.install_dir do
    recursive true
  end

  directory new_resource.etc_dir
  directory new_resource.var_dir
  directory ::File.join(new_resource.var_dir, new_resource.port.to_s)

  # a mix of built-in Chef resources and Ruby
  remote_file new_resource.tar_path do
    source new_resource.src 
  end

  bash 'make redis' do
    cwd new_resource.install_dir
    creates new_resource.srv_bin
    code <<~BASH
      tar --strip-components=1 -xzf #{new_resource.tar_file}
      make install
    BASH
  end

  file new_resource.init_path do
    content( lazy {init_script(new_resource.init_src, new_resource.port) })
    mode 0755
    sensitive true
  end

  file new_resource.conf_path do
    content( lazy { conf_file(new_resource.conf_src, new_resource.port)})
    sensitive true
  end

  execute 'update init rc' do
    command "update-rc.d redis_#{new_resource.port} defaults"
    creates "/etc/rc5.d/S01redis_#{new_resource.port}"
  end

  execute 'start redis' do
    command "#{new_resource.init_path} start"
    creates new_resource.pid_file
  end
end

