module Chess
  class Piece

    def self.diagonal_rays ; [[-1,-1], [1,-1], [-1,1], [1,1]] end
    def self.cardinal_rays ; [[1,0], [-1,0], [0,1], [0,-1]] end

    def self.piece_name ; name.split('::').last.downcase.to_sym end

    def self.colors ; [:black, :white] end
    def self.classes ; @classes ||= begin ; h = {} ; types.each {|t| h[t] = const_get t.to_s.capitalize.to_sym } ; h end end
    def self.types ; @types ||= %w(king queen rook bishop knight pawn).map &:to_sym end

    # https://en.wikipedia.org/wiki/Chess_symbols_in_Unicode
    def self.unicode
      unicode ||= begin
        chess_base = 0x2654
        r = {}
        colors.each_with_index.map {|color, ci|
          r[color] = {}
          offset = ci * 6 # 0 or 6
          types.each_with_index.map {|(type, _), ti|
            # p [:un, color, offset, type, ti, chess_base+offset+ti]
            r[color][type] = (chess_base + offset + ti).chr('UTF-8')
          }
        }
        r
      end
    end

    def self.ascii
      ascii ||= begin
        r = {}
        colors.map {|color|
          types.map {|type|
            c = types[type]
            c.upcase! if color == colors.first
            r[color][type] = c
          }
        }
        r
      end
    end

    def self.other_color color ; (colors - [color]).first end

    def self.create color, type, board
      raise "Invalid color #{color.inspect}" unless colors.include? color
      raise "Invalid type #{  type.inspect}" unless types.include?(type)
      classes[type].new color, board
    end

    # algebraic chess notation only
    def self.from_notation c
      color = (c == c.upcase) ? colors.first : colors.last
      type = types.find {|k,v| v == c.upcase }.last
      new color, type
    end

    def can_move_to x, y
      moves.any? {|mv| mv.dest == [x, y] }
    end

    def location
      @location ||= board.location_of self
    end

    def on_color
      board.color_at *location
    end

    def moved? ; !!last_move end

    def moved ; @number_of_moves += 1 ; @last_move = board.halfmove_number ; @location = nil ; end

    def moves ; self.class.moves board, self end

    # Creates the object, doesn't apply it
    def move dest: , src2: nil, dest2: nil, capture_location: nil
      dx, dy = dest
      final    = :white == color ? board.ysize : 1 # where do we get promoted?
      new_type = :queen if :pawn == type && dy == final
      captured = board.pieces[dest] || board.pieces[capture_location]
      captured_type = captured.type if captured
      check = checkmate = false # TODO fix this...
      Move.new color, type, src: location, dest: dest, new_type: new_type, src2: src2, dest2: dest2,
        captured_type: captured_type, capture_location: capture_location, check: check, checkmate: checkmate
    end

    # classes are responsible for overriding for enpassant, castling, etc
    def move_to x, y = nil
      x, y = x unless y
      board.move move dest: [x, y]
    end


    def to_s ; @symbol ||= true ? self.class.unicode[color][type] : self.class.ascii[color][type] end

    def type ; self.class.piece_name end

    def opponent_color ; self.class.other_color color end

    def inspect ; "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{color}#{' - unmoved' unless last_move}>" end

    def diagonal_rays ; self.class.diagonal_rays end
    def cardinal_rays ; self.class.cardinal_rays end
    def move_pattern ; self.class.move_pattern end
    def threatened_squares include_self = true ; board.available_moves_along_rays x, y, move_pattern, (include_self ? :both : color) end # Includes enemies and friendlies
    def moves ; threatened_squares(false).map {|dx,dy| move dest: [dx, dy] } end
    def check? ; board.threatened_squares(color).include? location end

    def x ; location[0] end
    def y ; location[1] end

    def enemy_color ; board.other_color color end

    attr_accessor :board
    attr_reader :color, :last_move, :number_of_moves
    def initialize color, board
      @color = color
      @board = board
      @number_of_moves = 0
      @last_move = nil
    end

    class Rook < Piece
      def self.move_pattern ; cardinal_rays end
    end

    class Bishop < Piece
      def self.move_pattern ; diagonal_rays end
    end

    class Queen < Piece
      def self.move_pattern ; diagonal_rays + cardinal_rays end
    end

    class King < Piece
      def self.move_pattern ; Queen.move_pattern.map {|ray| ray << 1 } end # Same directions, limit one square
      def moves
        locations_in_check = board.threatened_squares(color).uniq
        super.reject {|mv| locations_in_check.include? mv.dest }
      end
    end

    class Knight < Piece
      def self.move_pattern ; [[-1,-2], [-2,-1], [1,-2], [-2,1], [-1, 2], [2, -1], [1, 2], [2, 1]] ; end
      def threatened_squares # TODO Make other threatened_squares() methods like this one - follow rays and "capture" both.
        move_pattern.map {|ox,oy|
          dx = x + ox
          next if dx < 1 || dx > board.xsize
          dy = y + oy
          next if dy < 1 || dy > board.ysize
          [dx, dy]
        }.compact
      end
      def moves ; threatened_squares.map {|dx,dy| dest = board.at(dx, dy) ; next if dest && dest.color == color ; move dest: [dx, dy] }.compact end
    end

    class Pawn < Piece
      def start_rank ; :white == color ? 2 : 7 end
      def enpassant_rank ; :white == color ? 5 : 4 end
      def offset ; board.pawn_offset color end
      def can_move_double ; start_rank == y && number_of_moves.zero? end
      def can_capture_enpassant ; enpassant_rank == y end # FIXME What is a proper test on a non-standard board?
      def can_be_captured_enpassant ; start_rank + offset * 2 == y && 1 == number_of_moves end

      def move_pattern ; [[0,offset,(can_move_double ? 2 : 1)]] end
      def direct_capture_pattern ; [[-1, offset], [1, offset]] end
      def enpassant_pattern ; can_capture_enpassant ? direct_capture_pattern.map {|x,y| [x,y,x,0] } : [] end
      def capture_pattern ; direct_capture_pattern + enpassant_pattern.map {|_,_,x,y| [x,y, :enpassant] } end

      def threatened_squares
        capture_pattern.map {|ox,oy,type| [x + ox, y + oy, type] }.reject {|tx, ty| tx < 1 || tx > board.xsize || ty < 1 || ty > board.ysize }
      end
      def moves
        results = board.available_moves_along_rays(x, y, move_pattern).map {|dx, dy| move dest: [dx, dy] }
        results += direct_capture_pattern.map {|dox,doy|
          dx, dy = x + dox, y + doy
          dest = board.at dx, dy
          next unless dest && dest.color != color
          move dest: [dx, dy]
        }
        results += enpassant_pattern.map {|dox,doy,cox,coy|
          dx, dy = x + dox, y + doy
          cx, cy = x + cox, y + coy
          dest    = board.at dx, dy
          next if dest # is occupied
          capture = board.at cx, cy
          next unless capture && capture.color == enemy_color && :pawn == capture.type && capture.can_be_captured_enpassant
          move dest: [dx, dy], capture_location: [cx, cy]
        }
        results.compact
      end
    end
  end
end
