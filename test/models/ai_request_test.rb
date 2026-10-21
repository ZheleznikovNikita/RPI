require "test_helper"

class AiRequestTest < ActiveSupport::TestCase
  setup do
    @action = create_game_session.submit_action!(command: "Осмотреться")
    @request = @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "test-model", payload: { "prompt" => "История" })
  end

  test "requires provider model purpose status and object payload" do
    @request.assign_attributes(provider: "", model_identifier: "", purpose: "unknown", status: "unknown", request_payload: [])
    assert_not @request.valid?
    %i[provider model_identifier purpose status request_payload].each { |field| assert @request.errors[field].any? }
  end

  test "transitions from pending through running to success with timestamps" do
    assert @request.pending?
    @request.start!
    assert @request.running?
    assert @request.started_at
    @request.succeed!(response: { "narration" => "Тропа уходит в лес" })
    assert @request.reload.succeeded?
    assert @request.finished_at >= @request.started_at
  end

  test "invalid response leaves running request unchanged in database" do
    @request.start!
    [ nil, [], { "narration" => 12 }, { "narration" => " " }, { "narration" => "x" * 20_001 } ].each do |payload|
      assert_raises(ActiveRecord::RecordInvalid) { @request.succeed!(response: payload) }
      assert @request.reload.running?
      assert_nil @request.finished_at
    end
  end

  test "failure keeps diagnostic and retry creates a separate attempt" do
    @request.start!
    @request.fail!(message: "Timeout")
    retried = @request.retry!
    assert_not_equal @request.id, retried.id
    assert retried.pending?
    assert_equal @request.request_payload, retried.request_payload
    assert @request.reload.failed?
    assert_equal "Timeout", @request.error_message
  end

  test "terminal requests cannot be restarted completed or failed again" do
    assert_raises(ActiveRecord::RecordInvalid) { @request.succeed!(response: { "narration" => "Рано" }) }
    @request.reload.fail!(message: "Timeout")
    assert_raises(ActiveRecord::RecordInvalid) { @request.start! }
    assert_raises(ActiveRecord::RecordInvalid) { @request.fail!(message: "Другая ошибка") }
  end

  test "only one in flight attempt per purpose is allowed" do
    assert_no_difference "AiRequest.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "m", payload: { "prompt" => "x" }) }
    end
    image = @action.request_ai!(purpose: "image", provider: "test", model_identifier: "m", payload: { "prompt" => "Лес" })
    assert image.purpose_image?
  end

  test "summary and image purposes have their own response contract" do
    summary = successful_request(@action, purpose: "summary", response: { "summary" => "Герой в лесу" })
    image = successful_request(@action, purpose: "image", response: { "image_url" => "https://example.test/forest.png" })
    assert summary.succeeded?
    assert image.succeeded?
    assert_equal 3, @action.ai_requests.count
  end

  test "diagnostic is required for a failed request" do
    assert_raises(ActiveRecord::RecordInvalid) { @request.fail!(message: " ") }
    assert @request.reload.pending?
  end

  test "database rejects two in flight attempts even when validations are bypassed" do
    attributes = @request.attributes.except("id")
    assert_raises(ActiveRecord::RecordNotUnique) { AiRequest.insert_all!([ attributes ]) }
    assert_equal 1, @action.ai_requests.purpose_narration.count
  end
end
