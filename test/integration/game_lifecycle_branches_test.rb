require "test_helper"

class GameLifecycleBranchesTest < ActionDispatch::IntegrationTest
  STORY_COUNTS = [ "GameSession.count", "Inventory.count", "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ].freeze

  setup do
    @player = create_game_user
    post login_path, params: { email: @player.email, password: "Lantern!Orbit7Cedar" }
  end

  test "guest can visit start and restart routes but cannot persist or finish a game" do
    delete logout_path
    assert_no_difference STORY_COUNTS do
      get new_game_path
      assert_redirected_to game_path
      post start_game_path
      assert_redirected_to game_path
      follow_redirect!
      assert_select ".game-menu-panel form[action=?]", finish_game_path, count: 0
      post game_path, params: { command: "Осмотреться" }
      follow_redirect!
      assert_select "[data-story-text]", Storytelling::OfflineProvider::MESSAGE
      get game_path
      assert_select ".story-entry", count: 0
      post finish_game_path
      assert_redirected_to game_path
      follow_redirect!
      assert_select ".flash-alert", /Нет активного прохождения/
    end
  end

  test "restart can be abandoned and confirmed restart deletes only unfinished progress" do
    finished = @player.start_game_session!(title: "Архив")
    complete_action(finished)
    finished.finish!
    archived_turn = finished.story_turns.sole
    game = @player.start_game_session!(title: "Черновик")
    complete_action(game)
    game.inventory.add_item!(code: "key", name: "Ключ")
    removed = [ game.inventory, game.inventory.inventory_items.sole, game.player_actions.sole, game.ai_requests.sole, game.story_turns.sole, game.story_summaries.sole ]
    assert_no_difference STORY_COUNTS do
      get new_game_path
      assert_response :success
      assert_select "input[name='replace_game_session_id'][value=?]", game.id.to_s
      assert_select "a[href=?]", game_path, text: "Продолжить текущую"
      get game_path
      assert_select ".story-entry", count: 1
      assert_select ".inventory-slot-filled strong", "Ключ"
    end
    post start_game_path, params: { replace_game_session_id: game.id }
    assert_redirected_to game_path
    assert_not GameSession.exists?(game.id)
    removed.each { |record| assert_not record.class.exists?(record.id), "Restart left #{record.class} #{record.id}" }
    assert StoryTurn.exists?(archived_turn.id)
    fresh = @player.reload.active_game_session
    assert_equal [ 100, 100 ], [ fresh.health, fresh.stamina ]
    assert_empty fresh.player_actions
    assert_empty fresh.story_summaries
    assert_empty fresh.inventory.inventory_items
    get statistics_path
    assert_select ".statistics-game h2", "Архив"

    # Repeating an old confirmation must not delete the newly created game.
    assert_no_difference STORY_COUNTS do
      post start_game_path, params: { replace_game_session_id: game.id }
      assert_redirected_to new_game_path
    end
    assert_equal fresh.id, @player.reload.active_game_session.id
  end

  test "finished game cannot be finished twice or receive commands from an old form" do
    post start_game_path
    game = @player.reload.active_game_session
    post finish_game_path, params: { game_session_id: game.id }
    assert_redirected_to statistics_path(from: "finished_game")
    completed_at = game.reload.completed_at
    assert_no_difference STORY_COUNTS do
      post finish_game_path, params: { game_session_id: game.id }
      assert_redirected_to game_path
      post game_path, params: { game_session_id: game.id, command: "Позднее действие" }, as: :json
      assert_response :conflict
    end
    assert_equal completed_at, game.reload.completed_at
    assert_nil @player.reload.active_game_session
    get root_path
    assert_select "a[href=?]", game_path, text: "Продолжить игру", count: 0
    assert_select "form[action=?]", start_game_path
    post game_path, params: { command: "Новое приключение" }, as: :json
    assert_response :success
    assert_not_equal game.id, response.parsed_body.fetch("game_session_id")
    assert game.reload.completed?
  end

  test "authenticated player without a game can open new screen and cannot finish anything" do
    assert_no_difference STORY_COUNTS do
      get new_game_path
      assert_response :success
      post finish_game_path
      assert_redirected_to game_path
      follow_redirect!
      assert_select ".flash-alert", /Нет активного прохождения/
    end
    post start_game_path
    assert_redirected_to game_path
    assert @player.reload.active_game_session
  end

  test "unfinished image request blocks finishing even when its player action is completed" do
    game = @player.start_game_session!(title: "Тропа")
    action = complete_action(game)
    request = action.request_ai!(purpose: "image", provider: "test", model_identifier: "test", payload: { "prompt" => "Тропа" })
    [ :pending, :running ].each do |status|
      request.start! if status == :running
      post finish_game_path, params: { game_session_id: game.id }
      assert_redirected_to game_path
      follow_redirect!
      assert_select ".flash-alert", /дождитесь завершения/
      assert game.reload.active?
    end
    request.succeed!(response: { "image_url" => "https://example.test/scene.png" })
    post finish_game_path, params: { game_session_id: game.id }
    assert_redirected_to statistics_path(from: "finished_game")
    assert game.reload.completed?
  end

  [ :html, :json ].each do |format|
    test "#{format} invalid commands preserve an existing story and boundary commands succeed" do
      game = @player.start_game_session!(title: "Тропа")
      complete_action(game)
      original = game.story_summaries.sole.attributes
      [ nil, "", " \t\n", "я" * 2001, [ "Идти" ], { text: "Идти" } ].each do |command|
        assert_no_difference STORY_COUNTS do
          send_command(game, command, format)
        end
        if format == :json
          assert_response :unprocessable_entity
          assert_equal "invalid", response.parsed_body.fetch("status")
        else
          assert_redirected_to game_path
          follow_redirect!
          assert_select "#command-feedback.is-error:not([hidden])", /Введите действие/
          assert_select ".story-entry", count: 1
        end
        assert_equal original, game.story_summaries.sole.attributes
      end
      [ "я", "я" * 2000 ].each do |command|
        assert_difference [ "PlayerAction.count", "AiRequest.count", "StoryTurn.count", "StorySummary.count" ], 1 do
          send_command(game, command, format)
        end
        assert_response(format == :json ? :success : :see_other)
        assert_equal command, game.player_actions.last.command
      end
    end

    test "#{format} stale tab is rejected and refreshed form can submit" do
      old = @player.start_game_session!(title: "Прежняя")
      game = @player.start_game_session!(title: "Новая")
      assert_no_difference STORY_COUNTS do
        send_command(old, "Идти", format)
      end
      if format == :json
        assert_response :conflict
        assert_equal "conflict", response.parsed_body.fetch("status")
      else
        follow_redirect!
        assert_select "#command-feedback.is-error", /Прохождение изменилось/
      end
      get game_path
      assert_select "input[name='game_session_id'][value=?]", game.id.to_s
      send_command(game, "Идти", format)
      assert_response(format == :json ? :success : :see_other)
      assert_equal 1, game.player_actions.completed.count
    end

    test "#{format} pending action blocks another command until it is resolved" do
      game = @player.start_game_session!(title: "Тропа")
      action = game.submit_action!(command: "Ждать")
      request = action.request_ai!(purpose: "narration", provider: "test", model_identifier: "test", payload: { "command" => "Ждать" })
      request.start!
      assert_no_difference STORY_COUNTS do
        send_command(game, "Бежать", format)
      end
      if format == :json
        assert_response :conflict
      else
        follow_redirect!
        assert_select "#command-feedback.is-error", /ещё обрабатывается/
      end
      post finish_game_path, params: { game_session_id: game.id }
      follow_redirect!
      assert_select ".flash-alert", /дождитесь завершения/
      assert game.reload.active?
      assert request.reload.running?
      # There is no public admin endpoint: simulate completion of the worker's request.
      request.succeed!(response: { "narration" => "Ожидание закончено." })
      action.complete!(request: request, summary: "Герой дождался ответа")
      send_command(game, "Бежать", format)
      assert_response(format == :json ? :success : :see_other)
      assert_equal 2, game.player_actions.completed.count
      post finish_game_path, params: { game_session_id: game.id }
      assert_redirected_to statistics_path(from: "finished_game")
    end
  end

  private

  def send_command(game, command, format)
    options = { params: { game_session_id: game.id, command: command } }
    options[:as] = :json if format == :json
    post game_path, **options
  end
end
