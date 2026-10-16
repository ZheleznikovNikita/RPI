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

  # Adventure ownership
  test "starts owned adventure and cascades deletion" do
    user = build_user
    user.save!
    adventure = user.start_adventure!(title: "Первый путь")
    adventure.record_turn!(command: "Идти", response: { "narration" => "Вы у ворот", "summary" => "Герой у ворот" })
    assert_equal user, adventure.user
    assert adventure.active?
    assert_difference [ "Adventure.count", "StoryTurn.count" ], -1 do
      user.destroy!
    end
  end
end
