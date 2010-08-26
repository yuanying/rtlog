
module Rtlog
  class << self
    def logger=(logger)
      @@logger = logger
    end
    def logger
      @@logger
    end
    
    def root
      File.join(File.dirname(__FILE__), '..')
    end
  end
end
