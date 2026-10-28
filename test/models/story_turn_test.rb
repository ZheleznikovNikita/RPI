require "test_helper"

class StoryTurnTest < ActiveSupport::TestCase
  setup do
    @action = create_game_session.submit_action!(command: "Осмотреться")
    @request = successful_request(@action)
    @turn = @request.build_story_turn(narration: "Вы нашли тропу")
  end

  test "stores narrative linked to its action request and session" do
    @turn.save!
    assert_equal "Вы нашли тропу", @turn.reload.narration
    assert_equal @action.game_session, @turn.game_session
    assert_equal @action, @turn.player_action
    assert_equal @request, @turn.ai_request
  end

  test "requires nonempty bounded narration" do
    [ nil, " ", "x" * 20_001 ].each do |narration|
      @turn.narration = narration
      assert_not @turn.valid?
      assert @turn.errors[:narration].any?
    end
  end

  test "action and session are derived only from the source request" do
    @turn.ai_request = successful_request(create_game_session.submit_action!(command: "Идти"))
    @turn.save!
    assert_equal @turn.ai_request.player_action, @turn.reload.player_action
    assert_equal @turn.ai_request.game_session, @turn.game_session
    assert_not_equal @action, @turn.player_action
  end

  test "narration must match the accepted request response" do
    @turn.narration = "Подменённый текст"
    assert_not @turn.valid?
    assert @turn.errors[:narration].any?
  end

  test "pending failed image and summary requests cannot supply a story turn" do
    pending = @action.request_ai!(purpose: "narration", provider: "test", model_identifier: "model", payload: { "prompt" => "История" })
    @turn.ai_request = pending
    assert_not @turn.valid?
    assert @turn.errors[:ai_request].any?

    pending.fail!(message: "Timeout")
    image = successful_request(@action, purpose: "image", response: { "image_url" => "https://example.test/image.png" })
    summary = successful_request(@action, purpose: "summary", response: { "summary" => "Память" })

    [ pending, image, summary ].each do |request|
      @turn.ai_request = request
      assert_not @turn.valid?
      assert @turn.errors[:ai_request].any?
    end
  end

  test "different attempts of one action cannot supply multiple accepted turns" do
    @turn.save!
    alternative = successful_request(@action, response: { "narration" => "Другой вариант" })
    duplicate = alternative.build_story_turn(narration: "Другой вариант")

    assert_raises(ActiveRecord::RecordInvalid) { duplicate.save! }
    assert_equal @request, @action.reload.story_turn.ai_request
    assert_nil alternative.reload.story_turn
  end

  test "database prevents storing two turns for one request" do
    @turn.save!
    attributes = @turn.attributes.except("id")

    assert_raises(ActiveRecord::RecordNotUnique) { StoryTurn.insert_all!([ attributes ]) }
  end

  test "only one turn can be applied to an action and a request" do
    @turn.save!
    duplicate = @turn.dup
    assert_not duplicate.valid?
    assert duplicate.errors[:ai_request_id].any?
    assert duplicate.errors[:ai_request].any?
  end

  test "deleting a request removes its narrative through the ownership chain" do
    @turn.save!
    assert_difference "StoryTurn.count", -1 do
      @request.destroy!
    end
    assert_nil @action.reload.story_turn
  end
end
