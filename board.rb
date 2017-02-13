module Chess
  class Board

    private

    # FIXME debug
    def clr ; caller.reject {|l| l =~ /pry/ }.map {|s| s.split(/\//).last } end

    attr_reader :states

    # Generates a summary of all game state such that duplicate positions can be detected
    # Includes .moved? to indicate castling status, the color to play, and the enpassant file if any
    def distinct_state ; "<#{self.class.name} #{xsize}x#{ysize} #{pieces.sort_by {|(x,y),_| [x,y] }.map {|(x,y),pc| "(#{pc.color} #{pc.type}-#{x},#{y}-#{pc.moved?})" }.join(', ')}#{" - cap #{captures.map {|pc| "#{pc.type}" }.join(',')}" unless captures.empty?} enpassant #{enpassant_availability}>" end

    def state_hash ; Digest::SHA256.hexdigest distinct_state end

    # Does not update the 'initial_layout', or count as moves
    def add_piece x, y, color, type
      loc = [x, y].map(&:to_i)
      raise "There's already a #{pieces[loc]} at #{loc.join(',')}" if pieces[loc]
      cache.clear
      pieces[loc] = Piece.create color, type, self
    end

    def white_square ; "\u25a0" end
    def black_square ; "\u25a1" end
    def square color ; color == :white ? white_square : black_square end

    def color_at x, y
      (((x % 2) + (y % 2)) % 2).zero? ? :black : :white
    end

    def render overlay = {}, underlay = {}
      ysize.downto(1).map {|y|
        1.upto(xsize).map {|x|
          overlay[[x,y]] || pieces[[x,y]] || underlay[[x,y]] || square(color_at(x,y))
        }.join + " #{y}"
      }.join("\n") +
      "\n" + xsize.times.map {|i| (i + 10).to_s(36) }.join + "\n"
    end

    def follow_vector x, y, step_x, step_y
      loop do
        x += step_x
        y += step_y
        break unless x <= xsize && x >= 1 && y <= ysize && y >= 1
        yield x, y
      end
    end

    def arrowdir vec
      {[-1,0] => '←', [0,1] => '↑', [1,0] => '→', [0,-1] => '↓', [1,1] => '↗', [1,-1] => '↘', [-1,-1] => '↙', [-1,1] => '↖'}[vec]
    end

    public

    def color char, color = :red
      (@highline ||= HighLine.new).color char, color
    end

    def show_threatened_squares clr = to_play
      overlay = {}
      dot = "\u{2022}"
      threatened_squares(clr).uniq.each {|x,y|
        pc = at x, y
        next if pc && pc.color == clr # Don't show own pieces as threatened
        c = pc ? color(pc.to_s, :on_red) : color(dot)
        overlay[[x,y]] = c
      }
      display overlay
    end

    def display overlay = {}, underlay = {}
      last = history.last
      if underlay.empty? && last
        underlay = {}
        src, dest = last.src, last.dest
        dx, dy = dest.zip(src).map {|a,b| a - b }
        if !dx.zero? && !dy.zero? && dx.abs != dy.abs # Handle one leg of a knight move specially
          vec = dx.abs < dy.abs ? [dx, 0] : [0, dy] # Choose the short one
          underlay[src] = color arrowdir(vec), :red
          src = [src.first + vec.first, src.last + vec.last]
          dx, dy = dest.zip(src).map {|a,b| a - b }
        end
        stepx = dx.zero? ? 0 : dx / dx.abs
        stepy = dy.zero? ? 0 : dy / dy.abs
        ([dx.abs, dy.abs].max).times {
          underlay[src] = color arrowdir([stepx, stepy]), :red
          src = [src.first + stepx, src.last + stepy]
        }
        # underlay = {last.src => HighLine.new.color(arrowdir(last), :red)} # Does just the src square
      end
      puts render(overlay, underlay)
    end

    def available_moves_along_vectors x, y, vectors, maxlen: nil
      results = []
      vectors.each {|step_x, step_y, maxlen| # A vector is sequentially checked until blocked
        count = 0 if maxlen
        follow_vector(x, y, step_x, step_y) {|tx, ty|
          pc = at(tx, ty)
          results << [tx, ty]
          break if pc
          if maxlen
            count += 1
            break if count == maxlen
          end
        }
      }
      results
    end

    def mutate
      # p [:mutating, halfmove_number]
      pcs, caps = pieces.dup, captures.dup
      @history, @states = history.dup, states.dup
      @pieces, @captures = {}, []
      @cache = cache.dup
      pcs.each  {|k,v| v = v.dup ; pieces[k]  = v ; v.board = self }
      caps.each {|  v| v = v.dup ; captures  << v ; v.board = self }
      self
    end

    def dup
      super.mutate
    end

    # See if a move is allowed. Always checks basic plausibility, and defaults to doing a full check.
    def check mv, fully_legal: true
      # p [:check, halfmove_number, to_play, fully_legal, mv, clr[0...-11]]
      raise "Not a move '#{mv.inspect}'" unless mv.respond_to? :src
      raise "Game finished" unless :in_progress == status if fully_legal
      src_loc, dest_loc = mv.src, mv.dest
      src, dest = pieces[src_loc], pieces[dest_loc]
      raise "No piece at #{mv.src.join(',')}" unless src
      raise "It isn't #{src.color}'s turn" unless src.color == to_play
      raise "A #{src.type} can't move from #{mv.src.join(',')} to #{mv.dest.join(',')}" unless src.can_move_to(*dest_loc)
      raise "Move exposes king to check" if dup.move(mv, fully_legal: false).check?(mv.color) if fully_legal
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
    def move mv, fully_legal: true
      src_loc, dest_loc = mv.src, mv.dest
      src, dest = pieces[src_loc], pieces[dest_loc]

      check mv, fully_legal: fully_legal # if fully_legal # FIXME needs to always be called - however sometimes fails

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
      @halfmove_number += 1
      @draw_clock = halfmove_number if mv.captured_type || :pawn == mv.type # These things reset the 50-move draw-clock
      states << (hsh = state_hash) if fully_legal

      # Update the move, for transcription purposes, to note if it resulted in check or checkmate. This occurs as the next player
      mv.update self if fully_legal # No need to do all that checking if this is just an existence proof.
      self
    end

    # You need to know if your piece is vulnerable to enpassant
    def threatened_squares color = to_play, consider_enpassant: false
      squares = cache[[:threats, halfmove_number, color, consider_enpassant]] ||= begin
        # p [:b_ts, halfmove_number, color, consider_enpassant, clr]
        squares = own_pieces(color).map {|pc| pc.threatened_squares }.inject(&:+) || []
        squares = squares.reject {|x,y,type| :enpassant == type }.map {|x,y,type| [x, y] } unless consider_enpassant
        # squares.sort! # FIXME benchmark
      end
    end

    def moves color = to_play, fully_legal: true # Fully-legal moves need to be evaluated to see if they cause inadvertent check
      # FIXME Cache fully and pseudo-legal moves. Use fully to supply partial, so avoid fetching twice.
      cache[[:moves, halfmove_number, color, fully_legal]] ||= begin
        # p [:moves, :halfmove_number, halfmove_number, :color, color, :fully_legal, fully_legal, history.last]
        # caller.each {|c| break if c =~ /pry/ ; puts c }
        mvs = own_pieces(color).map {|pc| pc.moves }.inject(&:+) || []
        # mvs.sort_by! {|mv| [mv.src, mv.dest] } # FIXME slow
        mvs
        # p [:moves2, fully_legal]
        return mvs unless fully_legal # Don't cache because we aren't generating a proper answer
        mvs.reject {|mv| dup.move(mv, fully_legal: false).check?(color) } # not 'fully-legal'. Check for check isn't endlessly recursive
      end
    end

    def self.layouts
      {
          empty_8x8: '8/8/8/8/8/8/8/8',
        default_8x8: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
      }
    end
    def layouts ; self.class.layouts end

    def setup
      @pieces = {}
      @captures = []
      @history = []
      @states = []
      @cache = {}
      @halfmove_number = 1
      @draw_clock = halfmove_number

      types = {p: :pawn, k: :king, q: :queen, b: :bishop, n: :knight, r: :rook}

      fen_layout, fen_to_play, fen_castling_rights, fen_enpassant, fen_halfmove_clock, fen_move_number = self.class.parse_fen initial_layout
      layout = parse_fen_layout fen_layout

      @ysize = layout.length
      @xsize = layout.first.length

      layout.zip(ysize.downto(1).to_a).each {|pieces, y| # walk through by rank
        pieces.zip(1.upto(xsize).to_a) {|pc, x|          # and by file
          next unless type = types[pc.downcase.to_sym]
          color = (pc == pc.upcase) ? :white : :black
          add_piece x, y, color, type
        }
      }

      # If we were supplied with a full X-FEN string, handle all fields of it
      if fen_move_number # We either take just a layout, or all fields
        @halfmove_number = fen_move_number.to_i + ('w' == fen_to_play ? 0 : 1)
        @draw_clock = halfmove_number - fen_halfmove_clock.to_i
        raise "Incorrect draw clock" unless draw_clock > 0
        # Reads castling rights, which default to true, and disables them if they are NOT included in the line. 'KQk' -> disable black queenside castling
        parse_castling_rights(fen_castling_rights).each {|color, side| next unless k = king(color) ; side == :left ? k.disable_castle_left : k.disable_castle_right }
        if '-' != fen_enpassant
          pawn_rank = 'w' == to_play ? 5 : 4 # If it's white's turn, black's pawn must have just made a double-move, to 5...
          file = Chess.letter_to_file fen_enpassant
          pawn = at(file, pawn_rank)
          raise "No pawn vulnerable to enpassant" unless pawn
          raise "Incorrectly specified enpassant" if pawn.color == to_play
          pawn.moved # Tell this pawn it just moved
        end
      end

      self
    end

    # Returns true if the *current* state has happened two or more times before
    # You may call for draw at the beginning or end of your turn, but if you don't you lose the chance until it arises again
    def threefold_repetition?
      count = 0
      current_state = states.last
      states.reverse.each {|state|
        next unless current_state == state
        count += 1
        return true if 3 == count # break as soon as we find a third
      }
      false
    end

    def status
      if threefold_repetition?
        :draw # TODO Add draw as a move
      elsif checkmate?
        :checkmate
      elsif stalemate?
        :stalemate
      else
        :in_progress
      end
    end

    def location_of piece
      return :captured if captures.include? piece
      loc, _ = pieces.find {|loc, pc| pc == piece }
      loc
    end

    def at x, y = nil
      x, y = x if x.respond_to? :length
      pieces[[x,y]]
    end

    # If there is a king, is it in check? This is to allow simplified test scenarios with one side being incomplete.
    def check? color = to_play ; k = king color ; threatened_squares(other_color color).include? k.location if k end

    def checkmate? color = to_play ; moves(color).empty? && check?(color) end
    def stalemate? ; moves.empty? && !check?  end

    # direction of movement for a pawn
    def pawn_offset color ; :white == color ? 1 : -1 end

    def other_color c ; Piece.other_color c end
    def to_play ; Piece.colors[halfmove_number % 2] end
    def next_to_play ; other_color to_play end

    def enemy_pieces color = to_play ; pieces.values.select {|pc| pc.color != color } end
    def own_pieces   color = to_play ; pieces.values.select {|pc| pc.color == color } end

    def       king color = to_play ; pieces.values.find {|pc| pc.color == color && :king == pc.type } end
    def   own_king color = to_play      ; king color end
    def enemy_king color = next_to_play ; king color end
    def white_king ; king :white end
    def black_king ; king :black end
    def kings ; [white_king, black_king] end

    # We don't care if an enemy move exposes them to check because we'd be dead by then
    def enemy_moves ; moves(next_to_play, fully_legal: false) end

    def winner ; next_to_play if checkmate? end
    def loser  ;      to_play if checkmate? end

    def cache ; @cache ||= {} end

    def inspect
      "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{xsize}x#{ysize} - " +
      "#{pieces.length + captures.length} pieces - #{captures.length} captured>"
    end

    attr_reader :xsize, :ysize, :captures, :halfmove_number, :initial_layout, :initial_fen, :draw_clock, :history, :states, :pieces

    # Takes a layout name, or a FEN layout, or a complete X-FEN string
    def initialize layout_ = nil, layout: nil
      layout ||= layout_ || :default_8x8
      @initial_layout = layout.is_a?(Symbol) ? layouts[layout] : layout
      setup
      @initial_fen = to_fen
    end
  end
end
