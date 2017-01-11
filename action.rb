module Chess
  class Action
    attr_reader :color
    def initialize  color
      raise "Unknown color #{color}" unless Piece.colors.include? color
      @color = color
    end
  end

  class Resignation < Action ; def initialize color ; super color ; @type = :resignation end end
  class Draw <        Action ; def initialize color ; super color ; @type = :draw_proposal end end

  # Move doesn't try to assume things such as the location of a pawn captured en-passant, or if and where pawns get promoted
  class Move < Action
    private

    def file_to_letter n ; (n + 9).to_s(36) end
    def xy_to_algebraic x, y ; [file_to_letter(x), y] end
    def locstr loc ; xy_to_algebraic(*loc).join end


    def s_type ; types[type] end
    def s_capturing ; captured_type ? 'x' : '' end
    def s_new_rand ; types[new_type] end
    public

    def to_s
      types = {king: 'K', queen: 'Q', rook: 'R', knight: 'N', bishop: 'B', pawn: ''}
      base = if src2
        if 1 == src2.first # queenside
          'O-O-O'
        else
          'O-O'
        end
      else
        "#{types[type]}#{'x' if captured_type}#{locstr dest}#{"=#{types[new_type]}" if new_type}"
      end
      state = "#{'+' if check}#{'#' if checkmate}"
      base + state
    end

    def description
      "#{color} #{type} " +
      "#{src2 ? 'castles' : 'moves'} from #{locstr src} to #{locstr dest}" +
      "#{" capturing#{' en-passant' if capture_location} a #{captured_type}#{" at #{locstr capture_location}" if capture_location}" if captured_type}" +
      "#{" and is promoted to #{new_type}" if new_type}"
    end

    def inspect
      "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} - #{description}>"
    end

    attr_reader :color, :type, :src, :dest, :captured_type, :src2, :dest2, :new_type, :capture_location
    attr_accessor :check, :checkmate # These are set after the fact - it isn't know until the move is applied to the board
    def initialize color, type,
                   src:, dest:,                # for all moves
                   captured_type: nil,         # for a capture
                   capture_location: nil,      # for en-passant
                   src2: nil, dest2: nil,      # for castling
                   new_type: nil,              # for a pawn promption
                   check: false, checkmate: false
      super color
      raise "Non-pawns can't get promoted" unless :pawn == type if new_type
      raise "Non-pawns can't capture en-passant" unless :pawn == type if capture_location
      @type, @src, @dest = type, src, dest
      @captured_type = captured_type
      @capture_location = capture_location
      @src2, @dest2 = src2, dest2
      @new_type = new_type
      @check, @checkmate = check, checkmate
    end
  end
end
