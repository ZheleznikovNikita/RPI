require "test_helper"

class StoryTurnTest < ActiveSupport::TestCase
  setup do
    @action = create_game_session.submit_action!(command: "Осмотреться")
    @request = successful_request(@action)
    @turn = @action.build_story_turn(ai_request: @request, narration: "Вы нашли тропу")
  end

  test "stores narrative linked to its action request and session" do
    @turn.save!
    assert_equal "Вы нашли тропу", @turn.reload.narration
    assert_equal @action.game_session, @turn.game_session
    assert_equal @request, @turn.ai_request
  end

  test "requires nonempty bounded narration" do
    [ nil, " ", "x" * 20_001 ].each do |narration|
      @turn.narration = narration
      assert_not @turn.valid?
      assert @turn.errors[:narration].any?
    end
  end

  test "rejects a request belonging to another action" do
    @turn.ai_request = successful_request(create_game_session.submit_action!(command: "Идти"))
    assert_not @turn.valid?
    assert @turn.errors[:ai_request].any?
  end

  test "narration must match the accepted request response" do
    @turn.narration = "Подменённый текст"
    assert_not @turn.valid?
    assert @turn.errors[:narration].any?
  end

  test "only one turn can be applied to an action and a request" do
    @turn.save!
    duplicate = @turn.dup
    assert_not duplicate.valid?
    assert duplicate.errors[:player_action_id].any?
    assert duplicate.errors[:ai_request_id].any?
    assert_raises(ActiveRecord::DeleteRestrictionError) { @request.destroy! }
  end
end
