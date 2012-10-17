#!/usr/bin/env rackup

app_path = ::File.expand_path(::File.dirname(__FILE__))
$: << ::File.join(app_path, 'lib')

# We want to read all text data as UTF-8
Encoding.default_external = Encoding::UTF_8

require 'fileutils'
require 'rack/olelo_patches'
require 'rack/relative_redirect'
require 'rack/static_cache'
require 'olelo'
require 'olelo/middleware/degrade_mime_type'
require 'olelo/middleware/flash'
require 'olelo/middleware/force_encoding'
require 'securerandom'

Olelo::Config.instance['app_path'] = app_path
Olelo::Config.instance['config_path'] = ::File.join(app_path, 'config')
Olelo::Config.instance['initializers_path'] = ::File.join(app_path, 'config', 'initializers')
Olelo::Config.instance['plugins_path'] = ::File.join(app_path, 'plugins')
Olelo::Config.instance['views_path'] = ::File.join(app_path, 'views')
Olelo::Config.instance['themes_path'] = ::File.join(app_path, 'static', 'themes')
Olelo::Config.instance['rack.session_secret'] = SecureRandom.hex
Olelo::Config.instance.load!(::File.join(app_path, 'config', 'config.yml.default'))

if Dir.pwd == app_path
  puts "Serving from Olelo application directory #{app_path}"
  data_path = File.join(app_path, '.wiki')
  Olelo::Config.instance['repository.git'] = { :path => ::File.join(data_path, 'repository'), :bare => false }
  Olelo::Config.instance['cache_store'] = { :type => 'file', 'file.root' => ::File.join(data_path, 'cache') }
  Olelo::Config.instance['authentication.yamlfile.store'] = ::File.join(data_path, 'users.yml')
  Olelo::Config.instance['log.file'] = ::File.join(data_path, 'log')
elsif File.directory?(::File.join(Dir.pwd, '.git'))
  puts "Serving out of repository #{Dir.pwd}"
  data_path = File.join(Dir.pwd, '.wiki')
  Olelo::Config.instance['repository.git'] = { :path => Dir.pwd, :bare => false }
  Olelo::Config.instance['cache_store'] = { :type => 'file', 'file.root' => ::File.join(data_path, 'cache') }
  Olelo::Config.instance['authentication.yamlfile.store'] = ::File.join(data_path, 'users.yml')
  Olelo::Config.instance['log.file'] = ::File.join(data_path, 'log')
else
  puts 'No default data storage location defined, please create your own configuration!'
end

Olelo::Config.instance.load(ENV['OLELO_CONFIG'] || ENV['WIKI_CONFIG'] || ::File.join(app_path, 'config', 'config.yml'))
Olelo::Config.instance.freeze

FileUtils.mkpath ::File.dirname(Olelo::Config['log.file'])
logger = ::Logger.new(Olelo::Config['log.file'], :monthly, 10240000)
logger.level = ::Logger.const_get(Olelo::Config['log.level'])

use_lint if !Olelo::Config['production']

use Rack::Runtime
use Rack::ShowExceptions if !Olelo::Config['production']

if Olelo::Config['rack.deflater']
  use Rack::Deflater
end

use Rack::StaticCache, :urls => ['/static'], :root => app_path
use Rack::Session::Cookie, :key => 'olelo.session', :secret => Olelo::Config['rack.session_secret']
use Olelo::Middleware::DegradeMimeType

class LoggerOutput
  def initialize(logger); @logger = logger; end
  def write(text); @logger << text; end
end

use Rack::MethodOverride
use Rack::CommonLogger, LoggerOutput.new(logger)

if !Olelo::Config['rack.blacklist'].empty?
  require 'olelo/middleware/blacklist'
  use Olelo::Middleware::Blacklist, :blacklist => Olelo::Config['rack.blacklist']
end

use Olelo::Middleware::ForceEncoding
use Olelo::Middleware::Flash, :set_accessors => %w(error warn info)
use Rack::RelativeRedirect

Olelo::Initializer.initialize(logger)
run Olelo::Application.new

logger.info "Olelo started in #{Olelo::Config['production'] ? 'production' : 'development'} mode"
