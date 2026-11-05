require "test_helper"

class PlayerJourneyTest < ActionDispatch::IntegrationTest
  PASSWORD = "Lantern!Orbit7Cedar".freeze

  test "guest registers from game and starts saved progress without importing transient demo" do
    post game_path, params: { command: "Гостевая команда" }
    follow_redirect!
    assert_select "[data-story-text]", Storytelling::OfflineProvider::MESSAGE
    get profile_path(from: "game")
    assert_select "a[href=?]", register_path(from: "game")
    post register_path(from: "game"), params: { user: { name: "Путник", email: "guest-journey@example.test", password: PASSWORD, password_confirmation: PASSWORD } }
    assert_redirected_to profile_path(from: "game")
    follow_redirect!
    assert_select ".back-arrow[href=?]", game_path
    get game_path
    assert_select ".story-entry", count: 0
    post game_path, params: { command: "Сохранённая команда" }
    follow_redirect!
    assert_select "[data-player-echo]", "Ваше действие: Сохранённая команда"
    assert_equal [ "Сохранённая команда" ], User.find_by!(email: "guest-journey@example.test").active_game_session.player_actions.pluck(:command)
  end

  test "player registers plays resumes after login finishes and starts a fresh journey" do
    get root_path
    assert_select "a[href=?]", register_path
    get register_path
    assert_response :success
    assert_difference "User.count", 1 do
      post register_path, params: { user: { name: "Путник", email: "journey@example.test", password: PASSWORD, password_confirmation: PASSWORD } }
    end
    assert_redirected_to profile_path
    follow_redirect!
    assert_select ".session-status", "Вы вошли как Путник"
    patch profile_path, params: { user: { name: "Хранитель" } }
    follow_redirect!
    assert_select "input[name='user[name]'][value='Хранитель']"

    get root_path
    assert_select "form[action=?] button", start_game_path, text: "Начать игру"
    assert_difference [ "GameSession.count", "Inventory.count" ], 1 do
      post start_game_path
    end
    assert_redirected_to game_path
    follow_redirect!
    assert_select ".inventory-empty"
    assert_select "#command-feedback:not([hidden])", /Прогресс сохраняется/
    player = User.find_by!(email: "journey@example.test")
    game = player.active_game_session

    assert_difference [ "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ], 1 do
      post game_path, params: { game_session_id: game.id, command: "  Осмотреть ворота  " }
    end
    assert_redirected_to game_path
    follow_redirect!
    assert_select "[data-player-echo]", "Ваше действие: Осмотреть ворота"
    assert_select "[data-story-text]", Storytelling::OfflineProvider::MESSAGE
    assert_select "#command-feedback[hidden]"

    get settings_path(from: "game")
    assert_select "input[type='range'][data-setting='volume']"
    assert_select ".back-arrow[href=?]", game_path
    get profile_path(from: "game")
    assert_select "a[href=?]", ui_kit_path(from: "game")
    get ui_kit_path(from: "game")
    assert_select ".back-arrow[href=?]", profile_path(from: "game")

    delete logout_path
    assert_redirected_to root_path
    get statistics_path
    assert_redirected_to login_path
    post login_path, params: { email: player.email, password: PASSWORD }
    assert_redirected_to profile_path
    get root_path
    assert_select "a[href=?]", game_path, text: "Продолжить игру"
    get game_path
    assert_select "input[name='game_session_id'][value=?]", game.id.to_s
    assert_select "[data-player-echo]", "Ваше действие: Осмотреть ворота"

    assert_difference [ "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ], 1 do
      post game_path, params: { game_session_id: game.id, command: "Постучать" }, as: :json
    end
    assert_response :success
    assert_equal "completed", response.parsed_body.fetch("status")
    assert_equal game.id, response.parsed_body.fetch("game_session_id")
    assert_equal Storytelling::OfflineProvider::MESSAGE, response.parsed_body.fetch("text")
    assert_equal [ "Осмотреть ворота", "Постучать" ], game.player_actions.completed.pluck(:command)
    assert_equal [ 1, 2 ], game.story_summaries.order(:version).pluck(:through_position)
    assert_equal [ "succeeded", "succeeded" ], game.ai_requests.order(:id).pluck(:status)

    post finish_game_path, params: { game_session_id: game.id }
    assert_redirected_to statistics_path(from: "finished_game")
    follow_redirect!
    assert_select ".statistics-game h2", game.title
    assert_select ".statistics-metrics dd", text: "2"
    assert_select ".back-arrow[href=?]", root_path
    assert game.reload.completed?
    assert_not_nil game.completed_at
    get statistics_path
    assert_select ".back-arrow[href=?]", profile_path

    assert_difference [ "GameSession.count", "Inventory.count" ], 1 do
      post start_game_path
    end
    fresh = player.reload.active_game_session
    assert_not_equal game.id, fresh.id
    get game_path
    assert_select ".story-entry", count: 0
    assert_select ".inventory-empty"
    assert_equal 2, game.player_actions.completed.count
    delete logout_path
    follow_redirect!
    assert_select ".profile-pill", "Профиль"
  end

  test "player corrects registration login profile and command validation errors" do
    assert_no_difference "User.count" do
      post register_path, params: { user: { name: "", email: "invalid", password: PASSWORD, password_confirmation: "different" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    player = create_game_user
    post login_path, params: { email: player.email, password: "wrong" }
    assert_response :unprocessable_entity
    assert_select ".flash-alert"
    get profile_path
    assert_select ".session-status", "Вы не вошли в аккаунт"
    post login_path, params: { email: player.email, password: PASSWORD }
    assert_redirected_to profile_path
    patch profile_path, params: { user: { name: " " } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal "Игрок", player.reload.name
    patch profile_path, params: { user: { name: "Следопыт" } }
    assert_redirected_to profile_path
    assert_equal "Следопыт", player.reload.name

    # Invalid input must not lazily create a game or any part of a story.
    assert_no_difference [ "GameSession.count", "Inventory.count", "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ] do
      post game_path, params: { command: " " }
      assert_redirected_to game_path
      follow_redirect!
      assert_select "#command-feedback.is-error:not([hidden])", /Введите действие/
    end
    post game_path, params: { command: "Осмотреться" }, as: :json
    assert_response :success
    game = player.reload.active_game_session
    assert_equal 1, game.player_actions.completed.count
    get game_path
    assert_select "#command-feedback[hidden]"
    assert_select "[data-player-echo]", "Ваше действие: Осмотреться"
  end
end
