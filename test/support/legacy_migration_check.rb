# Runs only against the disposable DATABASE_URL supplied by the migration test.
require Rails.root.join("db/migrate/20261008170000_create_users")
require Rails.root.join("db/migrate/20261016090000_create_adventures_and_story_turns")
require Rails.root.join("db/migrate/20261021120000_normalize_game_sessions")
require Rails.root.join("db/migrate/20261028130000_remove_story_relationship_cycles")

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
ActiveRecord::Base.connection.clear_cache!

actions = legacy_records("player_actions")
entries = legacy_records("story_turns")
summaries = legacy_records("story_summaries")
original_turns = entries.order(:id).map(&:attributes)
original_summaries = summaries.order(:id).map(&:attributes)
foreign_action = actions.create!(game_session_id: finished.id, position: 1, command: "Чужое действие", status: "completed")

# Both old triangles allow contradictory ownership through direct SQL. Refuse to
# remove a redundant reference until its value agrees with the surviving path.
entry = entries.find(first.id)
original_action_id = entry.player_action_id
entry.update_columns(player_action_id: foreign_action.id)
begin
  ActiveRecord::Base.transaction { RemoveStoryRelationshipCycles.new.migrate(:up) }
  raise "Conflicting turn ownership was silently discarded"
rescue ActiveRecord::MigrationError
  check(ActiveRecord::Base.connection.column_exists?(:story_turns, :player_action_id), "Guard changed the turn schema")
  check(!ActiveRecord::Base.connection.column_exists?(:story_summaries, :through_position), "Guard changed summary columns")
end
entry.update_columns(player_action_id: original_action_id)

memory = summaries.where(game_session_id: active.id).first
original_source_id = memory.player_action_id
memory.update_columns(player_action_id: foreign_action.id)
begin
  ActiveRecord::Base.transaction { RemoveStoryRelationshipCycles.new.migrate(:up) }
  raise "Conflicting summary ownership was silently discarded"
rescue ActiveRecord::MigrationError
  check(ActiveRecord::Base.connection.column_exists?(:story_summaries, :player_action_id), "Guard changed the summary schema")
end
memory.update_columns(player_action_id: original_source_id)
foreign_action.destroy!

ActiveRecord::Base.transaction { RemoveStoryRelationshipCycles.new.migrate(:up) }
ActiveRecord::Base.connection.schema_cache.clear!
ActiveRecord::Base.connection.clear_cache!
check(!ActiveRecord::Base.connection.column_exists?(:story_turns, :player_action_id), "Turn still has a direct action reference")
check(!ActiveRecord::Base.connection.column_exists?(:story_summaries, :player_action_id), "Summary still has an action reference")

# The reverse migration can reconstruct the removed references from the retained
# request ownership and the summary's session-local history boundary.
ActiveRecord::Base.transaction { RemoveStoryRelationshipCycles.new.migrate(:down) }
ActiveRecord::Base.connection.schema_cache.clear!
ActiveRecord::Base.connection.clear_cache!
restored_turns = legacy_records("story_turns").order(:id).map(&:attributes)
restored_summaries = legacy_records("story_summaries").order(:id).map(&:attributes)
check(restored_turns == original_turns, "Turn references were not restored: #{restored_turns.inspect} != #{original_turns.inspect}")
check(restored_summaries == original_summaries, "Summary references were not restored: #{restored_summaries.inspect} != #{original_summaries.inspect}")
ActiveRecord::Base.transaction { RemoveStoryRelationshipCycles.new.migrate(:up) }
ActiveRecord::Base.connection.schema_cache.clear!
ActiveRecord::Base.connection.clear_cache!

game = GameSession.find(active.id)
check(game.user_id == user.id && game.health == 80 && game.stamina == 50, "Session state was lost")
check(game.player_actions.pluck(:position) == [ 1, 3 ], "Action ordering was changed")
check(game.story_turns.pluck(:id).sort == [ first.id, last.id ].sort, "Turn ids were lost")
check(game.ai_requests.order(:id).first.response_payload == first_response, "Raw response metadata was lost")
check(game.ai_requests.all? { |request| request.succeeded? && request.provider == "legacy" }, "Legacy requests are not traceable")
check(game.story_summaries.order(:version).pluck(:content) == [ "Первая память", "Вторая память", "Последняя сохранённая память" ], "Summary history was lost")
check(game.story_summaries.order(:version).pluck(:through_position) == [ 1, 3, 3 ], "Summary coverage was lost")
check(game.summary == "Последняя сохранённая память", "Current memory changed")
check(game.inventory.persisted?, "Inventory was not created")
completed = GameSession.find(finished.id)
check(completed.completed_at.present? && completed.summary == "Начальная память без хода", "Completed session memory was lost")
check(completed.latest_summary.through_position.zero?, "Initial memory acquired a fake history boundary")
check(ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").empty?, "Broken foreign keys after import")
puts "LEGACY_MIGRATION_OK"
