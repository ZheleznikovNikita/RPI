require "test_helper"

class PrototypePagesTest < ActionDispatch::IntegrationTest
  test "main prototype pages render" do
    get root_path
    assert_response :success
    assert_select "h1", "RPI"

    get game_path
    assert_response :success
    assert_select ".dialogue-panel"

    get login_path
    assert_response :success
    assert_select "h1", "Авторизация"

    get register_path
    assert_response :success
    assert_select "h1", "Регистрация"

    get settings_path
    assert_response :success
    assert_select "h1", "Настройки"

    get profile_path
    assert_response :success
    assert_select "h1", /Профиль|Вход в профиль/
  end

  test "user can register and is signed in" do
    assert_difference("User.count", 1) do
      post register_path, params: {
        user: {
          name: "Тестовый игрок",
          email: "Player@Example.com",
          password: "secret123",
          password_confirmation: "secret123"
        }
      }
    end

    user = User.last
    assert_equal "player@example.com", user.email
    assert_not_equal "secret123", user.password_digest
    assert_redirected_to profile_path
    assert_equal user.id, session[:user_id]
  end

  test "registration rejects duplicated email" do
    User.create!(name: "Первый", email: "dupe@example.com", password: "secret123")

    assert_no_difference("User.count") do
      post register_path, params: {
        user: {
          name: "Второй",
          email: "DUPE@example.com",
          password: "secret123",
          password_confirmation: "secret123"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "registered user can log in" do
    user = User.create!(name: "Игрок", email: "login@example.com", password: "secret123")

    post login_path, params: { email: "login@example.com", password: "secret123" }

    assert_redirected_to profile_path
    assert_equal user.id, session[:user_id]
  end
end