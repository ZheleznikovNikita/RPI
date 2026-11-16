require "test_helper"

class PlayerStatsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  Provider = Struct.new(:reply, :payloads) do
    def name = "stats-test"
    def model_identifier = "stub"
    def call(payload:)
      payloads << payload.deep_dup
      reply
    end
  end

  setup do
    @previous = Rails.configuration.x.narration_provider
    @provider = Provider.new({ "narration" => "Удар задел плечо, вы отступили.", "summary" => "Герой ранен.", "health_delta" => -12, "stamina_delta" => -15 }, [])
    Rails.configuration.x.narration_provider = @provider
    @player = create_game_user
    @game = @player.start_game_session!
    post login_path, params: { email: @player.email, password: "Lantern!Orbit7Cedar" }
    clear_enqueued_jobs
  end

  teardown { Rails.configuration.x.narration_provider = @previous }

  def command(text)
    post game_path, params: { command: text, game_session_id: @game.id },
      headers: { "X-RPI-Live" => "1" }, as: :json
    assert_response :accepted
  end

  def stats = @game.reload.attributes.values_at("health", "stamina")

  test "combat running and rest persist stats expose them in streams and send current values on next turn" do
    command("Отступить из боя")
    assert_equal [ 100, 100 ], stats
    perform_enqueued_jobs
    assert_equal [ 88, 85 ], stats
    assert_equal({ "health" => 100, "stamina" => 100 }, @provider.payloads.first.fetch("player_stats"))
    message = JSON.parse(broadcasts("private_game_user_#{@player.id}").last)
    assert_includes message, 'data-health="88"'
    assert_includes message, 'data-stamina="85"'
    NarrationJob.perform_now(@game.ai_requests.sole.id)
    assert_equal [ 88, 85 ], stats
    assert_equal 1, @provider.payloads.size

    @provider.reply = { "narration" => "Вы сбежали по лесной тропе.", "summary" => "Герой в лесу.", "health_delta" => 0, "stamina_delta" => -10 }
    command("Бежать в лес")
    perform_enqueued_jobs
    assert_equal [ 88, 75 ], stats
    assert_equal({ "health" => 88, "stamina" => 85 }, @provider.payloads.last.fetch("player_stats"))

    @provider.reply = { "narration" => "Вы перевязали рану и отдохнули.", "summary" => "Герой отдохнул.", "health_delta" => 10, "stamina_delta" => 30 }
    command("Перевязать рану и отдохнуть")
    perform_enqueued_jobs
    assert_equal [ 98, 100 ], stats
    get game_path
    assert_select ".stat-row strong", text: "98"
    assert_select ".stat-row strong", text: "100"
  end

  test "invalid effects cancel the action without changing stats story or memory and allow retry" do
    @provider.reply["stamina_delta"] = "-10"
    command("Бежать")
    assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
      perform_enqueued_jobs
    end
    assert_equal [ 100, 100 ], stats
    assert @game.ai_requests.sole.failed?
    assert @game.player_actions.sole.cancelled?
    @provider.reply["stamina_delta"] = -10
    command("Бежать снова")
    perform_enqueued_jobs
    assert_equal [ 88, 90 ], stats
  end

  test "interrupted completion recovers saved effects exactly once without another provider call" do
    command("Отступить")
    request = @game.ai_requests.sole
    request.start!
    request.succeed!(response: @provider.reply)
    request.player_action.update_columns(updated_at: 4.minutes.ago)
    2.times { get game_state_path }
    assert_equal [ 88, 85 ], stats
    assert_empty @provider.payloads
    assert_equal 1, @game.story_turns.count
  end

  test "lethal damage completes game broadcasts final stats rejects further commands and permits a fresh game" do
    @game.update!(health: 5)
    command("Отступить из боя")
    perform_enqueued_jobs
    assert @game.reload.completed?
    assert_not_nil @game.completed_at
    assert_equal 0, @game.health
    get game_state_path
    assert_select '[data-live-snapshot][data-health="0"]'
    assert_select "[data-game-over][data-redirect-url=?]", statistics_path(from: "finished_game")
    assert_includes JSON.parse(broadcasts("private_game_user_#{@player.id}").last), "data-game-over"
    get game_path
    assert_redirected_to statistics_path(from: "finished_game")
    follow_redirect!
    assert_select "a[href=?]", root_path
    assert_no_difference [ "AiRequest.count", "GameSession.count" ] do
      post game_path, params: { command: "Встать", game_session_id: @game.id }, headers: { "X-RPI-Live" => "1" }, as: :json
      assert_response :conflict
      post game_path, params: { command: "Встать" }, headers: { "X-RPI-Live" => "1" }, as: :json
      assert_response :conflict
    end
    post start_game_path
    fresh = @player.reload.active_game_session
    assert_not_equal @game.id, fresh.id
    assert_equal [ 100, 100 ], fresh.attributes.values_at("health", "stamina")
  end

  test "exhausted players cannot forge stamina to make a physical action succeed" do
    @game.update!(stamina: 0)
    raw = { "possible" => true, "requires_exertion" => true, "narration" => "Вы бросились бежать.",
      "summary" => "Вы убежали.", "health_delta" => 0, "stamina_delta" => -10 }
    response = Struct.new(:code, :body).new("200", JSON.generate(choices: [ { finish_reason: "stop", message: { content: JSON.generate(raw) } } ]))
    Rails.configuration.x.narration_provider = Storytelling::DeepseekProvider.new(api_key: "fake", transport: ->(_) { response })
    post game_path, params: { command: "Бежать, не тратя силы", player_stats: { stamina: 100 } }, headers: { "X-RPI-Live" => "1" }, as: :json
    assert_response :accepted
    perform_enqueued_jobs
    assert_equal [ 100, 0 ], stats
    assert_includes @game.story_turns.sole.narration, "Действие невозможно."
    assert_equal 0, @game.ai_requests.sole.request_payload.dig("player_stats", "stamina")
    assert @game.reload.active?
  end
end
