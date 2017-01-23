module Chess
  class Board

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

    def location_of piece
      return :captured if captures.include? piece
      loc, _ = pieces.find {|loc, pc| pc == piece }
      loc
    end

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

    def follow_ray x, y, step_x, step_y
      loop do
        x += step_x
        y += step_y
        break unless x <= xsize && x >= 1 && y <= ysize && y >= 1
        yield x, y
      end
    end

    def available_moves_along_rays x, y, rays, maxlen: nil
      results = []
      rays.each {|step_x, step_y, maxlen| # A ray is sequentially checked until blocked
        count = 0 if maxlen
        follow_ray(x, y, step_x, step_y) {|tx, ty|
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

    # See if a move is allowed. Always checks basic plausibility, and defaults to doing a full check.
    def check mv, fully_legal: true
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

      check mv, fully_legal: fully_legal

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
    # FIXME Make this own_pieces - reverse the meaning
    def threatened_squares color = to_play, consider_enpassant: false # by color's enemy
      # p [:b_ts, halfmove_number, color, consider_enpassant]
      # squares = cache[[:threats, halfmove_number, color]] ||= begin
        squares = enemy_pieces(color).map {|pc| pc.threatened_squares }.inject(&:+) || []
        # squares.sort! # FIXME benchmark
      # end
      unless consider_enpassant
        squares = squares.reject {|x,y,type| :enpassant == type }.map {|x,y,type| [x, y] }
      end
      squares
    end

    def moves color = to_play, fully_legal: true # Fully-legal moves need to be evaluated to see if they cause inadvertent check
      # FIXME Cache fully and pseudo-legal moves. Use fully to supply partial, so avoid fetching twice.
      # cache[[:moves, halfmove_number, color]] ||= begin
        # p [:moves, :halfmove_number, halfmove_number, :color, color, :fully_legal, fully_legal]
        # caller.each {|c| break if c =~ /pry/ ; puts c }
        mvs = own_pieces(color).map {|pc| pc.moves }.inject(&:+) || []
        # mvs.sort_by! {|mv| [mv.src, mv.dest] } # FIXME slow
        mvs
        # p [:moves2, fully_legal]
        return mvs unless fully_legal
        mvs.reject {|mv| dup.move(mv, fully_legal: false).check?(color) } # not 'fully-legal'. Check for check isn't endlessly recursive
      # end
    end

    # TODO output and parse FEN and X-FEN :
    # https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation
    # https://en.wikipedia.org/wiki/X-FEN

    def transcript
      move_pairs = history.each_slice(2).each_with_index.to_a
      move_pairs << [[],0] if move_pairs.empty?
      move_pairs.map {|(m1, m2),i| "#{i + 1}. #{m1}#{" #{m2}" if m2}" }.join(' ') + " #{status_text}"
    end

    def self.parse_pgn_header line
      md = line.match(/^\[(?<key>\w+)\s+"(?<value>.*)"\]$/)
      raise "Malformed header: '#{line}'" unless md
      [md[:key], md[:value]]
    end

    def self.parse_fen str
      layout, to_play, castling_rights, enpassant, halfmove_clock, move_number = str.split(/\s+/)
      [layout, to_play, castling_rights, enpassant, halfmove_clock, move_number]
    end

    def self.parse_transcript transcript
      raise "Not a valid transcript" unless transcript =~ /^\s*1\./
      move_pairs = transcript.split("\n").join(' ').gsub(/\s\s+/,' ').split(/\s*\d+\.\s*/).reject(&:empty?)
      moves = move_pairs.map {|pair| pair.split(/\s+/) }.flatten.map(&:strip)
      moves.pop if moves.last =~ /\d-\d|\*/
      moves
    end

    def self.parse_pgn str
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
      score = pgn[/\S+$/]
      moves = parse_transcript pgn
      layout, to_play, castling_rights, enpassant, halfmove_clock, move_number = parse_fen headers['FEN'] if '1' == headers['SetUp']

      [headers, layout, moves, to_play, castling_rights, enpassant, halfmove_clock, move_number, score]
    end

    # FEN is in the FEN header, SetUp header must also appear and be '1'
    # https://en.wikipedia.org/wiki/Chess_notation#Notation_systems_for_computers
    def self.load_pgn str
      headers, layout, moves, to_play, castling_rights, enpassant, halfmove_clock, move_number, score = parse_pgn str
      # p [headers, layout, moves, to_play, castling_rights, enpassant, halfmove_clock, halfmove_number, score]
      $b = board = new layout
      moves.each {|mv| board.display ; p [:lpgn, mv] ; board.do_pgn_move mv }
      board
    end

    def find_piece type, dest, disambiguator = ''
      pcs = own_pieces.select {|pc| pc.type == type && pc.can_move_to(*dest) }
      raise "Couldn't find a #{to_play} #{type}#{" on #{disambiguator}" unless disambiguator.empty?} capable of reaching #{Chess.locstr dest}" if pcs.empty?

      if pcs.length == 1
        pc = pcs.first
      else
        raise "Ambiguous move text - could refer to one of #{pcs.length} pieces" unless disambiguator && !disambiguator.empty?
        tx, ty = disambiguator.split(//) if disambiguator
        ty, tx = tx, nil if tx =~ /^\d+$/
        tx = Chess.letter_to_file tx if tx
        ty = ty.to_i if ty
        pcs.select! {|pc|
          if tx && ty
            pc.x == tx && pc.y == ty
          else
            pc.x == tx || pc.y == ty
          end
        }
        raise "Disambiguator incorrect - no candidates" if pcs.empty?
        raise "Disambiguator not sufficient - left with #{pcs}" unless pcs.length == 1
        pc = pcs.first
      end
    end

    # Takes a move string eg: 'Qxb6', decodes it, finds the piece, and performs the move if legal
    def do_pgn_move pgn
      types = {'K' => :king, 'Q' => :queen, 'R' => :rook, 'B' => :bishop, 'N' => :knight, '' => :pawn}
      type, disambiguator, capture, file, rank, new_type, check, checkmate, castling = parse_pgn_move pgn

      x = Chess.letter_to_file file
      y = rank.to_i
      dest = [x, y]

      pc = find_piece types[type], dest, disambiguator
      mv = pc.moves.find {|m| next unless m.castling? if castling ; m.dest == dest }
      move mv
    end

    # Must be done on the instance, as it relies on context
    # returns the src_loc and dest_loc
    def parse_pgn_move pgn
      color = to_play
      last_rank = :white == color ? 1 : ysize
      queenside_file, kingside_file = 'c', 'g'
      type, disambiguator, capture, file, rank, castling, rest = nil
      type_p          = '([KQRBNP]|)' # The 'P' is unusual but not wrong
      disambiguator_p = '([a-l]?\d*)'
      capture_p       = '(x)'
      file_p          = '([a-l])'
      rank_p          = '(\d+)'
      rest_p          = '(.+)'
      pattern = /^#{type_p}#{disambiguator_p}?#{capture_p}?#{file_p}#{rank_p}#{rest_p}?$/

      case pgn
      when /O-O-O/ ; type, file, rank, castling = 'K', queenside_file, last_rank, true
      when /O-O/   ; type, file, rank, castling = 'K',  kingside_file, last_rank, true
      when /.\d/   ; type, disambiguator, capture, file, rank, rest = pgn.match(pattern).captures
      else         ; raise "Unknown move #{pgn}"
      end
      type ||= 'P'
      new_type, _ = rest.match(/=(.)/).captures if rest =~ /=/
      check       = !!(rest =~ /\+/)
      checkmate   = !!(rest =~ /#/)

      [type, disambiguator, capture, file, rank, new_type, check, checkmate, castling]
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

    def to_fen_layout
      ysize.downto(1).map {|y|
        1.upto(xsize).map {|x|
          pc = at(x,y)
          pc ? pc.to_fen : '.'
        }.join
      }.join('/').gsub(/\.+/) {|s| s.length.to_s }
    end

    def castling_text
      t = "#{(king(:white)&.to_pgn || '') + (king(:black)&.to_pgn || '')}"
      t.empty? ? '-' : t
    end

    def enpassant_availability
      enemy_pawn = enemy_pieces.select {|pc| :pawn == pc.type }.find {|pc| pc.can_be_captured_enpassant }
      return '-' unless enemy_pawn && own_pieces.select {|pc| :pawn == pc.type }.find {|pc| pc.moves.any? {|mv| mv.capture? && mv.capture_location == enemy_pawn.location } }
      Chess.locstr(enemy_pawn.location)[0]
    end

    def to_fen
      "#{to_fen_layout} " +
      "#{:white == to_play ? 'w' : 'b'} " +
      "#{castling_text} " +
      "#{enpassant_availability} " +
      "#{halfmove_number - draw_clock} " +
      "#{(halfmove_number + 1).div(2)}"
    end

    # X-FEN https://en.wikipedia.org/wiki/X-FEN
    def to_pgn
      stock_layout = layouts[:default_8x8] == initial_layout
      headers = {
         Event: 'unnamed',
          Site: `hostname`.strip,
          Date: Time.now.strftime('%Y.%m.%d'),
         Round: 1,
         White: 'Computer',
         Black: 'Computer',
        Result: status_text,
      }
      if !stock_layout
        headers['SetUp'] = 1
        headers['FEN'] = initial_fen
      end
      headers['CurrentFEN'] = to_fen unless 1 == halfmove_number # Don't show the initial layout again
      (headers.map {|k,v| "[#{k} \"#{v}\"]" } + [transcript]).join("\n")
    end

    def parse_fen_layout fen ; fen.split('/').map {|line| line.gsub(/\d+/) {|n| '.' * n.to_i }.split(//) } end

    def self.layouts
      {
          empty_8x8: '8/8/8/8/8/8/8/8',
        default_8x8: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
      }
    end
    def layouts ; self.class.layouts end

    # Note: Because castling rights default to true, this returns the INVERSE of the specified rights - to be disabled
    def self.parse_castling_rights str
      raise "Improper castling rights '#{str}'" unless str =~ /^([kq]{1,4}|-)$/i
      syms = {'Q' => [:white, :left],
              'K' => [:white, :right],
              'q' => [:black, :left],
              'k' => [:black, :right]}
      all = syms.values
      return all if '-' == str
      indicated_rights = str.scan(/./).map {|c| syms[c] }
      all - indicated_rights
    end
    def parse_castling_rights str ; self.class.parse_castling_rights str end

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

    # If there is a king, is it in check? This is to allow simplified test scenarios with one side being incomplete.
    def check? color = to_play ; k = king color ; threatened_squares(color).include? k.location if k end

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

    attr_reader :xsize, :ysize, :captures, :halfmove_number, :initial_layout, :initial_fen, :draw_clock, :history, :states

    # Takes a layout name, or a FEN layout, or a complete X-FEN string
    def initialize layout_ = nil, layout: nil
      layout ||= layout_ || :default_8x8
      @initial_layout = layout.is_a?(Symbol) ? layouts[layout] : layout
      setup
      @initial_fen = to_fen
    end
  end
end
