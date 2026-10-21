require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attributes)
    User.new({ name: "Странник", email: "player@example.com", password: "Lantern!Orbit7Cedar", password_confirmation: "Lantern!Orbit7Cedar" }.merge(attributes))
  end

  # Identity and validation
  test "normalizes email and rejects case insensitive duplicates" do
    user = build_user(email: " Player@Example.COM ")
    user.save!
    assert_equal "player@example.com", user.reload.email
    duplicate = build_user
    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "requires name and valid email" do
    user = build_user(name: " ", email: "broken")
    assert_not user.valid?
    assert user.errors[:name].any?
    assert user.errors[:email].any?
  end

  # Password policy and authentication
  test "stores only a digest and authenticates after reload" do
    user = build_user
    user.save!
    assert_not_equal "Lantern!Orbit7Cedar", user.password_digest
    assert user.reload.authenticate("Lantern!Orbit7Cedar")
    assert_not user.authenticate("wrong")
  end

  test "rejects missing short predictable and oversized passwords" do
    [ nil, "short", "password123456", "я" * 37 ].each do |password|
      user = build_user(password: password, password_confirmation: password)
      assert_not user.valid?, "Expected password to be rejected"
      assert user.errors[:password].any?
    end
  end

  test "requires matching confirmation when assigning a password" do
    [ nil, "", "different" ].each do |confirmation|
      user = build_user(password_confirmation: confirmation)
      assert_not user.valid?
      assert user.errors[:password_confirmation].any?
    end
  end

  test "can edit name without resetting password" do
    user = build_user
    user.save!
    user.reload.update!(name: "Новое имя")
    assert user.reload.authenticate("Lantern!Orbit7Cedar")
  end

  # Game session lifecycle
  test "starts an owned session and cascades deletion of all game data" do
    user = build_user
    user.save!
    game = user.start_game_session!(title: "Первый путь")
    complete_action(game)
    game.inventory.add_item!(code: "key", name: "Ключ")
    assert_equal user, game.user
    assert_equal game, user.reload.active_game_session
    assert_difference [ "GameSession.count", "Inventory.count", "InventoryItem.count", "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ], -1 do
      user.destroy!
    end
  end

  test "new game discards unfinished session but keeps completed history" do
    user = create_game_user
    finished = user.start_game_session!(title: "Завершённая").finish!
    unfinished = user.start_game_session!(title: "Черновик")
    complete_action(unfinished)
    unfinished.inventory.add_item!(code: "key", name: "Ключ")
    inventory_id = unfinished.inventory.id
    replacement = user.start_game_session!(title: "Новая")
    assert_not GameSession.exists?(unfinished.id)
    assert_not InventoryItem.exists?(inventory_id: inventory_id)
    assert_empty StorySummary.where(game_session_id: unfinished.id)
    assert_equal [ finished.id, replacement.id ].sort, user.game_sessions.pluck(:id).sort
    assert_equal replacement, user.reload.active_game_session
  end

  test "failed new game preserves the old session and its items" do
    user = create_game_user
    existing = user.start_game_session!(title: "Текущая")
    existing.inventory.add_item!(code: "key", name: "Ключ")
    assert_raises(ActiveRecord::RecordInvalid) { user.start_game_session!(title: " ") }
    assert_equal existing, user.reload.active_game_session
    assert_equal 1, existing.inventory.inventory_items.find_by!(code: "key").quantity
  end

  test "statistics returns the last ten completed games in completion order" do
    user = create_game_user
    games = 11.times.map do |index|
      game = user.start_game_session!(title: "Игра #{index}").finish!
      game.update!(completed_at: Time.utc(2026, 1, 1) + index.minutes)
      game
    end
    user.start_game_session!(title: "Активная")
    assert_equal games.reverse.first(10), user.recent_game_sessions.to_a
    assert_equal 11, user.game_sessions.completed.count
  end

  test "explicit deletion is scoped to the owner" do
    user = create_game_user
    own = user.start_game_session!(title: "Своя")
    foreign = create_game_session
    assert_raises(ActiveRecord::RecordNotFound) { user.delete_game_session!(foreign) }
    user.delete_game_session!(own)
    assert_not GameSession.exists?(own.id)
    assert GameSession.exists?(foreign.id)
  end
end
