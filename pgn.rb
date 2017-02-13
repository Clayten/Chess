module Chess
  class Board
    # https://en.wikipedia.org/wiki/Chess_notation#Notation_systems_for_computers
    # https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation
    # https://en.wikipedia.org/wiki/X-FEN

    private

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
      strs = str.split(/\r?\n/).map(&:strip).reject(&:empty?).compact
      strs.each {|line|
        if line =~ /^\[.*\]$/
          k, v = parse_pgn_header line ; headers[k] = v
        else
          pgns << line
        end
      }
      pgn = pgns.join(' ')
      pgn = pgn.gsub(/{[^}]*}/,'').strip # remove comments
      pgn = pgn.gsub(/\d+\. \.{3}/,'') # 1. e4 {foo} 1. ... e5
      pgn = pgn.gsub(/\s{2,}/,' ')
      score = pgn[/(?<=\s)[-012*\/]+$/] || headers['Result']
      moves = parse_transcript pgn
      layout, to_play, castling_rights, enpassant, halfmove_clock, move_number = parse_fen headers['FEN'] if '1' == headers['SetUp']

      [headers, layout, moves, to_play, castling_rights, enpassant, halfmove_clock, move_number, score]
    end

    # included in pgn.rb because it's central to parsing notation
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
      when /[a-l]\d/ ; type, disambiguator, capture, file, rank, rest = pgn.match(pattern).captures
      else           ; raise "Unknown move #{pgn}"
      end
      type ||= 'P'
      new_type, _ = rest.match(/=(.)/).captures if rest =~ /=/
      check       = !!(rest =~ /\+/)
      checkmate   = !!(rest =~ /#/)
      # 'rest' also contains ? and ! markers, as part of annotation, which may be useful but are not currently used

      [type, disambiguator, capture, file, rank, new_type, check, checkmate, castling]
    end

    # Create move from pgn notation
    def create_pgn_move pgn
      types = {'K' => :king, 'Q' => :queen, 'R' => :rook, 'B' => :bishop, 'N' => :knight, '' => :pawn}
      type, disambiguator, capture, file, rank, new_type, check, checkmate, castling = parse_pgn_move pgn

      x = Chess.letter_to_file file
      y = rank.to_i
      dest = [x, y]

      pc = find_piece types[type], dest, disambiguator
      mv = pc.moves.find {|m| next unless m.castling? if castling ; m.dest == dest }
    end

    public

    def transcript
      move_pairs = history.each_slice(2).each_with_index.to_a
      move_pairs << [[],0] if move_pairs.empty?
      move_pairs.map {|(m1, m2),i| "#{i + 1}. #{m1}#{" #{m2}" if m2}" }.join(' ') + " #{status_text}"
    end

    def to_fen_layout
      ysize.downto(1).map {|y|
        1.upto(xsize).map {|x|
          pc = at(x,y)
          pc ? pc.to_fen : '.'
        }.join
      }.join('/').gsub(/\.+/) {|s| s.length.to_s }
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

    # TODO Load the player names and other headers
    def self.load_pgn str, interactive = false
      headers, layout, moves, to_play, castling_rights, enpassant, halfmove_clock, move_number, score = parse_pgn str
      $b = board = new layout
      moves.each {|mv| board.do_pgn_move mv ; next unless interactive ; puts "\n#{board.next_to_play} moved #{mv} - #{board.history.last.description}" ; board.display ; gets }
      board
    end

    # Takes a move string eg: 'Qxb6', decodes it, finds the piece, and performs the move if legal
    def do_pgn_move pgn ; move create_pgn_move pgn end


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

    def castling_text
      t = "#{(king(:white)&.to_pgn || '') + (king(:black)&.to_pgn || '')}"
      t.empty? ? '-' : t
    end

    def enpassant_availability
      enemy_pawn = enemy_pieces.select {|pc| :pawn == pc.type }.find {|pc| pc.can_be_captured_enpassant }
      return '-' unless enemy_pawn && own_pieces.select {|pc| :pawn == pc.type }.find {|pc| pc.moves.any? {|mv| mv.capture? && mv.capture_location == enemy_pawn.location } }
      Chess.locstr(enemy_pawn.location)[0]
    end

    def parse_fen_layout fen ; fen.split('/').map {|line| line.gsub(/\d+/) {|n| '.' * n.to_i }.split(//) } end

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




  end
end
