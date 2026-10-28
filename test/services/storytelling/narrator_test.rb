require "test_helper"

class Storytelling::NarratorTest < ActiveSupport::TestCase
  Provider = Struct.new(:response, :error, :payload, keyword_init: true) do
    def name = "test"
    def model_identifier = "test-narrator"
    def call(payload:)
      self.payload = payload
      raise error if error
      response
    end
  end

  setup { @game = create_game_session }

  test "offline demo replies advance and persist the story without a pending action" do
    narrator = Storytelling::Narrator.new
    assert_difference [ "StoryTurn.count", "StorySummary.count" ], 2 do
      2.times do
        result = narrator.call(command: "Осмотреть ворота", game_session: @game)
        assert_equal "completed", result.status
        assert_includes result.text, "нейросеть не подключена"
      end
    end
    assert_equal 2, @game.player_actions.completed.count
    assert_equal 2, @game.ai_requests.succeeded.count
    assert_equal [ "offline" ], @game.ai_requests.distinct.pluck(:provider)
    assert_equal [ 1, 2 ], @game.story_summaries.order(:version).pluck(:through_position)
    assert_empty @game.player_actions.pending
    assert_empty @game.ai_requests.where(status: %w[pending running])
  end

  test "an injected API adapter receives context and its result completes the existing models" do
    complete_action(@game, command: "Подойти к воротам", summary: "Герой у ворот")
    provider = Provider.new(response: { "narration" => "Ворота открываются.", "summary" => "Герой вошёл в город." })
    result = Storytelling::Narrator.new(provider: provider).call(command: "Постучать", game_session: @game)

    assert_equal "completed", result.status
    assert_equal "Ворота открываются.", result.text
    assert_equal "Герой у ворот", provider.payload["summary"]
    assert_equal "Подойти к воротам", provider.payload["history"].first["command"]
    assert_equal "Постучать", provider.payload["command"]
    assert_equal "Герой вошёл в город.", @game.summary
    assert @game.player_actions.last.completed?
    assert_equal result.text, @game.player_actions.last.story_turn.narration
  end

  test "timeouts and invalid JSON contracts fail cleanly and allow another command" do
    [ Provider.new(error: Timeout::Error.new("secret-provider-details")), Provider.new(response: { "narration" => "Без памяти" }) ].each do |provider|
      result = Storytelling::Narrator.new(provider: provider).call(command: "Идти", game_session: @game)
      assert_equal "error", result.status
      assert_not_includes result.text, "secret-provider-details"
      assert @game.player_actions.last.cancelled?
      assert @game.ai_requests.last.failed?
    end
    assert_empty @game.story_turns
    assert_empty @game.story_summaries
    assert_equal "completed", Storytelling::Narrator.new.call(command: "Снова идти", game_session: @game).status
  end

  test "guest preview does not persist data or call an external adapter" do
    provider = Provider.new(error: RuntimeError.new("must not call"))
    assert_no_difference [ "PlayerAction.count", "AiRequest.count" ] do
      assert_equal "completed", Storytelling::Narrator.new(provider: provider).call(command: "Идти").status
    end
    assert_nil provider.payload
  end
end
