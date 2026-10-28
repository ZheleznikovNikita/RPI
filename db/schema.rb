# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_28_130000) do
  create_table "ai_requests", force: :cascade do |t|
    t.integer "player_action_id", null: false
    t.string "purpose", null: false
    t.string "provider", null: false
    t.string "model_identifier", null: false
    t.string "status", default: "pending", null: false
    t.json "request_payload", null: false
    t.json "response_payload"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["player_action_id", "purpose"], name: "one_active_ai_request_per_purpose", unique: true, where: "status IN ('pending', 'running')"
    t.index ["player_action_id"], name: "index_ai_requests_on_player_action_id"
    t.check_constraint "purpose IN ('narration', 'summary', 'image')", name: "ai_requests_purpose"
    t.check_constraint "status IN ('pending', 'running', 'succeeded', 'failed')", name: "ai_requests_status"
  end

  create_table "game_sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.string "status", default: "active", null: false
    t.integer "health", default: 100, null: false
    t.integer "stamina", default: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.index ["user_id"], name: "index_game_sessions_on_user_id"
    t.index ["user_id"], name: "one_active_game_session_per_user", unique: true, where: "status = 'active'"
    t.check_constraint "health BETWEEN 0 AND 100", name: "adventures_health_range"
    t.check_constraint "stamina BETWEEN 0 AND 100", name: "adventures_stamina_range"
    t.check_constraint "status IN ('active', 'completed')", name: "adventures_status"
  end

  create_table "inventories", force: :cascade do |t|
    t.integer "game_session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_session_id"], name: "index_inventories_on_game_session_id", unique: true
  end

  create_table "inventory_items", force: :cascade do |t|
    t.integer "inventory_id", null: false
    t.string "code", null: false
    t.string "name", null: false
    t.text "description", default: "", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "code"], name: "index_inventory_items_on_inventory_id_and_code", unique: true
    t.index ["inventory_id"], name: "index_inventory_items_on_inventory_id"
    t.check_constraint "quantity BETWEEN 1 AND 1000000", name: "inventory_items_quantity_range"
  end

  create_table "player_actions", force: :cascade do |t|
    t.integer "game_session_id", null: false
    t.integer "position", null: false
    t.text "command", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_session_id", "position"], name: "index_player_actions_on_game_session_id_and_position", unique: true
    t.index ["game_session_id"], name: "index_player_actions_on_game_session_id"
    t.index ["game_session_id"], name: "one_pending_action_per_session", unique: true, where: "status = 'pending'"
    t.check_constraint "position > 0", name: "player_actions_position_positive"
    t.check_constraint "status IN ('pending', 'completed', 'cancelled')", name: "player_actions_status"
  end

  create_table "story_summaries", force: :cascade do |t|
    t.integer "game_session_id", null: false
    t.integer "version", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "through_position", default: 0, null: false
    t.index ["game_session_id", "version"], name: "index_story_summaries_on_game_session_id_and_version", unique: true
    t.index ["game_session_id"], name: "index_story_summaries_on_game_session_id"
    t.check_constraint "through_position >= 0", name: "story_summaries_through_position_nonnegative"
    t.check_constraint "version > 0", name: "story_summaries_version_positive"
  end

  create_table "story_turns", force: :cascade do |t|
    t.integer "ai_request_id", null: false
    t.text "narration", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_request_id"], name: "index_story_turns_on_ai_request_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "ai_requests", "player_actions"
  add_foreign_key "game_sessions", "users"
  add_foreign_key "inventories", "game_sessions"
  add_foreign_key "inventory_items", "inventories"
  add_foreign_key "player_actions", "game_sessions"
  add_foreign_key "story_summaries", "game_sessions"
  add_foreign_key "story_turns", "ai_requests"
end
