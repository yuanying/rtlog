require 'rubygems'
require 'rtlog'
require 'rubytter'
require 'active_support'
require 'fileutils'
require 'json/pure'
require 'open-uri'
require 'erb'

module Rtlog

module DirUtils
  def entries(path)
    Dir.entries(path).delete_if{|d| !(/\d+/ =~ d) }.reverse.map!{ |file| File.join(path, file) }
  end
end

class TwitPic
  TWIT_REGEXP = /http\:\/\/twitpic\.com\/([0-9a-zA-Z]+)/
  
  attr_reader :id
  attr_reader :config
  attr_reader :url
  
  def initialize config, url
    @config = config
    @url    = url
    @id     = TWIT_REGEXP.match(url)[1]
  end
  
  def original_thumbnail_url
    "http://twitpic.com/show/thumb/#{id}"
  end
  
  def local_url
    "#{config['url_prefix']}#{path}"
  end
  
  def download
    file_path   = File.expand_path( File.join(config['target_dir'], path) )
    folder_path = File.dirname(file_path)
    FileUtils.mkdir_p(folder_path) unless File.exist?(folder_path)
    open(original_thumbnail_url) do |f|
      extname = File.extname( f.base_uri.path )
      file_path = file_path + extname
      open(file_path, 'w') do |io|
        io.write f.read
      end
    end
    sleep 1
  end
  
  protected
  def path
    prefix = id[0, 2]
    "/twitpic/#{prefix}/#{id}"
  end
end

class Tweet
  include DirUtils
  include ERB::Util
  attr_reader :data
  attr_reader :config
  
  def initialize config, path_or_data
    @config = config
    if path_or_data.is_a?(String)
      open(path_or_data) do |io|
        @data = JSON.parse(io.read)
      end
    else
      @data = path_or_data
    end
  end
  
  def method_missing sym, *args, &block
    return super unless @data.key?(sym.to_s)
    return @data[sym.to_s]
  end
  
  URL_REGEXP    = /https?(:\/\/[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+)/
  REPRY_REGEXP  = /@(\w+)/
  
  def formatted_text
    t = h(text)
    t = t.gsub(URL_REGEXP)    { "<a href='#{$&}'>#{$&}</a>" }
    t = t.gsub(REPRY_REGEXP)  { "<a href='http://twitter.com/#{$1}'>@#{$1}</a>" }
    t
  end
  
  def id
    @data['id']
  end
  
  def medias
    unless defined?(@medias) && @medias
      @medias = []
      text.gsub(TwitPic::TWIT_REGEXP) do |m|
        @medias << TwitPic.new(config, m)
      end
    end
    @medias
  end
  
  def created_at
    Time.zone.parse(@data['created_at'])
  end
end

class Entry
  include DirUtils
  attr_reader :config
  attr_reader :path
  attr_writer :logger
  
  def initialize config, path
    @config = config
    @path   = path
    @date   = nil
  end
  
  def date
    unless @date
      @date = Time.zone.local( *path.split('/').last(date_split_size) )
    end
    @date
  end
  
  def logger
    defined?(@logger) ? @logger : Rtlog.logger
  end
end

class DayEntry < Entry
  def tweets
    entries(@path).each do |path|
      yield Tweet.new(config, path)
    end
  end
  
  def size
    entries(@path).size
  end
  
  protected
  def date_split_size
    3
  end
end

class MonthEntry < Entry
  
  def day_entries
    unless defined?(@day_entries) && @day_entries
      @day_entries = []
      entries(@path).each do |path|
        @day_entries << DayEntry.new(config, path)
      end
    end
    @day_entries
  end
  
  def size
    unless @size
      @size = 0
      day_entries.each do |d|
        @size += d.size
      end
    end
    @size
  end
  
  protected
  def date_split_size
    2
  end
end

class YearEntry < Entry
  
  def month_entries
    unless defined?(@month_entries) && @month_entries
      @month_entries = []
      entries(@path).each do |path|
        @month_entries << MonthEntry.new(config, path)
      end
    end
    @month_entries
  end
  
  protected
  def date_split_size
    1
  end
end

class Archive
  include DirUtils

  attr_accessor :config
  attr_writer :logger

  def initialize config
    @config       = config
    @tw           = Rubytter.new
    @year_entries = nil
    Time.zone     = @config['time_zone'] || user_info.time_zone
  end
  
  def logger
    defined?(@logger) ? @logger : Rtlog.logger
  end
  
  def user_info
    @userinfo ||= @tw.user( twitter_id )
    @userinfo
  end
  alias :user :user_info
  
  def recent_entry_id
    year_entries.first.month_entries.first.day_entries.first.tweets do |tweet|
      return tweet.id
    end
  rescue
    nil
  end
  
  def recent_day_entries size=7
    unless defined?(@recent_day_entries) && @recent_day_entries
      @recent_day_entries = []
      year_entries.each do |y|
        y.month_entries.each do |m|
          m.day_entries.each do |d|
            @recent_day_entries << d
            return @recent_day_entries if @recent_day_entries.size == size
          end
        end
      end
    end
    @recent_day_entries
  end
  
  def year_entries
    unless @year_entries
      @year_entries = []
      entries(temp_dir).each do |path|
        @year_entries << YearEntry.new(config, path)
      end
    end
    @year_entries
  end
  
  def month_entry month
    path = File.join( temp_dir, sprintf('%04d', month.year), sprintf('%02d', month.month) )
    MonthEntry.new(config, path)
  end
  
  def day_entry day
    path = File.join( temp_dir, sprintf('%04d', day.year), sprintf('%02d', day.month), sprintf('%02d', day.day) )
    DayEntry.new(config, path)
  end

  def temp_dir
    @temp_dir ||= File.expand_path(@config['temp_dir'])
    @temp_dir
  end

  def twitter_id
    @config['twitter_id']
  end

  def download option={}
    option['count'] ||= (@config['count'] || 200)
    option.reject! { |k,v|  v==nil }

    timeline = @tw.user_timeline( twitter_id, option )
    return false if timeline.size == 0
    return false if timeline.last.id == option['max_id']

    timeline.each do |status|
      status = JSON.parse(status.to_json)
      save status
      yield status if block_given?
    end

    @year_entries       = nil
    @recent_day_entries = nil
    return timeline.last.id
  end

  def download_all
    max_id = nil
    while true
      max_id = download('max_id' => max_id) unless block_given?
      max_id = download('max_id' => max_id) { |status| yield status } if block_given?
      break unless max_id
      sleep 10
    end
  end

  def save status
    Tweet.new(config, status).medias.each do |m|
      logger.debug("Download media: #{m.class}, #{m.id}")
      m.download
    end
    date = Time.zone.parse(status['created_at'])
    date = DateTime.parse(date.to_s)
    
    path = "#{temp_dir}/#{date.strftime('%Y/%m/%d')}/#{status['id']}.json"
    FileUtils.mkdir_p( File.dirname(path) ) unless File.exist?( File.dirname(path) )
    File.open(path, "w") { |file| file.write(status.to_json) }
    logger.debug("Tweet is saved: #{path}")
  end
  
end

end


