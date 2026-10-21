require "test_helper"

class PlayerActionTest < ActiveSupport::TestCase
  setup do
    @game = create_game_session
    @action = @game.submit_action!(command: "Осмотреть ворота")
  end

  test "validates command ordering ownership and status" do
    @action.assign_attributes(command: "", position: 0, game_session: nil, status: "unknown")
    assert_not @action.valid?
    %i[command position game_session status].each { |field| assert @action.errors[field].any? }
  end

  test "applying a successful request stores turn memory and completion atomically" do
    request = successful_request(@action)
    assert_difference [ "StoryTurn.count", "StorySummary.count" ], 1 do
      turn = @action.complete!(request: request, summary: "Герой осмотрел ворота")
      assert_equal request, turn.ai_request
      assert_equal "Вы нашли тропу", turn.narration
    end
    assert @action.reload.completed?
    assert_equal "Герой осмотрел ворота", @game.summary
  end

  test "invalid memory rolls back an already inserted turn and action status" do
    request = successful_request(@action)
    assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { @action.complete!(request: request, summary: " ") }
    end
    assert @action.reload.pending?
    assert_nil @action.reload.story_turn
    assert request.reload.succeeded?
    assert_equal "", @game.summary
  end

  test "repeated application of the same response does not duplicate a turn" do
    request = successful_request(@action)
    turn = @action.complete!(request: request, summary: "Память")
    assert_no_difference [ "StoryTurn.count", "StorySummary.count" ] do
      assert_equal turn, @action.complete!(request: request, summary: "Не применяется")
    end
    assert_equal "Память", @game.summary
  end

  test "another successful response cannot replace an applied turn" do
    first = successful_request(@action)
    second = successful_request(@action, response: { "narration" => "Другая версия" })
    @action.complete!(request: first, summary: "Память")
    assert_raises(ActiveRecord::RecordInvalid) { @action.complete!(request: second, summary: "Подмена") }
    assert_equal first, @action.reload.story_turn.ai_request
    assert_equal "Память", @action.game_session.summary
  end

  test "rejects foreign pending and image requests" do
    foreign = successful_request(create_game_session.submit_action!(command: "Идти"))
    assert_raises(ActiveRecord::RecordNotFound) { @action.complete!(request: foreign, summary: "Чужое") }
    pending = @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "model", payload: { "prompt" => "test" })
    assert_raises(ActiveRecord::RecordInvalid) { @action.complete!(request: pending, summary: "Рано") }
    image = successful_request(@action, purpose: "image", response: { "image_url" => "https://example.test/image.png" })
    assert_raises(ActiveRecord::RecordInvalid) { @action.complete!(request: image, summary: "Изображение не рассказ") }
    assert @action.reload.pending?
  end

  test "cancellation rejects active requests but permits a failed request" do
    request = @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "model", payload: { "prompt" => "test" })
    assert_raises(ActiveRecord::RecordInvalid) { @action.cancel! }
    request.fail!(message: "Ошибка сети")
    @action.cancel!
    assert @action.reload.cancelled?
    assert_raises(ActiveRecord::RecordInvalid) { request.retry! }
  end

  test "completed narration cannot be generated again but image and summary requests are separate" do
    @action.complete!(request: successful_request(@action), summary: "Память")
    assert_raises(ActiveRecord::RecordInvalid) { @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "m", payload: { "prompt" => "x" }) }
    %w[image summary].each do |purpose|
      assert @action.request_ai!(purpose: purpose, provider: "test", model_identifier: "m", payload: { "prompt" => "x" }).persisted?
    end
  end
end
