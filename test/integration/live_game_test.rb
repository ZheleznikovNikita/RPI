require "test_helper"

class LiveGameTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  class BrokenQueueAdapter
    def enqueue(job) = raise(ActiveJob::EnqueueError, "private-queue-details")
    def enqueue_at(job, timestamp) = enqueue(job)
  end

  setup do
    @player = create_game_user
    post login_path, params: { email: @player.email, password: "Lantern!Orbit7Cedar" }
    post start_game_path
    @game = @player.reload.active_game_session
    clear_enqueued_jobs
  end

  test "acceptance queues a job and completion broadcasts a Turbo Stream with one persisted turn" do
    assert_no_difference "StoryTurn.count" do
      assert_enqueued_with(job: NarrationJob) { live_command("Осмотреться") }
    end
    assert_response :accepted
    assert_equal "accepted", response.parsed_body.fetch("status")
    request = @game.ai_requests.sole
    assert request.pending?
    assert_broadcasts "private_game_user_#{@player.id}", 2 do
      perform_enqueued_jobs
    end
    assert request.reload.succeeded?
    assert_equal 1, @game.story_turns.count
    message = JSON.parse(broadcasts("private_game_user_#{@player.id}").last)
    assert_includes message, '<turbo-stream action="update" target="live-state">'
    assert_includes message, "Осмотреться"
    assert_includes message, 'data-pending="false"'
    assert_no_difference [ "StoryTurn.count", "AiRequest.count" ] do
      NarrationJob.perform_now(request.id)
    end
  end

  test "a second tab recovers accepted story through state endpoint without resubmitting" do
    live_command("Постучать")
    live_command("Повтор")
    assert_response :conflict
    assert_equal 1, @game.player_actions.count
    get game_state_path
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_select "[data-live-snapshot][data-pending='true']"
    perform_enqueued_jobs
    get game_state_path
    assert_select ".story-entry", count: 1
    assert_select "[data-live-snapshot][data-pending='false']"
    assert_select "[data-player-echo]", "Ваше действие: Постучать"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "state endpoint never exposes a foreign game and guest must authenticate" do
    foreign = create_game_session
    complete_action(foreign, command: "Секретная команда")
    get game_state_path, params: { user_id: foreign.user_id, game_session_id: foreign.id }
    assert_not_includes response.body, "Секретная команда"
    delete logout_path
    get game_state_path
    assert_response :unauthorized
  end

  test "inventory frame renders only current players items and rejects guests" do
    @game.inventory.add_item!(code: "key", name: "Свой ключ")
    foreign = create_game_session
    foreign.inventory.add_item!(code: "secret", name: "Чужой ключ")
    get game_inventory_path, params: { game_session_id: foreign.id }
    assert_response :success
    assert_select "turbo-frame#inventory_contents"
    assert_select ".inventory-slot-filled strong", "Свой ключ"
    assert_not_includes response.body, "Чужой ключ"
    delete logout_path
    get game_inventory_path
    assert_response :unauthorized
  end

  test "lost async job expires safely and player may submit another command" do
    live_command("Потерянная команда")
    request = @game.ai_requests.sole
    request.update_columns(updated_at: 4.minutes.ago)
    get game_state_path
    assert request.reload.failed?
    assert request.player_action.reload.cancelled?
    assert_select "[data-live-snapshot][data-failed='true']"
    assert_no_difference "StoryTurn.count" do
      NarrationJob.perform_now(request.id)
    end
    live_command("Снова осмотреться")
    assert_response :accepted
  end

  test "deleted game job is harmless after restart" do
    live_command("Идти")
    request_id = @game.ai_requests.sole.id
    post start_game_path, params: { replace_game_session_id: @game.id }
    assert_redirected_to game_path
    assert_no_difference "StoryTurn.count" do
      NarrationJob.perform_now(request_id)
    end
  end

  test "asynchronous provider error preserves history and permits a retry" do
    complete_action(@game)
    previous = Rails.configuration.x.narration_provider
    failing = Class.new do
      def name = "test"
      def model_identifier = "test"
      def call(payload:) = raise(Timeout::Error, "private-provider-token")
    end.new
    Rails.configuration.x.narration_provider = failing
    live_command("Постучать")
    perform_enqueued_jobs
    assert_equal 1, @game.story_turns.count
    assert @game.ai_requests.reorder(id: :desc).first.failed?
    get game_state_path
    assert_select "[data-failed='true'][data-retry-command='Постучать']"
    assert_not_includes response.body, "private-provider-token"
    Rails.configuration.x.narration_provider = nil
    live_command("Постучать")
    assert_response :accepted
    perform_enqueued_jobs
    assert_equal 2, @game.story_turns.count
  ensure
    Rails.configuration.x.narration_provider = previous
  end

  test "stored successful response is recovered after interrupted acceptance without calling provider" do
    action = @game.submit_action!(command: "Идти")
    request = successful_request(action, response: { "narration" => "Вы дошли до моста.", "summary" => "Герой у моста" })
    action.update_columns(updated_at: 4.minutes.ago)
    get game_state_path
    assert_response :success
    assert action.reload.completed?
    assert request.reload.succeeded?
    assert_equal "Герой у моста", @game.summary
    assert_select "[data-story-text]", "Вы дошли до моста."
  end

  test "enqueue failure cancels prepared action instead of leaving the game blocked" do
    previous = NarrationJob.queue_adapter
    NarrationJob.queue_adapter = BrokenQueueAdapter.new
    live_command("Осмотреться")
    assert_response :service_unavailable
    assert @game.player_actions.sole.cancelled?
    assert @game.ai_requests.sole.failed?
    assert_not_includes response.body, "private-queue-details"
  ensure
    NarrationJob.queue_adapter = previous
  end

  private

  def live_command(command)
    post game_path, params: { command: command, game_session_id: @game.id }, as: :json, headers: { "X-RPI-Live" => "1" }
  end
end
