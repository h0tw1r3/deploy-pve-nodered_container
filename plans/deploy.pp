# Deploy Nodered Container
plan nodered_container::deploy (
  TargetSpec $targets
) {
  $terraform_result = run_task(
    'terraform::apply',
    'localhost',
    dir => './terraform'
  )

  apply_prep($targets)

  $apply_result = apply($targets, _catch_errors => true, _run_as => root) {
    $node_red_settings = {
        'uiPort'        => 80,
        'httpAdminRoot' => '/nodered-admin/',
        'httpNodeRoot'  => '/nodered/',
        'editorTheme'   => {
          'tours' => false,
        },
        'codeEditor'    => {
          'lib' => 'monaco',
        }
    }

    $node_red_addons = {
      'js-yaml'                                   => '4.1.0',
      'full-icu'                                  => '1.4.0',
      'node-red-contrib-bigtimer'                 => '2.8.1',
      'node-red-contrib-cast'                     => '0.2.17',
      'node-red-contrib-counter'                  => '0.1.6',
      'node-red-contrib-dlna'                     => '0.2.2',
      'node-red-contrib-home-assistant-websocket' => '0.43.1',
      'node-red-contrib-hubitat'                  => '1.8.0',
      'node-red-contrib-image-tools'              => '2.0.4',
      'node-red-contrib-influxdb'                 => '0.6.1',
      'node-red-contrib-interval-length'          => '0.0.5',
      'node-red-contrib-looptimer'                => '0.0.8',
      'node-red-contrib-modbus'                   => '5.21.2',
      'node-red-contrib-moment'                   => '4.0.0',
      'node-red-contrib-persistent-fsm'           => '1.1.0',
      'node-red-contrib-play-audio'               => '2.5.0',
      'node-red-contrib-scrape-it'                => '1.0.3',
      'node-red-contrib-statistics'               => '2.2.2',
      'node-red-contrib-stoptimer'                => '0.0.7',
      'node-red-contrib-sunevents'                => '3.0.3',
      'node-red-contrib-time-range-switch'        => '1.1.3',
      'node-red-contrib-timecheck'                => '1.1.0',
      'node-red-contrib-traffic'                  => '0.2.1',
      'node-red-contrib-ui-thermostat'            => '1.0.0',
      'node-red-dashboard'                        => '3.1.6',
      'node-red-node-base64'                      => '0.3.0',
      'node-red-node-email'                       => '1.15.0',
      'node-red-node-feedparser'                  => '0.2.2',
      'node-red-node-geofence'                    => '0.3.1',
      'node-red-node-msgpack'                     => '1.2.1',
      'node-red-node-pi-gpio'                     => '2.0.2',
      'node-red-node-ping'                        => '0.3.1',
      'node-red-node-random'                      => '0.4.0',
      'node-red-node-sentiment'                   => '0.1.6',
      'node-red-node-serialport'                  => '1.0.1',
      'node-red-node-smooth'                      => '0.1.2',
      'node-red-node-suncalc'                     => '1.0.1',
      'node-red-node-twitter'                     => '1.2.0',
      'node-red-node-ui-table'                    => '0.3.12',
      'line-by-line'                              => '0.1.6',
      'source-map-support'                        => '0.5.21',
    }

    $unneeded_packages = [
      'ubuntu-standard',
      'usbutils',
      'bind9-libs',
      'cpp', 'cpp-9',
      'dmidecode',
      'dosfstools',
      'irqbalance',
      'libdrm-common',
      'libllvm12', 'libxcb-shm0', 'libxcb-xfixes0',
      'libice6', 'libmaxminddb0',
      'xinit',
      'xauth',
      'x11-common',
      'libx11-data',
      'libx11-xcb1',
      'ntfs-3g',
      'libxcb1', 'libxshmfence1',
      'libxau6',
    ]

    package { $unneeded_packages:
      ensure => absent
    }
    -> class { 'unattended_upgrades':
      auto                   => {
        reboot => true,
        clean  => 7,
        remove => true,
      },
      extra_origins          => [
        '${distro_id}:${distro_codename}-updates',
      ],
      remove_new_unused_deps => true,
      syslog_enable          => true,
      days                   => ["0", "1", "2", "3", "4", "5", "6"],
    }
    -> file { '/etc/rsyslog.d/listen.conf':
      ensure  => present,
      notify  => Exec['restart-rsyslog'],
      content => @(EOD)
        module(load="imudp")
        input(type="imudp" port="514")
        module(load="imtcp")
        input(type="imtcp" port="514")
        | EOD
    }

    exec { 'restart-rsyslog':
      command     => '/usr/bin/env systemctl restart rsyslog',
      refreshonly => true,
    }

    $key_path = "/usr/share/keyrings"

    $repos = {
      'yarnkey'    => {
        'key_url' => "https://dl.yarnpkg.com/debian/pubkey.gpg",
        'url'     => "https://dl.yarnpkg.com/debian",
        'distro'  => "stable",
      }
    }

    $repos.each |$name, $repo| {
      file { "${key_path}/${name}.armor.gpg":
        ensure => present,
        source => $repo['key_url'],
      }
      ~> exec { "dearmor-gpgkey-${name}":
        command     => "/usr/bin/env gpg --dearmor < ${key_path}/${name}.armor.gpg > ${key_path}/${name}.gpg",
        refreshonly => true,
        notify      => Exec['apt-update'],
      }
      -> file { "/etc/apt/sources.list.d/${name}.list":
        ensure  => present,
        notify  => Exec['apt-update'],
        content => @("EOD")
          # Managed by Puppet
          deb [signed-by=${key_path}/${name}.gpg] ${repo['url']} ${repo['distro']} main
          | EOD
      }
    }

    exec { 'apt-update':
      command     => '/usr/bin/env apt-get -d update',
      refreshonly => true,
    }

    class { 'nodejs':
      repo_url_suffix => "16.x",
    }
    -> package { 'yarn': }
    -> file { '/opt/node-red':
      ensure => directory,
    }
    -> package { 'node-red':
      ensure          => present,
      install_options => ['--unsafe-perm'],
      provider        => 'npm',
    }

    $node_red_addons.each |$package, $ensure| {
      package { $package:
        ensure   => $ensure,
        provider => 'npm',
        require  => Package['node-red'],
        notify   => Service['node-red'],
      }
    }

    file { 'node-red.service':
      path    => '/etc/systemd/system/node-red.service',
      content => @(EOD)
        # Managed by Puppet
        [Unit]
        Description=Browser based flow programming tool.
        After=syslog.target network.target
        Documentation=http://nodered.org/
        
        [Service]
        ExecStart=/usr/bin/env node --max-old-space-size=128 /usr/lib/node_modules/node-red/red.js -v -D @./custom-settings.js
        WorkingDirectory=/home/nodered/.node-red
        User=nodered
        Nice=10
        StandardOutput=syslog
        Restart=on-failure
        KillSignal=SIGINT
        AmbientCapabilities=CAP_NET_BIND_SERVICE
        
        [Install]
        WantedBy=multi-user.target
        | EOD
    }
    ~> exec { 'systemd-daemon-reload':
			command => '/usr/bin/env systemctl daemon-reload',
      notify  => Service['node-red'],
    }

    user { 'nodered':
      ensure     => present,
      managehome => true,
      shell      => '/bin/bash',
    }
    -> file { '/home/nodered/.node-red':
      ensure => directory,
      owner  => 'nodered',
      group  => 'nodered',
    }
    -> file { '/home/nodered/.node-red/custom-settings.js':
      notify  => Service['node-red'],
      owner   => 'nodered',
      group   => 'nodered',
      content => $node_red_settings.to_json_pretty
    }
    -> nodejs::npm { 'node-red-contrib-theme-collection':
      ensure           => '2.2.0',
      package          => '@node-red-contrib-themes/theme-collection',
      target           => '/home/nodered/.node-red',
      user             => 'nodered',
      home_dir         => '/home/nodered',
    }
    ~> service { 'node-red':
      ensure  => running,
      enable  => true,
      require => File['node-red.service'],
    }
  }
  return $apply_result
}
