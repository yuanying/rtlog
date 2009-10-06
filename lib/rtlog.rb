
module Rtlog
  class << self
    def logger=(logger)
      @@logger = logger
    end
    def logger
      @@logger
    end
  end
end
