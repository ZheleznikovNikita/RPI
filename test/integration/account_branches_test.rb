require "test_helper"

class AccountBranchesTest < ActionDispatch::IntegrationTest
  PASSWORD = "Lantern!Orbit7Cedar".freeze

  {
    "blank name" => { name: " " },
    "long name" => { name: "я" * 41 },
    "invalid email" => { email: "not-an-email" },
    "short password" => { password: "short", password_confirmation: "short" },
    "weak password" => { password: "password123456", password_confirmation: "password123456" },
    "missing confirmation" => { password_confirmation: "" },
    "mismatched confirmation" => { password_confirmation: "Different!Password7" },
    "password over bcrypt byte limit" => { password: "Ж" * 37, password_confirmation: "Ж" * 37 }
  }.each do |label, invalid_fields|
    test "registration rejects #{label} independently and accepts corrected form" do
      valid = { name: "Путник", email: "branches@example.test", password: PASSWORD, password_confirmation: PASSWORD }
      assert_no_difference [ "User.count", "GameSession.count" ] do
        post register_path(from: "game"), params: { user: valid.merge(invalid_fields) }
      end
      assert_response :unprocessable_entity
      assert_select ".form-errors li"
      assert_select "form[action=?]", register_path(from: "game")
      assert_nil session[:user_id]
      assert_difference "User.count", 1 do
        post register_path(from: "game"), params: { user: valid }
      end
      assert_redirected_to profile_path(from: "game")
      follow_redirect!
      assert_select ".session-status", "Вы вошли как Путник"
      assert_select ".back-arrow[href=?]", game_path
    end
  end

  test "duplicate email can be corrected without modifying the existing account" do
    owner = create_game_user(email: "duplicate@example.test")
    original = owner.attributes
    fields = { name: "Новый", email: " DUPLICATE@EXAMPLE.TEST ", password: PASSWORD, password_confirmation: PASSWORD }
    assert_no_difference "User.count" do
      post register_path, params: { user: fields }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors", /уже используется/
    assert_equal original, owner.reload.attributes
    assert_nil session[:user_id]
    post register_path, params: { user: fields.merge(email: "unique@example.test") }
    assert_redirected_to profile_path
    assert_not_equal owner.id, session[:user_id]
  end

  test "unknown account and empty credentials fail and a subsequent valid login works" do
    player = create_game_user
    [ {}, { email: "unknown@example.test", password: PASSWORD }, { email: player.email, password: "" } ].each do |credentials|
      post login_path(from: "game"), params: credentials
      assert_response :unprocessable_entity
      assert_select ".flash-alert", /проверьте email и пароль/
      assert_select "form[action=?]", login_path(from: "game")
      assert_nil session[:user_id]
    end
    post login_path(from: "game"), params: { email: player.email, password: PASSWORD }
    assert_redirected_to profile_path(from: "game")
    delete logout_path
    delete logout_path
    assert_redirected_to root_path
    get statistics_path
    assert_redirected_to login_path
  end

  test "long profile name is rejected and maximum length name persists after another login" do
    player = create_game_user
    post login_path, params: { email: player.email, password: PASSWORD }
    patch profile_path(from: "game"), params: { user: { name: "я" * 41 } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal "Игрок", player.reload.name
    patch profile_path(from: "game"), params: { user: { name: "я" * 40 } }
    assert_redirected_to profile_path(from: "game")
    delete logout_path
    post login_path, params: { email: player.email, password: PASSWORD }
    follow_redirect!
    assert_select "input[name='user[name]'][value=?]", "я" * 40
  end
end
