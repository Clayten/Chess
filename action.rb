module Chess
  class Action
    attr_reader :type, :color
    def initialize color
      raise "Unknown color #{color}" unless Piece.colors.include? color
      @color = color
    end
  end

  class Move < Action
    attr_reader :type, :src, :dest
    def initialize color, type, src, dest
      super color
      @type, @src, @dest = type, src, dest
    end
  end

  class Capture < Move
    attr_reader :captured_type
    def initialize color, type, src, dest, captured_type
      super color, type, src, dest
      @capture = captured_type if captured_type
    end
  end

  class EnPassant < Capture
    attr_reader :capture_location
    def initialize color, src, dest, src2
      super color, :pawn, src, dest, :pawn
      @capture_location = src2
    end
  end

  class Castle < Move
    attr_reader :src2, :dest2
    def initialize color, src, dest, src2, dest2
      super color, :king, src, dest
      @src2, @dest2 = src2, dest2
    end
  end

  class Proposal < Action ; def initialize color ; super color end end
  class Resignation < Proposal ; def initialize color ; super color end end
  class Draw < Proposal ; def initialize color ; super color end end
end
