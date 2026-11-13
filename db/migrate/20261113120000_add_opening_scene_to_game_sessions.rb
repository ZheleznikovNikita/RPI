class AddOpeningSceneToGameSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :game_sessions, :opening_scene, :text,
      null: false, default: "Дорога тонет в тёплом тумане. Впереди — старые ворота. Как вы поступите?"
  end
end
