module Chess
  class Piece

    def self.piece_name ; name.split('::').last.downcase.to_sym end

    def self.colors ; [:black, :white] end
    def self.klasses
      @klasses ||= begin
        ks = {}
        constants.each {|c|
          k = const_get c
          next unless k.is_a? Class
          ks[c.to_s.split('::').last.downcase.to_sym] = k
        }
        ks
      end
    end
    def self.types ; klasses.keys end

    # def self.types  ; {king:   :K,
    #                    queen:  :Q,
    #                    rook:   :R,
    #                    bishop: :B,
    #                    knight: :N,
    #                    pawn:   :P}
    # end

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
      klasses[type].new color, board
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
      board.location_of self
    end

    def on_color
      board.color_at *location
    end

    def moved? ; !!last_move end

    def moved ; @number_of_moves += 1 ; @last_move = board.halfmove_number end

    def moves ; self.class.moves board, self end

    # Creates the object, doesn't apply it
    def move dest: , src2: nil, dest2: nil, capture_location: nil
      final    = :white == color ? board.ysize :  1 # where do we get promoted?
      new_type = :queen if :pawn == type && dest.last == final
      captured = board.pieces[dest] || board.pieces[capture_location]
      captured_type = captured.type if captured
      check = checkmate = false # TODO fix this...
      Move.new color, type, src: location, dest: dest, new_type: new_type, src2: src2, dest2: dest2,
        captured_type: captured_type, capture_location: capture_location, check: check, checkmate: checkmate
    end

    def to_s ; @symbol ||= true ? self.class.unicode[color][type] : self.class.ascii[color][type] end

    def type ; self.class.piece_name end

    def opponent_color ; self.class.other_color color end

    def inspect ; "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{color}#{' - unmoved' unless last_move}>" end

    attr_accessor :board
    attr_reader :color, :last_move, :number_of_moves
    def initialize color, board
      @color = color
      @board = board
      @number_of_moves = 0
      @last_move = nil
    end

    # Order of classes is important to match Unicode symbols
    class King < Piece
      def self.check? board, piece
        board.moves(piece.opponent_color).any? {|type, src, dest, capture| piece == capture }
      end
      def check? ; self.class.check? board, self end

      def self.moves board, piece
        board.adjacent_squares(piece) + board.castling(piece)
      end
    end

    class Queen < Piece
      def self.moves board, piece
        board.diagonal_lines(piece) + board.cardinal_lines(piece)
      end
    end

    class Rook < Piece
      def self.moves board, piece
        board.cardinal_lines(piece)
      end
    end

    class Bishop < Piece
      def self.moves board, piece
        board.diagonal_lines(piece)
      end
    end

    class Knight < Piece
      # Possible landing squares, discounting check, etc.
      def self.possible_moves x, y
        raise
      end
      def self.moves board, piece
        board.knight_moves(piece)
      end
    end

    # TODO replace with methods on board. Partly so method names are 'pawn_moves', etc.
    class Pawn < Piece
      def self.moves board, piece
        board.pawn_moves(piece)
      end
    end
  end
end
