$: << File.expand_path( File.join( File.dirname(__FILE__), '..', '..' ) )
require 'rubygems'
require 'optparse'
require 'yaml'
require 'twitter/log/archives'
require 'twitter/log/pages'

config        = File.join( File.dirname(__FILE__), 'example', 'config', 'config.yml' )
download_all  = false
re_construct  = false

opt = OptionParser.new
opt.on('-c', '--config-file CONFIG_FILE') { |v| config = v }
opt.on('-d') { |boolean| download_all = boolean }
opt.on('-r') { |boolean| re_construct = boolean }
opt.parse!

File.open(config) { |file| config = YAML.load(file) }

log = Twitter::Log::Archive.new(config)

update_months = []
update_days   = []
if log.recent_entry_id == nil || download_all
  log.download_all
  download_all = true
else
  log.download( 'count' => 200, 'since_id' => log.recent_entry_id ) do |tweet|
    tweet = Twitter::Log::Tweet.new(config, tweet)
    month = [tweet.created_at.year, tweet.created_at.month]
    update_months << month unless update_months.include?(month)
    day   = [tweet.created_at.year, tweet.created_at.month, tweet.created_at.day]
    update_days   << day   unless update_days.include?(day)
  end
end

if re_construct || download_all || (update_months.size > 0)
  index = Twitter::Log::IndexPage.new(config, log)
  index.generate
  rss   = Twitter::Log::RssPage.new(config, log)
  rss.generate
end

if re_construct || download_all
  index.month_pages.each do |month|
    begin
      month.generate
      month.current_day_pages.each do |day|
        day.generate
      end
    end while month = month.next
  end
else
  update_months.each do |month|
    month = Time.zone.local(*month)
    month_entry = log.month_entry(month)
    month_page = Twitter::Log::MonthPage.new(config, log, month_entry)
    begin
      month_page.generate
    end while month_page = month_page.next
  end
  
  update_days.each do |day|
    day = Time.zone.local(*day)
    day_entry = log.day_entry(day)
    day_page = Twitter::Log::DayPage.new(config, log, day_entry)
    day_page.generate
  end
end



