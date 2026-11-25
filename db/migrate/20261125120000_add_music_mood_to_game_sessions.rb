class AddMusicMoodToGameSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :game_sessions, :music_mood, :string, null: false, default: "calm"
    add_column :game_sessions, :music_mood_changed_at, :datetime
    add_check_constraint :game_sessions, "music_mood IN ('calm', 'battle', 'tension', 'mystery', 'sad', 'victory')", name: "game_music_mood"
  end
end
