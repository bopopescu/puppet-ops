# Configuration files for php5 running on application servers
#
# **fatal_log_file**
# Where to send PHP fatal traces.
#
# requires mediawiki::packages to be in place
class mediawiki::php(
    $fatal_log_file='udp://10.64.0.21:8420'
) {
    include ::mediawiki::packages

    file { '/etc/php5/apache2/php.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php5-common'],
        source  => 'puppet:///modules/mediawiki/php/php.ini',
    }

    file { '/etc/php5/cli/php.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php5-cli'],
        source  => 'puppet:///modules/mediawiki/php/php.ini.cli',
    }

    file { '/etc/php5/conf.d/fss.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php5-fss'],
        source  => 'puppet:///modules/mediawiki/php/fss.ini',
    }

    file { '/etc/php5/conf.d/apc.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php-apc'],
        source  => 'puppet:///modules/mediawiki/php/apc.ini',
    }

    file { '/etc/php5/conf.d/wmerrors.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php5-wmerrors'],
        content => template('mediawiki/php/wmerrors.ini.erb'),
    }

    file { '/etc/php5/conf.d/igbinary.ini':
        ensure => absent,
    }

    file { '/etc/php5/conf.d/mail.ini':
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        require => Package['php-mail'],
        source => 'puppet:///modules/mediawiki/php/mail.ini',
    }
}
