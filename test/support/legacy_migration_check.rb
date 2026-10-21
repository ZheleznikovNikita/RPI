# Runs only against the disposable DATABASE_URL supplied by the migration test.
require Rails.root.join("db/migrate/20261008170000_create_users")
require Rails.root.join("db/migrate/20261016090000_create_adventures_and_story_turns")
require Rails.root.join("db/migrate/20261021120000_normalize_game_sessions")

raise "A disposable database is required" unless ENV.fetch("DATABASE_URL", "").include?("rpi-legacy-")

ActiveRecord::Migration.verbose = false
CreateUsers.new.migrate(:up)
CreateAdventuresAndStoryTurns.new.migrate(:up)

def legacy_records(table)
  Class.new(ActiveRecord::Base) { self.table_name = table }
end

def check(condition, message)
  raise message unless condition
end

users = legacy_records("users")
adventures = legacy_records("adventures")
turns = legacy_records("story_turns")
user = users.create!(name: "Legacy", email: "legacy@example.test", password_digest: "legacy-digest")
active = adventures.create!(user_id: user.id, title: "Старая игра", health: 80, stamina: 50, summary: "Последняя сохранённая память")
duplicate = adventures.create!(user_id: user.id, title: "Лишняя активная")

begin
  ActiveRecord::Base.transaction { NormalizeGameSessions.new.migrate(:up) }
  raise "Multiple active sessions were silently accepted"
rescue ActiveRecord::MigrationError
  check(ActiveRecord::Base.connection.table_exists?(:adventures), "Guard changed the legacy schema")
end
duplicate.destroy!

first_response = { "narration" => "Первый текст", "summary" => "Первая память", "extra" => { "weather" => "rain" } }
first = turns.create!(adventure_id: active.id, position: 1, command: "Идти", response: first_response)
last = turns.create!(adventure_id: active.id, position: 3, command: "Ждать", response: { "narration" => "Второй текст", "summary" => "Вторая память" })
finished = adventures.create!(user_id: user.id, title: "Завершённая", status: "completed", summary: "Начальная память без хода")
invalid = turns.create!(adventure_id: active.id, position: 4, command: "Некорректно", response: [])

begin
  ActiveRecord::Base.transaction { NormalizeGameSessions.new.migrate(:up) }
  raise "Invalid JSON was silently discarded"
rescue ActiveRecord::MigrationError
  connection = ActiveRecord::Base.connection
  connection.schema_cache.clear!
  check(connection.table_exists?(:adventures), "Failed import did not restore the legacy table")
  check(!connection.table_exists?(:game_sessions), "Failed import left a new schema behind")
  check(turns.count == 3, "Failed import changed the old turns")
end
invalid.destroy!

ActiveRecord::Base.transaction { NormalizeGameSessions.new.migrate(:up) }
ActiveRecord::Base.connection.schema_cache.clear!
game = GameSession.find(active.id)
check(game.user_id == user.id && game.health == 80 && game.stamina == 50, "Session state was lost")
check(game.player_actions.pluck(:position) == [ 1, 3 ], "Action ordering was changed")
check(game.story_turns.pluck(:id).sort == [ first.id, last.id ].sort, "Turn ids were lost")
check(game.ai_requests.order(:id).first.response_payload == first_response, "Raw response metadata was lost")
check(game.ai_requests.all? { |request| request.succeeded? && request.provider == "legacy" }, "Legacy requests are not traceable")
check(game.story_summaries.order(:version).pluck(:content) == [ "Первая память", "Вторая память", "Последняя сохранённая память" ], "Summary history was lost")
check(game.summary == "Последняя сохранённая память", "Current memory changed")
check(game.inventory.persisted?, "Inventory was not created")
completed = GameSession.find(finished.id)
check(completed.completed_at.present? && completed.summary == "Начальная память без хода", "Completed session memory was lost")
check(completed.latest_summary.player_action.nil?, "Initial memory acquired a fake action")
check(ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").empty?, "Broken foreign keys after import")
puts "LEGACY_MIGRATION_OK"
