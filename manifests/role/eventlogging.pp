# == Class: role::eventlogging
#
# This role configures an instance to act as the primary EventLogging
# log processor for the cluster. The setup is described in detail on
# <https://wikitech.wikimedia.org/wiki/EventLogging>. End-user
# documentation is available in the form of a guide, located at
# <https://www.mediawiki.org/wiki/Extension:EventLogging/Guide>.
#
# There exist two APIs for generating events: efLogServerSideEvent() in
# PHP and mw.eventLog.logEvent() in JavaScript. Events generated in PHP
# are sent by the app servers directly to vanadium on UDP port 8421.
# JavaScript-generated events are URL-encoded and sent to our servers by
# means of an HTTP/S request to bits, which a varnishncsa instance
# forwards to vanadium on port 8422. These event streams are parsed,
# validated, and multiplexed into an output stream that is published via
# ZeroMQ on TCP port 8600. Data sinks are implemented as subscribers
# that connect to this endpoint and read data into some storage medium.
#
class role::eventlogging {
    include eventlogging
    include eventlogging::monitor

    system_role { 'role::eventlogging':
        description => 'EventLogging',
    }

    # Event data flows through several processes that communicate with each
    # other via TCP/IP sockets. At the moment, all processing is performed
    # locally, but the work could be easily distributed across multiple hosts.
    $processor = '127.0.0.1'


    ## Data flow

    # Server-side events are generated by MediaWiki and sent to vanadium
    # on UDP port 8421, using wfErrorLog('...', 'udp://...'). vanadium
    # is specified as the destination in $wgEventLoggingFile, declared
    # in wmf-config/CommonSettings.php.

    eventlogging::service::forwarder { '8421':
        ensure => present,
        count  => true,
    }

    eventlogging::service::processor { 'server-side events':
        format => '%n EventLogging %j',
        input  => "tcp://${processor}:8421",
        output => 'tcp://*:8521',
    }

    # Client-side events are generated by JavaScript-triggered HTTP/S
    # requests to //bits.wikimedia.org/event.gif?<event payload>.
    # A varnishncsa instance on the bits caches greps for these requests
    # and forwards them to vanadium on UDP port 8422. The varnishncsa
    # configuration is specified in <manifests/role/cache.pp>.

    eventlogging::service::forwarder { '8422':
        ensure => present,
    }

    eventlogging::service::processor { 'client-side events':
        format => '%q %l %n %t %h',
        input  => "tcp://${processor}:8422",
        output => 'tcp://*:8522',
    }

    # Parsed and validated client-side (Varnish-generated) and
    # server-side (MediaWiki-generated) events are multiplexed into a
    # single output stream, published on TCP port 8600.

    eventlogging::service::multiplexer { 'all events':
        inputs => [ "tcp://${processor}:8521", "tcp://${processor}:8522" ],
        output => 'tcp://*:8600',
    }


    ## MongoDB

    # Log events to a local MongoDB instance.

    include passwords::mongodb::eventlogging  # RT 5101
    $mongo_user = $passwords::mongodb::eventlogging::user
    $mongo_pass = $passwords::mongodb::eventlogging::password
    $mongo_host = $::realm ? {
        production => '127.0.0.1',
        labs       => '127.0.0.1',
    }

    if $mongo_host == '127.0.0.1' {
        class { 'mongodb':
            dbpath   => '/a/mongodb',
            settings => {
                auth => true,
            },
        }
    }

    eventlogging::service::consumer { 'vanadium':
        input  => "tcp://${processor}:8600",
        output => "mongodb://${mongo_user}:${mongo_pass}@${mongo_host}:27017",
    }


    ## MySQL / MariaDB

    # Log strictly valid events to the 'log' database on db1047. This is the
    # primary medium for data analysis as of July 2013.

    include passwords::mysql::eventlogging    # RT 4752
    $mysql_user = $passwords::mysql::eventlogging::user
    $mysql_pass = $passwords::mysql::eventlogging::password
    $mysql_db = $::realm ? {
        production => 'db1047.eqiad.wmnet/log',
        labs       => '127.0.0.1/log',
    }

    eventlogging::service::consumer { 'mysql-db1047':
        input  => "tcp://${processor}:8600",
        output => "mysql://${mysql_user}:${mysql_pass}@${mysql_db}?charset=utf8",
    }


    ## Flat files

    # Log all raw log records and decoded events to flat files in
    # /var/log/eventlogging as a medium of last resort. These files
    # are rotated and rsynced to stat1 & stat1002 for backup.

    eventlogging::service::consumer {
        'server-side-events.log':
            input  => "tcp://${processor}:8421?raw=1",
            output => 'file:///var/log/eventlogging/server-side-events.log';
        'client-side-events.log':
            input  => "tcp://${processor}:8422?raw=1",
            output => 'file:///var/log/eventlogging/client-side-events.log';
        'all-events.log':
            input  => "tcp://${processor}:8600",
            output => 'file:///var/log/eventlogging/all-events.log';
    }

    $backup_destinations = $::realm ? {
        production => [ 'stat1.wikimedia.org', 'stat1002.eqiad.wmnet' ],
        labs       => false,
    }

    if ( $backup_destinations ) {
        include rsync::server

        rsync::server::module { 'eventlogging':
            path        => '/var/log/eventlogging',
            read_only   => 'yes',
            list        => 'yes',
            require     => File['/var/log/eventlogging'],
            hosts_allow => $backup_destinations,
        }
    }


    ## Monitoring

    nrpe::monitor_service { 'eventlogging':
        ensure        => 'present',
        description   => 'Check status of defined EventLogging jobs',
        nrpe_command  => '/usr/lib/nagios/plugins/check_eventlogging_jobs',
        require       => File['/usr/lib/nagios/plugins/check_eventlogging_jobs'],
        contact_group => 'admins,analytics',
    }
}


# == Class: role::eventlogging::graphite
#
# Keeps a running count of incoming events by schema in Graphite by
# emitting 'eventlogging.SCHEMA_REVISION:1' on each event to a StatsD
# instance.
#
class role::eventlogging::graphite {
    include ::eventlogging

    eventlogging::service::consumer { 'graphite':
        input  => 'tcp://vanadium.eqiad.wmnet:8600',
        output => 'statsd://127.0.0.1:8125',
    }
}
