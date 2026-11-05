require "test_helper"

class PlayerAccessTest < ActionDispatch::IntegrationTest
  test "player without an active game cannot command a foreign game and starts only their own" do
    owner = create_game_user
    private_game = owner.start_game_session!(title: "Чужая игра")
    visitor = create_game_user
    post login_path, params: { email: visitor.email, password: "Lantern!Orbit7Cedar" }
    assert_no_difference [ "GameSession.count", "PlayerAction.count", "AiRequest.count" ] do
      post game_path, params: { game_session_id: private_game.id, command: "Подмена" }, as: :json
      assert_response :conflict
      post finish_game_path, params: { game_session_id: private_game.id }
      assert_redirected_to game_path
    end
    assert_nil visitor.reload.active_game_session
    post start_game_path, params: { replace_game_session_id: private_game.id }
    assert_redirected_to game_path
    assert private_game.reload.active?
    assert_not_equal private_game.id, visitor.reload.active_game_session.id
    assert_equal owner.id, private_game.user_id
  end

  test "independent clients cannot read modify replace or finish another players progress" do
    owner = create_game_user
    visitor = create_game_user
    finished = owner.start_game_session!(title: "Личная статистика").finish!
    private_game = owner.start_game_session!(title: "Секретное приключение")
    complete_action(private_game, command: "Секретная команда", summary: "Секретная память")
    private_game.inventory.add_item!(code: "secret", name: "Секретный амулет")
    own_game = visitor.start_game_session!(title: "Своя игра")
    browser = open_session
    browser.post login_path, params: { email: visitor.email, password: "Lantern!Orbit7Cedar" }
    browser.assert_redirected_to profile_path
    before = [ private_game.reload.attributes, owner.reload.attributes, private_game.player_actions.map(&:attributes), private_game.story_summaries.map(&:attributes) ]

    browser.get game_path, params: { game_session_id: private_game.id, user_id: owner.id }
    browser.assert_response :success
    [ "Секретное приключение", "Секретная команда", "Секретная память", "Секретный амулет" ].each do |secret|
      assert_not_includes browser.response.body, secret
    end
    browser.patch profile_path, params: { id: owner.id, user: { id: owner.id, name: "Новое имя", email: "stolen@example.test" } }
    browser.assert_redirected_to profile_path
    assert_equal "Новое имя", visitor.reload.name
    assert_not_equal "stolen@example.test", visitor.email
    browser.get statistics_path, params: { user_id: owner.id, game_session_id: finished.id }
    browser.assert_select ".statistics-empty"
    assert_not_includes browser.response.body, finished.title

    assert_no_difference [ "GameSession.count", "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ] do
      browser.post game_path, params: { game_session_id: private_game.id, command: "Чужое действие" }, as: :json
      browser.assert_response :conflict
      browser.post finish_game_path, params: { game_session_id: private_game.id }
      browser.assert_redirected_to game_path
      browser.post start_game_path, params: { replace_game_session_id: private_game.id }
      browser.assert_redirected_to new_game_path
    end
    assert own_game.reload.active?
    assert_equal before, [ private_game.reload.attributes, owner.reload.attributes, private_game.player_actions.reload.map(&:attributes), private_game.story_summaries.reload.map(&:attributes) ]
    assert_equal "Секретный амулет", private_game.inventory.inventory_items.sole.name

    # A separate guest client has no authenticated cookie from either account.
    guest = open_session
    assert_no_difference [ "GameSession.count", "PlayerAction.count" ] do
      guest.patch profile_path, params: { user: { id: owner.id, name: "Гость" } }
      guest.assert_redirected_to profile_path
      guest.post finish_game_path, params: { game_session_id: private_game.id }
      guest.assert_redirected_to game_path
      guest.post game_path, params: { game_session_id: private_game.id, command: "Подмена" }, as: :json
      guest.assert_response :conflict
    end
    get profile_path
    assert_select ".session-status", "Вы не вошли в аккаунт"
  end
end
