require "test_helper"

class GameInteractionsTest < ActionDispatch::IntegrationTest
  def sign_in
    @user = create_game_user
    post login_path, params: { email: @user.email, password: "Lantern!Orbit7Cedar" }
  end

  test "guest can submit a command with JSON and without JavaScript" do
    assert_no_difference [ "GameSession.count", "PlayerAction.count" ] do
      post game_path, params: { command: "Осмотреть ворота" }, as: :json
      assert_response :success
      assert_equal "completed", response.parsed_body["status"]
      assert_includes response.parsed_body["text"], "нейросеть не подключена"
    end
    post game_path, params: { command: "Идти дальше" }
    assert_redirected_to game_path
    follow_redirect!
    assert_select "[data-story-text]", /нейросеть не подключена/
    assert_select "form[action=?][method='post'] input[name='command'][maxlength='2000']", game_path
  end

  test "empty oversized and structured commands return a friendly validation error" do
    [ nil, "  ", "x" * 2001, { text: "Идти" }, [ "Идти" ] ].each do |command|
      post game_path, params: { command: command }, as: :json
      assert_response :unprocessable_entity
      assert_equal "invalid", response.parsed_body["status"]
    end
    assert_equal 0, PlayerAction.count
  end

  test "signed in player can start submit repeatedly resume and finish a game" do
    sign_in
    post start_game_path
    assert_redirected_to game_path
    game = @user.reload.active_game_session
    game.inventory.add_item!(code: "key", name: "Старый ключ", description: "Открывает ворота", quantity: 2)
    game.update!(health: 79, stamina: 56)
    3.times do |index|
      post game_path, params: { command: "Осмотреть ворота #{index + 1}", game_session_id: game.id }, as: :json
      assert_response :success
      assert_equal game.id, response.parsed_body["game_session_id"]
    end
    assert_equal 3, game.player_actions.completed.count
    assert_empty game.player_actions.pending
    get root_path
    assert_select "a[href=?]", game_path, text: "Продолжить игру"
    get game_path
    assert_select ".stat-row strong", text: "79"
    assert_select ".stat-row strong", text: "56"
    assert_select ".inventory-slot-filled strong", "Старый ключ"
    assert_select ".inventory-slot-filled span", "× 2"
    assert_select "[data-scene-text]", GameController::SCENE_INTRO
    assert_select ".story-entry [data-story-text]", count: 3, text: /нейросеть не подключена/
    assert_select ".story-entry [data-player-echo]" do |entries|
      assert_equal [ "Ваше действие: Осмотреть ворота 1", "Ваше действие: Осмотреть ворота 2", "Ваше действие: Осмотреть ворота 3" ], entries.map(&:text)
    end
    assert_select "input[name='command'][value]", count: 0
    assert_select "[data-music-toggle]", count: 0
    assert_select "#command-feedback[hidden]"
    assert_select ".game-menu-panel form[action=?]", finish_game_path
    assert_select "form[data-confirm-finish] button[aria-controls='finish-confirmation']"
    assert_select "dialog#finish-confirmation[aria-labelledby='finish-title']" do
      assert_select "button[data-cancel-finish][autofocus]", text: "Продолжить игру"
      assert_select "button[data-confirm-finish-button]", text: "Завершить игру"
    end
    post finish_game_path
    assert_redirected_to statistics_path(from: "finished_game")
    follow_redirect!
    assert_select ".statistics-game h2", game.title
    assert_select ".back-arrow[href=?][aria-label='В главное меню']", root_path
    assert_select ".statistics-metrics dd", text: "3"
    assert game.reload.completed?
  end

  test "new game requires an explicit confirmation screen and preserves completed sessions" do
    sign_in
    finished = @user.start_game_session!(title: "Первая").finish!
    active = @user.start_game_session!(title: "Текущая")
    post start_game_path
    assert_redirected_to new_game_path
    assert GameSession.exists?(active.id)
    get new_game_path
    assert_select "form[action=?] button", start_game_path, text: "Начать заново"
    assert GameSession.exists?(active.id)
    post start_game_path, params: { replace_game_session_id: active.id }
    assert_not GameSession.exists?(active.id)
    assert GameSession.exists?(finished.id)
    assert_not_equal active.id, @user.reload.active_game_session.id
  end

  test "progress hint disappears after a response but errors remain visible" do
    get game_path
    assert_select "#command-feedback:not([hidden])"
    post game_path, params: { command: "Идти" }
    follow_redirect!
    assert_select "#command-feedback[hidden]"
    post game_path, params: { command: " " }
    follow_redirect!
    assert_select "#command-feedback.is-error:not([hidden])", /Введите действие/
  end

  test "a stale game tab cannot submit into a new or foreign session" do
    sign_in
    old = @user.start_game_session!(title: "Старая")
    current = @user.start_game_session!(title: "Новая")
    foreign = create_game_session
    [ old.id, foreign.id ].each do |id|
      assert_no_difference "PlayerAction.count" do
        post game_path, params: { command: "Идти", game_session_id: id }, as: :json
        assert_response :conflict
      end
    end
    assert_equal current, @user.reload.active_game_session
    post finish_game_path, params: { game_session_id: old.id }
    assert_redirected_to game_path
    assert current.reload.active?
  end

  test "a pending action produces a recoverable response instead of a server exception" do
    sign_in
    game = @user.start_game_session!(title: "Тропа")
    game.submit_action!(command: "Ждать")
    post game_path, params: { command: "Бежать" }, as: :json
    assert_response :conflict
    assert_equal 1, game.player_actions.count
    post finish_game_path
    assert_redirected_to game_path
    assert game.reload.active?
  end

  test "stored commands are rendered as text" do
    sign_in
    post game_path, params: { command: '<script>alert("x")</script>' }
    follow_redirect!
    assert_select "[data-player-echo] script", count: 0
    assert_select "[data-player-echo]", /<script>/
  end

  test "draft storage keys are isolated by account and game session" do
    get game_path
    assert_select "form[data-draft-key='rpi-command-guest-new']"
    sign_in
    get game_path
    assert_select "form[data-draft-key=?]", "rpi-command-#{@user.id}-new"
    first = @user.start_game_session!(title: "Первая")
    get game_path
    assert_select "form[data-draft-key=?]", "rpi-command-#{@user.id}-#{first.id}"
    second = @user.start_game_session!(title: "Вторая")
    get game_path
    assert_select "form[data-draft-key=?]", "rpi-command-#{@user.id}-#{second.id}"
    assert_select "form[data-draft-key=?]", "rpi-command-#{@user.id}-#{first.id}", count: 0
  end

  test "settings and UI kit expose the same working volume control and game return link" do
    get settings_path(from: "game")
    assert_select ".back-arrow[href=?]", game_path
    assert_select "input[type='range'][data-setting='volume'][min='0'][max='100']"
    assert_select "[data-music-toggle]"
    assert_select ".volume-control + button[data-music-toggle]", text: "Выключить музыку"
    assert_not_includes response.body, "0% — без звука"
    assert_not_includes response.body, "Спокойная фоновая мелодия"
    assert_select "label", text: "ИИ-рассказчик", count: 0
    get ui_kit_path
    assert_select "input[type='range'][data-setting='volume']"
  end
end
