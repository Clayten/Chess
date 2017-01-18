module Chess
  class Piece

    # FIXME rename to vector - ray is the locations
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

    def can_move_to x, y ; threatened_squares.map {|a,b,c| [a,b] }.include? [x, y] end

    def location
      @location ||= board.location_of self
    end

    def on_color
      board.color_at *location
    end

    def moved? ; !!last_move end

    def moved ; @number_of_moves += 1 ; @last_move = board.halfmove_number ; @location = nil ; end

    # Creates the object, doesn't apply it
    def move dest: , src2: nil, dest2: nil, capture_location: nil
      dx, dy = dest
      final    = :white == color ? board.ysize : 1 # where do we get promoted?
      new_type = :queen if :pawn == type && dy == final
      captured = board.pieces[dest] || board.pieces[capture_location]
      captured_type = captured.type if captured
      check = threatened_squares(dx, dy).include? board.king(enemy_color)&.location
      checkmate = false # TODO fix this...
      Move.new color, type, src: location, dest: dest, new_type: new_type, src2: src2, dest2: dest2,
        captured_type: captured_type, capture_location: capture_location, check: check, checkmate: checkmate
    end

    # classes are responsible for overriding for enpassant, castling, etc
    def move_to x, y = nil
      x, y = x unless y
      board.move move dest: [x, y]
    end

    def fen_code ; {king: 'K', queen: 'Q', rook: 'R', knight: 'N', bishop: 'B', pawn: 'P'} ; end

    def to_fen ; s = fen_code[type] ; :white == color ? s : s.downcase end

    def to_s ; @symbol ||= true ? self.class.unicode[color][type] : self.class.ascii[color][type] end

    def type ; self.class.piece_name end

    def inspect ; "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{color}#{' - unmoved' unless last_move}>" end

    def diagonal_rays ; self.class.diagonal_rays end
    def cardinal_rays ; self.class.cardinal_rays end
    def move_pattern ; self.class.move_pattern end

    # The pseudo-legal moves - including into our own pieces. Used for calculating check, etc.
    def threatened_squares tx = x, ty = y ; board.available_moves_along_rays tx, ty, move_pattern end

    # The actual legal moves, with the exception of revealed-check
    def moves tx = x, ty = y ; threatened_squares(tx, ty).map {|dx,dy| move dest: [dx, dy] unless board.at(dx,dy)&.color == color }.compact end

    # This piece, royal or not - don't consider enpassant unless told to, because it probably doesn't apply to us
    def check? tx = x, ty = y, consider_enpassant: false ; board.threatened_squares(color, consider_enpassant: consider_enpassant).map {|a,b,c| [a,b] }.include? [tx, ty] end

    def x ; location[0] end
    def y ; location[1] end

    def valid_x tx ; tx >= 1 && tx <= board.xsize end
    def valid_y ty ; ty >= 1 && ty <= board.ysize end
    def valid_xy tx, ty ; valid_x(tx) && valid_y(ty) end

    def enemy_color ; board.other_color color end

    attr_accessor :board
    attr_reader :color, :last_move, :number_of_moves
    def initialize color, board
      @color = color
      @board = board
      @number_of_moves = 0
      @last_move = nil
    end

    class Queen < Piece
      def self.move_pattern ; diagonal_rays + cardinal_rays end
    end

    class Bishop < Piece
      def self.move_pattern ; diagonal_rays end
    end

    class Rook < Piece
      def self.move_pattern ; cardinal_rays end
      def starting_rank ; :white == color ? 1 : 8 end # TODO - 8x8 centric
      def in_starting_position? ; starting_rank == y && [1,8].include?(x) end # We don't try to figure out where we actually started
      def can_castle? ; in_starting_position? && !moved? end
    end

    class Knight < Piece
      def self.move_pattern ; [[-1,-2], [-2,-1], [1,-2], [-2,1], [-1, 2], [2, -1], [1, 2], [2, 1]] ; end
      def threatened_squares tx = x, ty = y ; move_pattern.map {|ox,oy| dx, dy = tx + ox, ty + oy [dx, dy] if valid_xy dx, dy }.compact end
      def moves tx = x, ty = y ; threatened_squares(tx, ty).map {|dx,dy| dest = board.at(dx, dy) ; next if dest&.color == color ; move dest: [dx, dy] }.compact end
    end

    class King < Piece
      def self.move_pattern ; Queen.move_pattern.map {|ray| ray << 1 } end # Same directions, limit one square
      def starting_rank ; :white == color ? 1 : 8 end # TODO Assumes 8x8 - can't castle otherwise
      def starting_location ; [5, starting_rank] end
      def can_castle? ; starting_location == location && !moved? end
      def  left_rook ; r = board.at(1, starting_rank) ; r if :rook == r&.type && color == r.color end
      def right_rook ; r = board.at(8, starting_rank) ; r if :rook == r&.type && color == r.color end
      def castleability ; [left_rook, right_rook].map {|rook| can_castle? && rook&.can_castle?  } end
      def squares_between check_to ; a, b = [x, check_to].sort ; a.upto(b).map {|tx| yield tx, y } end

      def castling_moves
        return [] unless 8 == board.xsize && 8 == board.ysize # Ensure standard board - TODO allow castling in nonstandard setups (5x5, etc)
        return [] if moved? || location != starting_location
        can_castle_left, can_castle_right = castleability
        threats = nil
        [[left_rook, 4, 3, can_castle_left], [right_rook, 6, 7, can_castle_right]].map {|rook, rook_dest, king_dest, can_castle|
          next unless can_castle
          threats = board.threatened_squares(color) # FIXME Speedtest using .uniq here
          next unless catch(:stop) do
            squares_between(king_dest) {|*loc| next if location == loc ; throw :stop if board.at(loc) || threats.include?(loc) }
            true
          end
          move dest: [king_dest, y], src2: [rook.x, y], dest2: [rook_dest, y]
        }.compact
      end

      def moves tx = x, ty = y
        locations_in_check = board.threatened_squares(color) # .uniq # FIXME slow
        super.reject {|mv| locations_in_check.include? mv.dest } + castling_moves
      end

      def to_pgn
        can_castle_left, can_castle_right = castleability
        upcase = :white == color
        (can_castle_right ? (upcase ? 'K' : 'k') : '') + (can_castle_left ? (upcase ? 'Q' : 'q') : '')
      end
    end

    class Pawn < Piece
      def start_rank ; :white == color ? 2 : 7 end
      def enpassant_rank ; :white == color ? 5 : 4 end
      def offset ; board.pawn_offset color end # Which direction do we go? [1,-1]
      def can_move_double ; start_rank == y && number_of_moves.zero? end
      def can_capture_enpassant ; enpassant_rank == y end # FIXME What is a proper test on a non-standard board?
      def can_be_captured_enpassant ; start_rank + offset * 2 == y && 1 == number_of_moves end

      def move_pattern ; [[0,offset,(can_move_double ? 2 : 1)]] end # a ray of length 1 or 2
      def direct_capture_pattern ; [[-1, offset], [1, offset]] end
      def direct_enpassant_pattern ; direct_capture_pattern.map {|ox,oy| [ox,oy,ox,0] } end # Adds a capture location - to either side, on the same rank
      def enpassant_pattern ; can_capture_enpassant ? direct_enpassant_pattern : [] end
      def capture_pattern ; direct_capture_pattern + enpassant_pattern.map {|_,_,x,y| [x,y, :enpassant] } end # for enpassant we only care where we threaten, not end up

      # In this case, we are vulnerable to enpassant, so enquire about threat via it
      def check? tx = x, ty = y ; super tx, ty, consider_enpassant: true end

      def move_squares tx = x, ty = y ; board.available_moves_along_rays(tx, ty, move_pattern).map {|dx, dy| [dx, dy] } end
      def threatened_squares tx = x, ty = y ; capture_pattern.map {|ox,oy,enpassant| dx, dy = tx + ox, ty + oy ; [dx, dy, enpassant] if valid_xy dx, dy }.compact end

      def can_move_to x, y ; super || move_squares.include?([x,y]) end

      def moves tx = x, ty = y
        results = move_squares.map {|dx, dy| move dest: [dx, dy] unless board.at(dx, dy) }.compact

        # FIXME consolidate these routines
        results += direct_capture_pattern.map {|dox,doy|
          dx, dy = tx + dox, ty + doy
          dest = board.at dx, dy
          next unless dest && dest.color != color
          move dest: [dx, dy]
        }
        results += enpassant_pattern.map {|dox,doy,cox,coy|
          dx, dy = tx + dox, ty + doy
          cx, cy = tx + cox, ty + coy
          dest    = board.at dx, dy
          next if dest # is occupied
          capture = board.at cx, cy
          next unless capture && enemy_color == capture.color && :pawn == capture.type && capture.can_be_captured_enpassant
          move dest: [dx, dy], capture_location: [cx, cy]
        }
        results.compact
      end
    end
  end
end
