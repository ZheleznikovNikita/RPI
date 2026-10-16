require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Странник", email: "auth@example.com", password: "Lantern!Orbit7Cedar", password_confirmation: "Lantern!Orbit7Cedar")
  end

  test "session survives repeated page requests and logout ends it" do
    get profile_path
    assert_select ".session-status", "Вы не вошли в аккаунт"
    post login_path, params: { email: " AUTH@EXAMPLE.COM ", password: "Lantern!Orbit7Cedar" }
    assert_redirected_to profile_path
    2.times do
      get profile_path
      assert_select ".session-status", "Вы вошли как Странник"
      assert_select "form[action=?] input[name='_method'][value='delete']", logout_path
      assert_select "form[action=?][data-confirm-logout='Выйти из аккаунта?']", logout_path
      assert_select ".profile-card a[href=?]", game_path, count: 0
      assert_select ".back-arrow[href=?][aria-label='В главное меню']", root_path
      assert_select ".profile-tools a[href=?]", ui_kit_path, text: "UI Kit"
    end
    delete logout_path
    assert_response :see_other
    assert_nil session[:user_id]
    get profile_path
    assert_select ".session-status", "Вы не вошли в аккаунт"
  end

  test "incorrect password cannot establish a session" do
    post login_path, params: { email: @user.email, password: "incorrect" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_select ".flash-alert"
  end

  test "editing profile preserves return to game including validation errors" do
    post login_path(from: "game"), params: { email: @user.email, password: "Lantern!Orbit7Cedar" }
    assert_redirected_to profile_path(from: "game")
    get profile_path(from: "game")
    assert_select "form.auth-form[action=?]", profile_path(from: "game")
    patch profile_path(from: "game"), params: { user: { name: "" } }
    assert_response :unprocessable_entity
    assert_select ".back-arrow[href=?]", game_path
    patch profile_path(from: "game"), params: { user: { name: "Новое имя" } }
    assert_redirected_to profile_path(from: "game")
    follow_redirect!
    assert_select ".back-arrow[href=?]", game_path
  end

  test "weak registration password is rejected with Russian error" do
    assert_no_difference "User.count" do
      post register_path, params: { user: { name: "Другой", email: "other@example.com", password: "password123456", password_confirmation: "password123456" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors", /слишком предсказуемый/
    assert_nil session[:user_id]
  end

  test "guest cannot update a profile" do
    patch profile_path, params: { user: { name: "Подмена" } }
    assert_redirected_to profile_path
    assert_equal "Странник", @user.reload.name
  end

  test "ui kit exposes core components" do
    get ui_kit_path
    assert_response :success
    assert_select "h1", "RPI UI Kit"
    assert_select "progress", count: 2
    assert_select "input[aria-invalid='true']"
    assert_select "body[data-ui-lab='enabled']"
  end
end
