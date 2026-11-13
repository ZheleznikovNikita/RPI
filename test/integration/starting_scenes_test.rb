require "test_helper"

class StartingScenesTest < ActionDispatch::IntegrationTest
  test "preview stays stable and first saved command uses the displayed opening" do
    player = create_game_user
    post login_path, params: { email: player.email, password: "Lantern!Orbit7Cedar" }
    get game_path
    intro = css_select("[data-scene-text]").sole.text
    title = css_select(".story-label").sole.text
    get game_path
    assert_select "[data-scene-text]", intro
    post game_path, params: { command: "Осмотреться" }, as: :json
    assert_response :success
    game = player.reload.active_game_session
    assert_equal [ title, intro ], [ game.title, game.opening_scene ]
    assert_equal intro, game.ai_requests.sole.request_payload.fetch("scene")
    assert_equal title, game.ai_requests.sole.request_payload.fetch("scene_title")
    delete logout_path
    post login_path, params: { email: player.email, password: "Lantern!Orbit7Cedar" }
    get game_path
    assert_select "[data-scene-text]", intro
    assert_select ".story-label", title
  end

  test "all ten openings are rendered persisted and passed to the narrator" do
    player = create_game_user
    post login_path, params: { email: player.email, password: "Lantern!Orbit7Cedar" }
    assert_equal 10, StartingScenes::SCENES.length
    assert_equal 10, StartingScenes::SCENES.map { |scene| scene[:title] }.uniq.length
    StartingScenes::SCENES.each do |opening|
      game = player.start_game_session!(opening: opening)
      get game_path
      assert_select ".story-label", opening[:title]
      assert_select "[data-scene-text]", opening[:intro]
      post game_path, params: { game_session_id: game.id, command: "Осмотреться" }, as: :json
      assert_response :success
      assert_equal opening[:intro], game.ai_requests.sole.request_payload.fetch("scene")
      assert_equal opening[:intro], game.reload.opening_scene
    end
  end

  test "new game samples a valid opening and confirmed restart saves a new snapshot" do
    player = create_game_user
    post login_path, params: { email: player.email, password: "Lantern!Orbit7Cedar" }
    post start_game_path
    first = player.reload.active_game_session
    assert_includes StartingScenes::SCENES, { title: first.title, intro: first.opening_scene }
    post start_game_path, params: { replace_game_session_id: first.id }
    second = player.reload.active_game_session
    assert_not_equal first.id, second.id
    assert_includes StartingScenes::SCENES, { title: second.title, intro: second.opening_scene }
    # A random draw is allowed to select the same opening again.
    assert_empty second.player_actions
  end
end
