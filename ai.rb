class Misc
  def self.graph cs, pre='base', l=0
    r = sl = l + (cs[:count] || 0)
    contents = []
    cs.each {|k,scs|
      next if :count == k
      w, content = graph scs,k,sl
      r += w
      contents << content
    }
    [(r-l), "<#{pre} l=#{l} #{contents.join ' '} r=#{r}>"]
  end
end

module Chess
  class AI
    def self.checkmate_score ; 100_000 end

    # The final static evaluator
    def self.rate_position board
      # p [:rating, board.to_play, board.history]
      # board.display
      values = {  king: 300, # This value isn't required to keep the king alive, it's for stength assessments
                 queen: 1200,
                  rook: 600,
                bishop: 410,
                knight: 400,
                  pawn: 100}

      # Basic strength from pieces
        own_piece_value =   board.own_pieces.map {|pc| values[pc.type] }.inject(&:+) || 0
      enemy_piece_value = board.enemy_pieces.map {|pc| values[pc.type] }.inject(&:+) || 0
      material_score = own_piece_value - enemy_piece_value

      # Options are good - counts useless moves too though
        own_moves = board.moves(fully_legal: false)
      enemy_moves = board.enemy_moves
      moves_score = (own_moves.length - enemy_moves.length) * 5

      # The enemy's threats toward the current player
      enemy_threat_count_score = enemy_threat_score = enemy_reinforcement_score = 0
      own_threatened_squares = board.threatened_squares
      own_threatened_squares.each {|x,y|
        enemy_threat_count_score += 3
        next unless pc = board.at(x, y)
        if board.to_play == pc.color
          enemy_threat_score += v = values[pc.type] * 0.3 # threatened
          # p [:friendly, pc.type, :threated_at, [x,y], :score, v]
        else
          enemy_reinforcement_score += v = values[pc.type] * 0.2 # reinforced
          # p [:enemy, pc.type, :reinforced_at, [x,y], :score, v]
        end
      }

      # The current player's threats and self-reinforcement
      own_threat_count_score = own_threat_score = own_reinforcement_score = 0
      enemy_threatened_squares = board.threatened_squares board.next_to_play
      enemy_threatened_squares.each {|x,y|
        own_threat_count_score += 3
        next unless pc = board.at(x, y)
        if board.to_play != pc.color
          own_threat_score += v = values[pc.type] * 0.3 # threatened
          # p [:enemy, pc.type, :threated_at, [x,y], :score, v]
        else
          own_reinforcement_score += v = values[pc.type] * 0.2 # reinforced
          # p [:friendly, pc.type, :reinforced_at, [x,y], :score, v]
        end
      }

      status_modifier = case board.status
      when :in_progress ; 0
      when :draw        ; 0
      when :stalemate   ; 0
      when :checkmate   ; (board.to_play == board.winner) ? checkmate_score : -checkmate_score
      end

      score = material_score + moves_score + status_modifier +
          own_threat_count_score +   own_threat_score +   own_reinforcement_score -
        enemy_threat_count_score - enemy_threat_score - enemy_reinforcement_score
      # p [:total_score, score, :material_score, material_score, :moves_score, moves_score, :checkmate, :status_modifier, status_modifier, :enemy_threat_count_score, enemy_threat_count_score, :enemy_threat_score, enemy_threat_score, :enemy_reinforcement_score, enemy_reinforcement_score, :own_threat_count_score, own_threat_count_score, :own_threat_score, own_threat_score, :own_reinforcement_score, own_reinforcement_score]

      score = score.to_i
    ensure
      # p [:score, score]
      score
    end

    # if depth_remaining, deduct one and try all available moves
    # if depth_remaining.zero? just evaluate

    # given a board, return the score of each available move

    # given a board and a move and a depth_remaining, return the score of that move either directly or recursively
    def self.score_move board, move, depth_remaining, analysis_depth = 0, resolve_only_captures = false
      p [:score_move, :move, move, :depth_remaining, depth_remaining, :ad, analysis_depth, :roc, resolve_only_captures]
      $b, $m = board, move
      depth_remaining = depth_remaining - 1 unless resolve_only_captures unless analysis_depth > 10
      analysis_depth += 1
      board = board.dup # FIXME use test_move - maybe rename
      board.move move
      # board.display if resolve_only_captures
      # gets if resolve_only_captures
      rating = if depth_remaining.zero?
        score = rate_position board
        # p [:move_score, board.transcript, score]
        score
      else
        moves = board.moves board.to_play, fully_legal: true # FIXME False?
        if moves.empty?
          # p [:no_more_moves, board.transcript]
          score = board.checkmate? ? -checkmate_score : 0
        else
          moves.select! {|mv| mv.capture? } if resolve_only_captures
          if moves.empty?
            score = rate_position board
          else
            # puts :moves, moves.map(&:inspect) if resolve_only_captures
            scores = moves.map {|mv|
              start_resolving_only_captures = (1 == depth_remaining && (mv.check? || mv.capture?)) # checks and captures
              p [:started_deepening_search_while_analyzing, mv, :check?, mv.check?, :capture?, mv.capture?] if start_resolving_only_captures
              score_move board, mv, depth_remaining, analysis_depth, (resolve_only_captures || start_resolving_only_captures)
            }
            # p [:move_scores, board.transcript, scores, :max, scores.max]
            scores.max
          end
        end
      end
      -rating # negative, because this is the rating of the next player, after the move was made
    end

    # We don't worry about fully-legal moves because we're testing them anyways.
    def self.score_moves board, depth
      # p [:score_moves, depth]
      rated_moves = board.moves(board.to_play, fully_legal: true).map {|move| rating = score_move board, move, depth ; [move, rating] }
    end

    # given a board, return the best move available
    def self.find_move board, depth = 1
      rated_moves = score_moves(board, depth)
      best_rating = rated_moves.map {|mv, rating| rating }.max

      # p [:sorted_moves, rated_moves.sort_by {|_,r| r }]

      best_moves = rated_moves.select {|mv, rating| rating == best_rating }
      mv, rating = best_moves.sample
      mv
    end
  end

end
