
module Rtlog
  class << self
    def logger=(logger)
      @@logger = logger
    end
    def logger
      @@logger
    end
    
    def root
      return RTLOG_ROOT if defined?(RTLOG_ROOT)
      @@rtlog_root = File.join(File.dirname(__FILE__), '..')
      return @@rtlog_root
    end
  end
end
