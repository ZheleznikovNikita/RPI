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

ActiveRecord::Schema[8.1].define(version: 2026_10_16_090000) do
  create_table "adventures", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.string "status", default: "active", null: false
    t.integer "health", default: 100, null: false
    t.integer "stamina", default: 100, null: false
    t.text "summary", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_adventures_on_user_id"
    t.check_constraint "health BETWEEN 0 AND 100", name: "adventures_health_range"
    t.check_constraint "stamina BETWEEN 0 AND 100", name: "adventures_stamina_range"
    t.check_constraint "status IN ('active', 'completed')", name: "adventures_status"
  end

  create_table "story_turns", force: :cascade do |t|
    t.integer "adventure_id", null: false
    t.integer "position", null: false
    t.text "command", null: false
    t.json "response", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id", "position"], name: "index_story_turns_on_adventure_id_and_position", unique: true
    t.index ["adventure_id"], name: "index_story_turns_on_adventure_id"
    t.check_constraint "position > 0", name: "story_turns_position_positive"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "adventures", "users"
  add_foreign_key "story_turns", "adventures"
end
