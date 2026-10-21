class NormalizeGameSessions < ActiveRecord::Migration[8.1]
  def up
    if connection.select_value("SELECT COUNT(*) FROM (SELECT user_id FROM adventures WHERE status = 'active' GROUP BY user_id HAVING COUNT(*) > 1)").to_i.positive?
      raise ActiveRecord::MigrationError, "У пользователя несколько активных приключений. Выберите активное перед миграцией."
    end

    rename_table :adventures, :game_sessions
    add_column :game_sessions, :completed_at, :datetime
    execute "UPDATE game_sessions SET completed_at = updated_at WHERE status = 'completed'"
    add_index :game_sessions, :user_id, unique: true, where: "status = 'active'", name: "one_active_game_session_per_user"

    create_table :inventories do |t|
      t.references :game_session, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end
    create_table :inventory_items do |t|
      t.references :inventory, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description, null: false, default: ""
      t.integer :quantity, null: false, default: 1
      t.timestamps
      t.check_constraint "quantity BETWEEN 1 AND 1000000", name: "inventory_items_quantity_range"
    end
    add_index :inventory_items, [ :inventory_id, :code ], unique: true

    create_table :player_actions do |t|
      t.references :game_session, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :command, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
      t.check_constraint "position > 0", name: "player_actions_position_positive"
      t.check_constraint "status IN ('pending', 'completed', 'cancelled')", name: "player_actions_status"
    end
    add_index :player_actions, [ :game_session_id, :position ], unique: true
    add_index :player_actions, :game_session_id, unique: true, where: "status = 'pending'", name: "one_pending_action_per_session"

    create_table :ai_requests do |t|
      t.references :player_action, null: false, foreign_key: true
      t.string :purpose, null: false
      t.string :provider, null: false
      t.string :model_identifier, null: false
      t.string :status, null: false, default: "pending"
      t.json :request_payload, null: false
      t.json :response_payload
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.check_constraint "purpose IN ('narration', 'summary', 'image')", name: "ai_requests_purpose"
      t.check_constraint "status IN ('pending', 'running', 'succeeded', 'failed')", name: "ai_requests_status"
    end
    add_index :ai_requests, [ :player_action_id, :purpose ], unique: true,
      where: "status IN ('pending', 'running')", name: "one_active_ai_request_per_purpose"

    create_table :story_entries do |t|
      t.references :player_action, null: false, foreign_key: true, index: { unique: true }
      t.references :ai_request, null: false, foreign_key: true, index: { unique: true }
      t.text :narration, null: false
      t.timestamps
    end
    create_table :story_summaries do |t|
      t.references :game_session, null: false, foreign_key: true
      t.references :player_action, foreign_key: true
      t.integer :version, null: false
      t.text :content, null: false
      t.timestamps
      t.check_constraint "version > 0", name: "story_summaries_version_positive"
    end
    add_index :story_summaries, [ :game_session_id, :version ], unique: true

    import_legacy_data
    drop_table :story_turns
    rename_table :story_entries, :story_turns
    remove_column :game_sessions, :summary
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Новая структура хранит данные, которых нет в старой схеме. Для отката восстановите резервную копию SQLite."
  end

  private

  # Migration-local records keep the import independent of future model changes.
  def records(table)
    Class.new(ActiveRecord::Base) { self.table_name = table }
  end

  def import_legacy_data
    sessions = records("game_sessions")
    turns = records("story_turns")
    inventories = records("inventories")
    actions = records("player_actions")
    requests = records("ai_requests")
    entries = records("story_entries")
    summaries = records("story_summaries")

    sessions.find_each do |session|
      inventories.create!(game_session_id: session.id, created_at: session.created_at, updated_at: session.updated_at)
      version = 0
      last_action = nil
      turns.where(adventure_id: session.id).order(:position).each do |turn|
        response = turn.response
        unless response.is_a?(Hash) && %w[narration summary].all? { |key| response[key].is_a?(String) && response[key].present? }
          raise ActiveRecord::MigrationError, "Некорректный JSON старого хода #{turn.id}. Данные не изменены."
        end
        timestamps = { created_at: turn.created_at, updated_at: turn.updated_at }
        last_action = actions.create!(game_session_id: session.id, position: turn.position, command: turn.command, status: "completed", **timestamps)
        request = requests.create!(player_action_id: last_action.id, purpose: "narration", provider: "legacy",
          model_identifier: "prototype", status: "succeeded", request_payload: { "command" => turn.command },
          response_payload: response, started_at: turn.created_at, finished_at: turn.updated_at, **timestamps)
        entries.create!(id: turn.id, player_action_id: last_action.id, ai_request_id: request.id, narration: response.fetch("narration"), **timestamps)
        version += 1
        summaries.create!(game_session_id: session.id, player_action_id: last_action.id, version: version, content: response.fetch("summary"), **timestamps)
      end

      if session.summary.present? && session.summary != summaries.where(game_session_id: session.id).order(version: :desc).first&.content
        summaries.create!(game_session_id: session.id, player_action_id: last_action&.id, version: version + 1,
          content: session.summary, created_at: session.updated_at, updated_at: session.updated_at)
      end
    end
  end
end
