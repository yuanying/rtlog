
module Rtlog
  class << self
    def logger=(logger)
      @@logger = logger
    end
    def logger
      @@logger
    end
    
    def root
      RTLOG_ROOT if defined?(RTLOG_ROOT)
      RTLOG_ROOT = File.join(File.dirname(__FILE__), '..')
      RTLOG_ROOT
    end
  end
end
