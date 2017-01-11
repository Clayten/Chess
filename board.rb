module Chess
  class Board

    attr_reader :states

    # Hash state, store, check for triplicates - draw
    def distinct_state ; "<#{self.class.name} #{xsize}x#{ysize} #{pieces.sort_by {|(x,y),_| [x,y] }.map {|(x,y),pc| "(#{pc.color} #{pc.type}-#{x},#{y}-#{pc.moved?})" }.join(', ')}#{" - cap #{captures.map {|pc| "#{pc.type}" }.join(',')}" unless captures.empty?}>" end

    def state_hash ; Digest::SHA256.hexdigest distinct_state end

    def test_move mv
      dup.force_move(mv.src, mv.dest, mv.src2, mv.dest2)
    end

    # # [int, int] or [char, int]
    # def parse x, y
    #   x = x.to_i(10 + xsize) - 10 unless x.is_a? Integer # by default, base 18 ('a' -> 'h') - 10 == 0->7
    #   raise "x: #{x} out of bounds" if x < 1 || x > xsize
    #   raise "y: #{y} out of bounds" if y < 1 || y > ysize
    #   [x, y]
    # end

    def add_piece x, y, color, type
      # p [:add_piece, x, y, color, type]
      loc = [x, y].map(&:to_i)
      raise "There's already a #{pieces[loc]} at #{loc.join(',')}" if pieces[loc]
      pieces[loc] = Piece.create color, type, self
    end

    def location_of piece
      return :captured if captures.include? piece
      loc, _ = pieces.find {|loc, pc| pc == piece }
      loc
    end

    # syntactic sugar
    # (x,y) or ([x,y]) -> (piece || nil)
    def at x, y = nil
      x, y = x if x.respond_to? :length
      pieces[[x,y]]
    end

    def white_square ; "\u25a0" end
    def black_square ; "\u25a1" end
    def square color ; color == :white ? white_square : black_square end

    def color_at x, y
      (((x % 2) + (y % 2)) % 2).zero? ? :black : :white
    end

    def render
      ysize.downto(1).map {|y|
        1.upto(xsize).map {|x|
          pieces[[x,y]] || square(color_at(x,y))
        }.join + " #{y}"
      }.join("\n") +
      "\n" + xsize.times.map {|i| (i + 10).to_s(36) }.join + "\n"
    end
    def display
      puts render
    end

    attr_reader :pieces

    public

    def other_color c ; Piece.other_color c end

    def next_to_play ; other_color to_play end

    def to_play ; Piece.colors[halfmove_number % 2] end

    # direction of movement for a pawn of some color - 1 or -1
    def pawn_offset color
      :white == color ? 1 : -1
    end

    def follow_ray x, y, step_x, step_y
      loop do
        x += step_x
        y += step_y
        break unless x <= xsize && x >= 1 && y <= ysize && y >= 1
        yield x, y
      end
    end

    # Moves, including those which capture if you specify you can capture (pawns cannot along their movement squares)
    def available_moves_along_rays x, y, rays, capture_as = nil, maxlen = nil
      results = []
      rays.each {|step_x, step_y, maxlen| # A ray is sequentially checked until blocked
        count = 0 if maxlen
        follow_ray(x, y, step_x, step_y) {|tx, ty|
          pc = at(tx, ty)
          capture = capture_as && pc && (:both == capture_as || pc.color != capture_as)
          results << [tx, ty] unless pc && !capture
          break if pc
          if maxlen
            count += 1
            break if count == maxlen
          end
        }
      }
      results
    end

    # TODO Correct name for 50-move-draw - https://chessprogramming.wikispaces.com/Reversible+moves

    # Not for normal use, might leave board in illegal condition
    # NOTE Not incrementing turn #, etc. We can test our position for own-check this way
    def force_move src_loc, dest_loc, src2_loc = nil, dest2_loc = nil
      pieces[dest_loc]  = pieces.delete  src_loc # BAM, it's done. But it may not be legal
      pieces[dest2_loc] = pieces.delete src2_loc if src2_loc # Move the secondary piece if there is one
      self
    end

    def mutate
      pcs, caps = pieces.dup, captures.dup
      @history, @states = history.dup, states.dup
      @pieces, @captures = {}, []
      pcs.each  {|k,v| v = v.dup ; pieces[k]  = v ; v.board = self }
      caps.each {|  v| v = v.dup ; captures  << v ; v.board = self }
      self
    end

    def dup
      super.mutate
    end

    def enemy_pieces color = to_play ; pieces.values.select {|pc| pc.color != color } end
    def own_pieces color = to_play ; pieces.values.select {|pc| pc.color == color } end

    # You need to know if your piece is vulnerable to enpassant
    def threatened_squares color = to_play, consider_enpassant = false # by color's enemy
      squares = enemy_pieces(color).map {|pc| pc.threatened_squares }.inject(&:+) || []
      squares.reject! {|x,y,type| :enpassant == type } unless consider_enpassant
      squares.map!    {|x,y,type| [x, y] } unless consider_enpassant
      squares
    end

    def moves color = to_play, quick = false # quick means don't go into the issue of what wouldn't be legal because it could cause check
      # p [:halfmove_number, halfmove_number, :color, color, :quick, quick]
      mvs = own_pieces(color).map {|pc| pc.moves }.inject(&:+) || []
      return mvs if quick
      mvs.reject {|mv| test_move(mv).check?  }
    end

    # TODO Check if it's a pawn move, or a capture, then reset the 50-move draw clock
    # TODO break out list of possible squares to move into, to iterate over for legal moves, and to properly display A pawn can't, and THIS pawn can't...
    # The issue is that some moves are complex to generate (castling), or can only happen if a certain square is occupied (en-passant.)
    # I'd like a list of squares-in-check-by-enemy, to help score the board, and squares-in-check-by-self...
    # I want to know my pawn will be at risk if I move it two squares, but the pawn sitting in position to capture en-passant doesn't place that square in check until after I move.
    # I'm not looking to know if a piece will remain safe, that's an issue for recursive checking, but to see if a piece will be safe where placed, for this turn.
    # If I move a pawn en-passant, how without recursively examining moves, can I see that it can die? The enemy can't move there to cause check, yet, because my pawn
    # isn't there. Pawn moves in general, but especially en-passant.
    # Can I answer this with a list of possibilities that include these specialty attacks? Flag the square as en-passant and ignore it for all non-pawns...
    # Also, even recursive analysis needs to include static analysis unless it can reach the end. I need to see if a spot is under-guard by me, and the enemy.
    #
    # idea - scan enemy moves without check, which terminates. Cache these (@enemy_cache[turn] = ...)
    # From that, generate the list of attacked squares. These forbid king movement, and can be used for check?() instead of the dup/move/check method.
    # Main difference being an up-front check and caching of enemy moves, instead of checking each move against a newly generated list on a duplicated board.

    # Separate list of movements, and of captures. For most pieces, one set is the other. For pawns, not so. Ditto castling.
    # I don't really care where the enemy moves, I care where they control. This is exemplified by fairy chess where the 'coordinator' pieces can capture one or two
    # distant pieces at the other two corners of a rectangle between itself and the king. You don't care where they can move to know where they can hurt you. But,
    # you do need to know where they can move to achieve this in order to block that movement.

    # scoring ideas
    # piece values. squares under guard. strength of pieces under guard. Depth of guard. Both a guared guard, and a doubly-guarded square.
    # pieces threatened, pieces threatened by weaker pieces.
    # potential revealed thread. Piece-moves not blocked by their own color.
    #   In starting position your pawns would be in some threat from the opposing main pieces, because the opposing pawns could move.
    #   Or is this, number_of_turns_till_threatened, of which higher is better. Or, pieces at threat next turn?
    #   ...

    def enemy_king color = next_to_play ; king color end
    def   own_king color = to_play      ; king color end
    def king color = to_play ; pieces.values.find {|pc| pc.color == color && :king == pc.type } end
    def kings ; [own_king, enemy_king] end # Not passing color, order will vary

    def enemy_moves
      moves(next_to_play, true) # We don't care if an enemy move exposes them to check because we'd be dead by then
    end

    def check mv
      # p [:check, :mv, mv]
      raise "Not a move '#{mv.inspect}'" unless mv.respond_to? :src
      raise "Game finished" unless :in_progress == status
      src_loc, dest_loc = mv.src, mv.dest
      src, dest = pieces[src_loc], pieces[dest_loc]
      raise "No piece at #{mv.src.join(',')}" unless src
      raise "It isn't #{src.color}'s turn" unless src.color == to_play
      raise "A #{src.type} can't move from #{mv.src.join(',')} to #{mv.dest.join(',')}" unless src.can_move_to(*dest_loc)
      raise "Move exposes king to check" if test_move(mv).check?
      if dest
        raise "Destination occupied by same color" if dest.color == src.color
        raise "Chess does not support regicide" if :king == dest.type
      end
      if mv.src2 # secondary piece - during castling only
        src2_loc, dest2_loc = mv.src2, mv.dest2
        src2 = pieces[src2_loc]
        raise "Castling can't capture" if pieces[dest_loc] || pieces[dest2_loc]
        raise "Only castling involves moving two pieces" unless :king == src.type
        raise "King has already moved" if src.moved?
        raise "Only rooks can castle with kings" unless :rook == pieces[src2_loc].type
        raise "Rook has already moved" if pieces[src2_loc].moved?
      end
      true
    end

    # Process a move, after checking if it is allowed
    def move mv
      src_loc, dest_loc = mv.src, mv.dest
      src, dest = pieces[src_loc], pieces[dest_loc]

      check mv

      captures << dest if dest
      pieces[dest_loc] = pieces.delete src_loc
      src.moved
      if mv.src2 # secondary piece - during castling only
        src2_loc, dest2_loc = mv.src2, mv.dest2
        src2 = pieces[src2_loc]
        pieces[dest2_loc] = pieces.delete src2_loc if src2
        src2.moved if src2
      end
      if mv.new_type
        src = pieces[dest_loc] = Piece.create(mv.color, mv.new_type, self)
      end
      history << mv
      states << (hsh = state_hash)
      @halfmove_number += 1
      @draw_clock = halfmove_number if mv.captured_type || :pawn == mv.type # These things reset the 50-move draw-clock

      # This occurs as the next player
      if check?
        if moves.empty?
          mv.checkmate = true
        else
          mv.check = true
        end
      end
      true
    end

    # TODO output and parse FEN and X-FEN :
    # https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation
    # https://en.wikipedia.org/wiki/X-FEN

    def transcript ; history.each_slice(2).each_with_index.map {|(m1, m2),i| "#{i + 1}. #{m1}#{" #{m2}" if m2}" }.join(' ') + " #{status_text}" end

    def self.parse_pgn_header line
      md = line.match(/^\[(?<key>\w+)\s+"(?<value>.*)"\]$/)
      raise "Malformed header: '#{line}'" unless md
      [md[:key], md[:value]]
    end

    def self.load_transcript str
      headers = {}
      pgns = []
      str.split("\n").each {|line|
        if line =~ /^\[.*\]$/
          k, v = parse_pgn_header line ; headers[k] = v
        else
          pgns << line
        end
      }
      pgn = pgns.join(' ')
      move_pattern = '\s+(.*?\w\d|O-O|O-O-O)' # FIXME Can't handle promotions and check/checkmate
      move_pairs = pgn.scan(/\d+\.#{move_pattern}#{move_pattern}?/).flatten.compact.map(&:strip)
      score = pgn.scan(/\S+$/)
      [headers,move_pairs,score]
    end

    # Must be done on the instance, as it relies on context
    # returns the src_loc and dest_loc
    def parse_pgn_move pgn, num = 1 # used to determine color for ambiguous moves
      color = [:black, :white][num % 2]
      last_rank = :white == color ? 1 : board.ysize
      queenside_file, kingside_file = 'c', 'g'
      type, disambiguator, capture, file, rank, rest = nil
      type_p          = '([KQRBNP]|)' # The 'P' is unusual but not wrong
      disambiguator_p = '([a-l]|\d+?)'
      capture_p       = '(x)'
      file_p          = '([a-l])'
      rank_p          = '(\d+)'
      rest_p          = '(.+)'
      pattern = /^#{type_p}#{disambiguator_p}?#{capture_p}?#{file_p}#{rank_p}#{rest_p}?$/

      case pgn
      when /O-O-O/ ; type, file, rank = 'K', queenside_file, last_rank
      when /O-O/   ; type, file, rank = 'K',  kingside_file, last_rank
      when /.\d/   ; type, disambiguator, capture, file, rank, rest = pgn.match(pattern).captures
      else         ; raise "Unknown move #{pgn}"
      end
      type ||= 'P'
      new_type, _ = rest.match(/=(.)/).captures if rest =~ /=/
      check       = !!(rest =~ /\+/)
      checkmate   = !!(rest =~ /#/)

      [type, disambiguator, capture, file, rank, new_type, check, checkmate]
    end

    def self.status_text status, winner
      case status
      when :in_progress ; '*'
      when :stalemate   ; '1/2-1/2'
      when :draw        ; '1/2-1/2'
      when :checkmate   ; (:white == winner ? '1-0' : '0-1')
      else ; raise "Unknown status #{status.inspect}"
      end
    end
    def status_text ; self.class.status_text status, winner end

    # X-FEN https://en.wikipedia.org/wiki/X-FEN
    def to_pgn
      headers = {
         Event: 'unnamed',
          Site: `hostname`.strip,
          Date: Time.now.strftime('%Y.%m.%d'),
         Round: 1,
         White: 'Computer',
         Black: 'Computer',
        Result: status_text,
      }
      castling_availability = "#{'K'}#{'Q'}#{'k'}#{'q'}" # TODO lookup king and rook .moved?
      current_state = initial_layout + " #{:white == to_play ? 'w' : 'b'} #{castling_availability} - #{halfmove_number - draw_clock} #{(halfmove_number + 1).div(2)}"
      (headers.map {|k,v| "[#{k} \"#{v}\"]" } + [current_state, transcript]).join("\n")
    end

    def self.layouts
      {
          empty_8x8: '8/8/8/8/8/8/8/8',
        default_8x8: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
      }
    end
    def layouts ; self.class.layouts end

    def parse_fen_line line
      line.gsub!(/\d+/) {|s| '.' * s.to_i }
      line.split(//)
    end

    def parse_fen fen
      # p [:pf, fen]
      fen.split('/').map {|l| parse_fen_line l }
    end

    def setup
      @pieces = {}
      @captures = []
      @history = []
      @states = []
      @halfmove_number = 1 # FIXME - set from FEN string, if included, along with .moved? status for kings, rooks, etc.
      @draw_clock = halfmove_number

      types = {p: :pawn, k: :king, q: :queen, b: :bishop, n: :knight, r: :rook}

      layout = parse_fen initial_layout
      @ysize = layout.length
      @xsize = layout.first.length

      layout.zip(ysize.downto(1).to_a).each {|pieces, y|
        pieces.zip(1.upto(xsize).to_a) {|pc, x|
          next unless type = types[pc.downcase.to_sym]
          color = (pc == pc.upcase) ? :white : :black
          add_piece x, y, color, type
        }
      }
      self
    end

    def inspect
      "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{xsize}x#{ysize} - " +
      "#{pieces.length + captures.length} pieces - #{captures.length} captured>"
    end

    # Returns true if the *current* state has happened two or more times before
    # You may call for draw at the beginning or end of your turn, but if you don't you lose the chance until it arises again
    def threefold_repetition?
      count = 0
      current_state = states.last
      states.reverse.each {|state|
        next unless current_state == state
        count += 1
        return true if 3 == count
      }
      false
    end

    def status
      if threefold_repetition?
        :draw # Assume the game is halted when possible # FIXME - :draw_possible? Communicate up but don't force
      elsif checkmate?
        :checkmate
      elsif stalemate?
        :stalemate
      else
        :in_progress
      end
    end

    def check?
      moves(next_to_play, true).each {|mv|
        return true if mv.captured_type && :king == mv.captured_type
      }
      false
    end

    def checkmate?
      moves.empty? && check?
    end

    def stalemate?
      moves.empty? && !check?
    end

    def winner ; next_to_play if checkmate? end
    def loser  ;      to_play if checkmate? end

    attr_reader :xsize, :ysize, :captures, :halfmove_number, :initial_layout, :draw_clock, :history, :states
    def initialize layout_ = nil, layout: nil
      layout ||= layout_ || :default_8x8
      @initial_layout = layout.is_a?(Symbol) ? layouts[layout] : layout
      # p [:init, layout, initial_layout]
      setup
    end
  end
end
