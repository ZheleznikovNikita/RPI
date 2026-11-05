require "test_helper"

class NarrationRecoveryTest < ActionDispatch::IntegrationTest
  # Only the external boundary is replaced; requests use real controllers and persistence.
  Provider = Struct.new(:reply, :error, :payloads, keyword_init: true) do
    def name = "integration"
    def model_identifier = "test-narrator"

    def call(payload:)
      payloads << payload.deep_dup
      raise error if error
      reply
    end
  end

  setup do
    @previous_provider = Rails.configuration.x.narration_provider
    @provider = Provider.new(payloads: [])
    Rails.configuration.x.narration_provider = @provider
    @player = create_game_user
    post login_path, params: { email: @player.email, password: "Lantern!Orbit7Cedar" }
    post start_game_path
    @game = @player.reload.active_game_session
  end

  teardown { Rails.configuration.x.narration_provider = @previous_provider }

  [ :html, :json ].each do |format|
    {
      "non object" => [],
      "missing narration" => { "summary" => "Память" },
      "blank narration" => { "narration" => " ", "summary" => "Память" },
      "non string narration" => { "narration" => 7, "summary" => "Память" },
      "missing summary" => { "narration" => "Рассказ" },
      "blank summary" => { "narration" => "Рассказ", "summary" => " " },
      "non string summary" => { "narration" => "Рассказ", "summary" => [ "Память" ] },
      "oversized narration" => { "narration" => "я" * 20_001, "summary" => "Память" },
      "oversized summary" => { "narration" => "Рассказ", "summary" => "я" * 20_001 },
      "timeout" => nil
    }.each do |label, reply|
      test "#{format} rejects #{label} without advancing story and allows recovery" do
        @provider.reply = reply
        @provider.error = Timeout::Error.new("private-service-details") if label == "timeout"
        assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
          assert_difference [ "PlayerAction.count", "AiRequest.count" ], 1 do
            options = { params: { game_session_id: @game.id, command: "Осмотреться" } }
            options[:as] = :json if format == :json
            post game_path, **options
          end
        end
        if format == :json
          assert_response :bad_gateway
          assert_equal "error", response.parsed_body.fetch("status")
          assert_equal Storytelling::Narrator::ERROR_MESSAGE, response.parsed_body.fetch("text")
        else
          assert_redirected_to game_path
          follow_redirect!
          assert_select "#command-feedback.is-error", Storytelling::Narrator::ERROR_MESSAGE
          assert_select ".story-entry", count: 0
        end
        assert_not_includes response.body, "private-service-details"
        assert @game.player_actions.last.cancelled?
        failed_request = @game.ai_requests.order(:id).last
        assert failed_request.failed?
        assert_not_nil failed_request.finished_at
        assert_empty @game.ai_requests.where(status: %w[pending running])
        @provider.error = nil
        @provider.reply = { "narration" => "Вы нашли тропу.", "summary" => "Герой на тропе" }
        options = { params: { game_session_id: @game.id, command: "Осмотреться" } }
        options[:as] = :json if format == :json
        assert_difference [ "StoryTurn.count", "StorySummary.count" ], 1 do
          post game_path, **options
        end
        assert_response(format == :json ? :success : :see_other)
        assert_equal "Герой на тропе", @game.summary
        assert_equal 1, @game.player_actions.completed.count
        get game_path
        assert_select "[data-story-text]", "Вы нашли тропу."
        assert_select "#command-feedback[hidden]"
      end
    end
  end

  test "provider markup is escaped when saved narration is rendered" do
    @provider.reply = { "narration" => '<script>alert("provider")</script>', "summary" => "Память" }
    post game_path, params: { game_session_id: @game.id, command: "Осмотреться" }
    follow_redirect!
    assert_select "[data-story-text] script", count: 0
    assert_select "[data-story-text]", '<script>alert("provider")</script>'
  end

  test "JSON timeout preserves accepted story and retry succeeds with its context" do
    accept_first_turn
    @provider.error = Timeout::Error.new("private-api-key-and-host")
    assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
      assert_difference [ "PlayerAction.count", "AiRequest.count" ], 1 do
        post game_path, params: { game_session_id: @game.id, command: "Открыть ворота" }, as: :json
      end
    end
    assert_response :bad_gateway
    assert_equal "error", response.parsed_body.fetch("status")
    assert_equal Storytelling::Narrator::ERROR_MESSAGE, response.parsed_body.fetch("text")
    assert_not_includes response.body, "private-api-key-and-host"
    assert @game.player_actions.last.cancelled?
    assert @game.ai_requests.order(:id).last.failed?
    assert_empty @game.player_actions.pending
    assert_equal "Герой у ворот", @game.summary
    get game_path
    assert_select ".story-entry", count: 1
    assert_select "[data-story-text]", "Впереди ворота."

    @provider.error = nil
    @provider.reply = { "narration" => "Ворота открылись.", "summary" => "Герой вошёл в город" }
    assert_difference [ "StoryTurn.count", "StorySummary.count" ], 1 do
      post game_path, params: { game_session_id: @game.id, command: "Открыть ворота" }, as: :json
    end
    assert_response :success
    assert_equal "Ворота открылись.", response.parsed_body.fetch("text")
    assert_equal "Герой у ворот", @provider.payloads.last.fetch("summary")
    assert_equal [ { "command" => "Подойти", "narration" => "Впереди ворота." } ], @provider.payloads.last.fetch("history")
    assert_equal "Герой вошёл в город", @game.summary
    get game_path
    assert_select ".story-entry", count: 2
    post finish_game_path, params: { game_session_id: @game.id }
    follow_redirect!
    assert_select ".statistics-metrics dd", text: "2"
  end

  test "HTML invalid provider response shows a safe error and allows a successful retry" do
    @provider.reply = { "narration" => "Ответ без обязательной памяти" }
    assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
      post game_path, params: { game_session_id: @game.id, command: "Подойти" }
    end
    assert_redirected_to game_path
    follow_redirect!
    assert_select "#command-feedback.is-error:not([hidden])", Storytelling::Narrator::ERROR_MESSAGE
    assert_select ".story-entry", count: 0
    assert @game.player_actions.last.cancelled?
    assert @game.ai_requests.order(:id).last.failed?
    @provider.reply = { "narration" => "Впереди ворота.", "summary" => "Герой у ворот" }
    post game_path, params: { game_session_id: @game.id, command: "Подойти" }
    follow_redirect!
    assert_select "#command-feedback[hidden]"
    assert_select "[data-story-text]", "Впереди ворота."
    get game_path
    assert_select ".story-entry", count: 1
    assert_select "#command-feedback[hidden]"
  end

  private

  def accept_first_turn
    @provider.reply = { "narration" => "Впереди ворота.", "summary" => "Герой у ворот" }
    post game_path, params: { game_session_id: @game.id, command: "Подойти" }, as: :json
    assert_response :success
  end
end
