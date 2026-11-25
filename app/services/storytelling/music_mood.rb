module Storytelling
  module MusicMood
    VALUES = %w[calm battle tension mystery sad victory].freeze
    VICTORY_SECONDS = 16

    def self.normalize(value, fallback: "calm")
      VALUES.include?(value) ? value : (VALUES.include?(fallback) ? fallback : "calm")
    end
  end
end
