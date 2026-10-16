class CreateAdventuresAndStoryTurns < ActiveRecord::Migration[8.1]
  def change
    create_table :adventures do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false, default: "active"
      t.integer :health, null: false, default: 100
      t.integer :stamina, null: false, default: 100
      t.text :summary, null: false, default: ""
      t.timestamps
      t.check_constraint "health BETWEEN 0 AND 100", name: "adventures_health_range"
      t.check_constraint "stamina BETWEEN 0 AND 100", name: "adventures_stamina_range"
      t.check_constraint "status IN ('active', 'completed')", name: "adventures_status"
    end

    create_table :story_turns do |t|
      t.references :adventure, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :command, null: false
      t.json :response, null: false
      t.timestamps
      t.check_constraint "position > 0", name: "story_turns_position_positive"
    end
    add_index :story_turns, [ :adventure_id, :position ], unique: true
  end
end
