module Chess
  class Board

    attr_reader :states

    # Hash state, store, check for triplicates - draw
    def states ; @states ||= [] end

    def distinct_state ; "<#{self.class.name} #{xsize}x#{ysize} #{pieces.map {|(x,y),pc| "(#{pc.color} #{pc.type}-#{x},#{y}-#{pc.moved?})" }.join(', ')}#{" - cap #{captures.map {|pc| "#{pc.type}" }.join(',')}" unless captures.empty?}>" end

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

    def location_of piece
      return :captured if captures.include? piece
      loc, _ = pieces.find {|loc, pc| pc == piece }
      loc
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

    def next_to_play ; Piece.other_color to_play end

    def to_play ; Piece.colors[halfmove_number % 2] end

    def check?
      moves(next_to_play, true).each {|mv|
        return true if mv.captured_type && :king == mv.captured_type
      }
      false
    end

    # These methods return a list of legal moves of a given type, from a location, for a color

    # Just checks for the king's ability to castle
    def castling src
      results = []
      x, y = src_loc = src.location
      return results if caller.any? {|c| c =~ /castling/ } # avoid recursion in checking for check across intermediate squares
      raise "Not a king" unless :king == src.type
      return results if src.moved?
      return results unless 8 == xsize && 8 == ysize # So far, we only castle on regulation boards
      opponent_moves = moves next_to_play, true
      locations_in_check = opponent_moves.map {|mv| mv.dest }.sort.uniq
      return results if locations_in_check.include? src_loc # Is the king in check to start with?
      [1, xsize].each {|rx|
        rook_loc = [rx, y]
        rook = pieces[rook_loc]
        next if !rook || rook.moved?
        intermediate_squares = (([rx, x].min + 1)...[rx, x].max).to_a
        next if intermediate_squares.any? {|ix|
          intermediate_loc = [ix, y]
          next true if pieces[intermediate_loc]
          next true if locations_in_check.include? intermediate_loc
        }
        # which way are we castling?
         dx = 8 == rx ? 7 : 3 # destination file for king
        rdx = 8 == rx ? 6 : 4 # for rook
        dest_loc = [dx, y]
        rook_dest_loc = [rdx, y]
        results << src.move(dest: dest_loc, src2: rook_loc, dest2: rook_dest_loc)
      }
      results
    end

    # Surrounding squares
    def adjacent_squares src
      results = []
      x, y = src_loc = src.location
      (x - 1).upto(x + 1).each {|tx|
        (y - 1).upto(y + 1).each {|ty|
          next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
          next if x == tx && y == ty
          dest_loc = [tx, ty]
          if dest = pieces[dest_loc]
            next if dest.color == src.color
            results << src.move(dest: dest_loc)
          else
            results << src.move(dest: dest_loc)
          end
        }
      }
      results
    end

    # Outward along cardinal (N/S, E/W) lines - ranks and files
    def cardinal_lines src
      results = []
      x, y = src_loc = src.location
      xrays = [(x - 1).downto(1), (x + 1).upto(xsize)].map(&:to_a).map {|xs| xs.zip([y] * xs.length) }
      yrays = [(y - 1).downto(1), (y + 1).upto(ysize)].map(&:to_a).map {|ys| ([x] *ys.length).zip ys }
      rays = xrays + yrays
      rays.each {|ray|
        ray.each {|tx,ty|
          dest_loc = [tx, ty]
          if dest = pieces[dest_loc]
            break if dest.color == src.color
            results << src.move(dest: dest_loc)
            break
          else
            results << src.move(dest: dest_loc)
          end
        }
      }
      results
    end

    # Outward along diagonal lines
    def diagonal_lines src
      results = []
      x, y = src_loc = src.location
      tdrays = [(x - 1).downto(1).to_a.zip((y - 1).downto(1).to_a), (x + 1).upto(xsize).to_a.zip((y + 1).upto(ysize).to_a)]
      burays = [(x - 1).downto(1).to_a.zip((y + 1).upto(ysize).to_a), (x + 1).upto(xsize).to_a.zip((y - 1).downto(1).to_a)]
      rays = tdrays + burays
      rays.each {|ray|
        ray.each {|tx,ty|
          next unless tx && ty
          dest_loc = [tx, ty]
          if dest = pieces[dest_loc]
            break if dest.color == src.color
            results << src.move(dest: dest_loc)
            break
          else
            results << src.move(dest: dest_loc)
          end
        }
      }
      results
    end

    # Two and one, or one and two, away in all directions
    def knight_moves src
      results = []
      x, y = src_loc = src.location
      offsets = [[-1, -2], [-2, -1], [1, -2], [2, -1], [-1, 2], [-2, 1], [1, 2], [2, 1]]
      offsets.each {|ox,oy|
        tx, ty = (x + ox), (y + oy)
        next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
        dest_loc = [tx, ty]
        if dest = pieces[dest_loc]
          next if dest.color == src.color
          results << src.move(dest: dest_loc)
        else
          results << src.move(dest: dest_loc)
        end
      }
      results
    end

    # Foward, attacking to the sides, and capturing en-passant
    # Here color is more functional, white advances towards black, etc
    def pawn_moves src
      results = []
      x, y = src_loc = src.location
      offset_y = :white == src.color ? 1     : -1 # which direction are we checking?
      # moving
      steps = !src.last_move ? 2 : 1 # we can step 1 or 2 if we haven't moved before
      y1, y2 = [(y + offset_y), (y + offset_y * steps)].sort
      y1.upto(y2).each {|ty|
        next if x < 1 || x > xsize || ty < 1 || ty > ysize
        dest_loc = [x, ty]
        break if dest = pieces[dest_loc]
        results << src.move(dest: dest_loc)
      }
      # capturing
      ty = y + offset_y
      [x - 1, x + 1].each {|tx|
        next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
        dest_loc = [tx, ty]
        next unless dest = pieces[dest_loc]
        next if dest.color == src.color
        results << src.move(dest: dest_loc)
      }
      # capturing en passant
      [-1, 1].each {|offset_x|
        tx = x + offset_x
        ty = y + offset_y
        en_passant_rank = (:white == src.color) ? (ysize.div(2)+1) : ysize.div(2)
        # p [src.color, src.type, src.location, tx, ty]
        next if tx < 1 || tx > xsize
        next unless en_passant_rank == y
        dest_loc = [tx, ty]
        capture_loc = [tx, y]
        next unless capture = pieces[capture_loc]
        next unless :pawn == capture.type
        next if capture.color == src.color # technically we know this doesn't happen because of the rank and the move limitation, but...
        next unless 1 == capture.number_of_moves # We can only capture en-passant if it's the enemy's first move (If they're on their fourth rank, they did it as a double move)
        next unless halfmove_number == (capture.last_move + 1) # We can only capture en-passant directly after the enemy moves
        results << src.move(dest: dest_loc, capture_location: capture_loc)
      }
      results
    end

    # TODO break out list of possible squares to move into, to iterate over for legal moves, and to properly display A pawn can't, and THIS pawn can't...
    # The issue is that some moves are complex to generate (castling), or can only happen if a certain square is occupied (en-passant.)
    # I'd like a list of squares-in-check-by-enemy, to help score the board, and squares-in-check-by-self...
    # I want to know my pawn will be at risk if I move it two squares, but the pawn sitting in position to capture en-passant doesn't place that square in check until after I move.
    # I'm not looking to know if a piece will remain safe, that's an issue for recursive checking, but to see if a piece will be safe where placed, for this turn.

    # Not for normal use, might leave board in illegal condition
    # NOTE Not incrementing turn #, etc. We can test our position for own-check this way
    def force_move src_loc, dest_loc, src2_loc = nil, dest2_loc = nil
      pieces[dest_loc]  = pieces.delete  src_loc # BAM, it's done. But it may not be legal
      pieces[dest2_loc] = pieces.delete src2_loc if src2_loc # Move the secondary piece if there is one
      self
    end

    def mutate
      pcs, caps = pieces.dup, captures.dup
      @pieces, @captures = {}, []
      pcs.each  {|k,v| v = v.dup ; pieces[k]  = v ; v.board = self }
      caps.each {|  v| v = v.dup ; captures  << v ; v.board = self }
      self
    end

    def dup
      super.mutate
    end

    # iterates over all pieces, returns all moves
    def moves color = to_play, dont_check_check = false
      mvs = pieces.values.select {|pc|
        pc.color == color
      }.map {|pc|
        mvs = pc.moves
        next if mvs.empty?
        mvs
      }.compact.inject(&:+)
      mvs ||= []
      return mvs if dont_check_check
      # Now weed out moves that result in check
      mvs.select {|mv| !test_move(mv).check? } # This is once-recursive. It doesn't consider check next time
    end

    def checkmate?
      moves.empty? && check?
    end

    def stalemate?
      moves.empty? && !check?
    end

    def check mv
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

    def triple_repeat_draw
      3 == states.select {|h| h == states.last }.length
    end

    def status
      # Can't return draw
      if checkmate?
        :checkmate
      elsif stalemate?
        :stalemate
      else
        :in_progress
      end
    end

    # TODO Make status :checkmate if check && no moves, statemate if no moves, OR in_progress. Get rid of instance_var draw is a state of the game, not the board, as is resignation

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
      @draw_clock = halfmove_number if true # FIXME Eligible only
      # TODO set @status
      # TODO set check/checkmate on mv, if appropriate
      if check?
        if moves.empty?
          mv.checkmate = true
        else
          mv.check = true
        end
      end
      true
    end

    def add_piece x, y, color, type
      # p [:add_piece, x, y, color, type]
      loc = [x, y]
      raise "There's already a #{pieces[loc]} at #{loc.join(',')}" if pieces[loc]
      pieces[loc] = Piece.create color, type, self
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

    def checkmate ; :checkmate == status end
    def stalemate ; :stalemate == status end
    def winner ; next_to_play if checkmate end
    def loser  ;      to_play if checkmate end

    attr_reader :xsize, :ysize, :captures, :halfmove_number, :initial_layout, :draw_clock, :history
    def initialize layout: nil
      layout ||= :default_8x8
      @initial_layout = layout.is_a?(Symbol) ? layouts[layout] : layout
      # p [:init, layout, initial_layout]
      setup
    end
  end
end
