module Wordpress

  # Define options for this plugin via the <tt>configure</tt> method
  # in your application manifest:
  #
  #   configure(:wordpress => {:foo => true})
  #
  # Then include the plugin and call the recipe(s) you need:
  #
  #  plugin :wordpress
  #  recipe :wordpress
  def wordpress(hash = {})
    options = {
      :domain => `hostname`,
      :apache => {
        :htpasswd => '/srv/wordpress/htpasswd'
      }.merge!( hash.delete(:apache) || {}),
      :db => {
        :name       => 'wordpress',
        :username   => 'wordpress',
        :password   => "t1me_2_bl@hg"
      }.merge!( hash.delete(:db) || {})
    }.merge! hash

    %w(wget libapache2-mod-fcgid).each{|p| package p, :ensure => :installed}
    %w(php5 php5-mysql php5-gd php5-cgi php5-cli).each{|p| package p, :ensure => :installed, :require => package('libapache2-mod-fcgid')}

    exec 'wordpress_db',
      :command => "mysqladmin create #{options[:db][:name]}",
      :unless => "mysqlshow #{options[:db][:name]}",
      :require => service('mysql')

    grant =<<-GRANT
GRANT ALL PRIVILEGES 
ON #{options[:db][:name]}.* 
TO #{options[:db][:username]}@localhost 
IDENTIFIED BY '#{options[:db][:password]}';
FLUSH PRIVILEGES;
    GRANT
    exec 'wordpress_db_permissions',
      :command => "mysql -e \"#{grant}\"",
      :unless  => "mysqlshow -u#{options[:db][:username]} -p#{options[:db][:password]} #{options[:db][:name]}",
      :require => exec('wordpress_db')

    exec 'install_wordpress',
      :command  => [
        'wget http://wordpress.org/latest.tar.gz',
        'tar xzf latest.tar.gz -C /srv'
      ].join(' && '),
      :cwd     => '/tmp',
      :require => package('wget'),
      :creates => '/srv/wordpress'

    file '/srv/wordpress/wp-config.php',
      :content => template(File.join(File.dirname(__FILE__), '..', 'templates', 'wp-config.php'), binding),
      :require => exec('install_wordpress'),
      :notify  => service('apache2')

    file "/etc/apache2/sites-available/#{options[:domain]}",
      :content => template(File.join(File.dirname(__FILE__), '..', 'templates', 'vhost'), binding),
      :require => package('apache2-mpm-worker'),
      :notify  => service('apache2')

    if options[:apache] && options[:apache][:users]
      htpasswd = options[:apache][:htpasswd]

      file htpasswd, :ensure => :file, :mode => '644'

      options[:apache][:users].each do |user,pass|
        exec "sudo htpasswd #{user}",
          :require => file(htpasswd),
          :command => "htpasswd -b #{htpasswd} #{user} #{pass}",
          :unless  => "grep '#{user}' #{htpasswd}"
      end
    end

    a2ensite options[:domain], :require => file("/etc/apache2/sites-available/#{options[:domain]}")
    a2enmod 'fcgid'
  end

end
