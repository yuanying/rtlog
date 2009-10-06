require 'rtlog'
require 'erb'
require 'fileutils'

module Rtlog

class Page
  include ERB::Util
  
  attr_reader :config
  attr_reader :log
  attr_writer :logger
  
  def initialize config, log
    @config = config
    @log    = log
  end
  
  def logger
    defined?(@logger) ? @logger : Rtlog.logger
  end
  
  def config_dir
    File.expand_path( config['config_dir'] )
  end
  
  def parse file_name
    logger.debug("Template parsing: #{file_name}")
    open(file_name) { |io| ERB.new( io.read ) }.result(binding)
  rescue => ex
    "<p>#{h(ex.to_s)}</p><pre class='error'>#{ex.backtrace.map{|m| h(m) }.join('<br />')}</pre>"
  end
  
  def generate options={}
    options = { :layout => 'layout.html.erb' }.merge(options)
    
    template = File.join( config_dir, options[:layout] ) if options[:layout]
    template = template_path unless template
    FileUtils.mkdir_p( File.dirname(file_path) ) unless File.exist?( File.dirname(file_path) )
    open(file_path, "w") do |io|  
      io.write(parse(template))
    end
    logger.debug("#{self.class} is generated: #{file_path}")
  end
  
  def size
    config['pages'][page_name]['size'] || 7
  end
  
  def template_path
    @template_path ||= ::File.join(config_dir, config['pages'][page_name]['template'])
    @template_path
  end
  
  def month_pages
    @month_pages = []
    log.year_entries.each do |y|
      y.month_entries.each do |m|
        @month_pages << MonthPage.new(config, log, m)
      end
    end
    @month_pages
  end
  
  def index_url
    config['url_prefix']
  end
end

class IndexPage < Page
  
  def title
    'Index'
  end
  
  def file_path
    File.expand_path( File.join(config['target_dir'], 'index.html') )
  end
  
  def url
    config['url_prefix']
  end
  
  def page_name
    'index'
  end
  
  def recent_day_pages size
    recent_day_pages = []
    log.recent_day_entries(size).each do |d|
      recent_day_pages << DayPage.new( config, log, d )
    end
    recent_day_pages
  end
end

class RssPage < IndexPage
  def url
    config['url_prefix'] + '/feed/rss'
  end
  
  def file_path
    File.expand_path( File.join(config['target_dir'], 'feed', 'rss.xml') )
  end
  
  def page_name
    'rss'
  end
  
  def generate
    super(:layout => nil)
  end
end

class MonthPage < Page
  attr_reader :month_entry
  attr_accessor :current_page
  
  def initialize config, log, month_entry
    @config       = config
    @log          = log
    @month_entry  = month_entry
    @current_page = 1
  end
  
  def title
    date.strftime('%Y-%m')
  end
  
  def date
    @month_entry.date
  end
  
  def current_day_pages
    current_day_pages = []
    month_entry.day_entries[(current_page - 1) * per_page, per_page].each do |d|
      current_day_pages << DayPage.new( config, log, d )
    end
    current_day_pages
  end
  
  def per_page
    size
  end
  
  def total_entries
    @total_entries ||= month_entry.day_entries.size
    @total_entries
  end
  
  def total_tweets
    month_entry.size
  end
  
  def total_pages
    (Float.induced_from(total_entries)/Float.induced_from(per_page)).ceil
  end
  
  def previous
    return false if current_page == 1
    previous_page = self.clone
    previous_page.current_page -= 1
    previous_page
  end
  
  def next
    return false if current_page == total_pages
    next_page = self.clone
    next_page.current_page += 1
    next_page
  end
  
  def file_path
    page = current_page == 1 ? '' : "_#{current_page}"
    File.expand_path( File.join(config['target_dir'], path, "index#{page}.html") )
  end
  
  def url
    page = current_page == 1 ? '' : "index_#{current_page}"
    config['url_prefix'] + '/' + path + '/' + page
  end
  
  protected
  def page_name
    'month'
  end
  
  def path
    month_entry.date.strftime('%Y/%m')
  end
end

class DayPage < Page
  attr_reader :day_entry
  
  def initialize config, log, day_entry
    @config     = config
    @log        = log
    @day_entry  = day_entry
  end
  
  def title
    date.strftime('%Y-%m-%d')
  end
  
  def date
    @day_entry.date
  end
  
  def tweets
    @day_entry.tweets do |tw|
      yield tw
    end
  end
  
  def file_path
    File.expand_path( File.join(config['target_dir'], path, 'index.html') )
  end
  
  def url
    config['url_prefix'] + '/' + path
  end
  
  protected
  def page_name
    'day'
  end
  
  def path
    day_entry.date.strftime('%Y/%m/%d')
  end
end

end

