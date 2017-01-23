#!/usr/bin/env ruby

require 'pry'

$LOAD_PATH << File.expand_path('.')

require 'board'
require 'piece'
require 'action'
require 'game'
require 'ai'

# For now, also just reload them each time
load 'board.rb'
load 'piece.rb'
load 'action.rb'
load 'game.rb'
load 'ai.rb'

module Chess
  def self.letter_to_file l ; l.to_i(36) - 9 end
  def self.file_to_letter n ; (n + 9).to_s(36) end
  def self.xy_to_algebraic x, y ; [file_to_letter(x), y] end
  def self.locstr loc ; xy_to_algebraic(*loc).join end

  def self.cli
    binding.pry
  end
end

Chess.cli if __FILE__ == $0
