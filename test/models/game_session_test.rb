require "test_helper"

class GameSessionTest < ActiveSupport::TestCase
  setup { @game = create_game_session }

  test "creates an isolated empty inventory and full stats" do
    assert_equal [ 100, 100, "active", "" ], [ @game.health, @game.stamina, @game.status, @game.summary ]
    assert_equal @game, @game.inventory.game_session
    assert_empty @game.inventory.inventory_items
  end

  test "validates owner title stats status and completion timestamp" do
    @game.assign_attributes(user: nil, title: "", health: -1, stamina: 101, status: "unknown")
    assert_not @game.valid?
    %i[user title health stamina status].each { |field| assert @game.errors[field].any? }
    @game.reload.assign_attributes(status: :completed)
    assert_not @game.valid?
    assert @game.errors[:completed_at].any?
  end

  test "only one pending action can exist and invalid commands do not consume a position" do
    assert_raises(ActiveRecord::RecordInvalid) { @game.submit_action!(command: " ") }
    first = @game.submit_action!(command: "Идти")
    assert_equal 1, first.position
    assert_raises(ActiveRecord::RecordInvalid) { @game.submit_action!(command: "Бежать") }
    first.cancel!
    assert_equal 2, @game.submit_action!(command: "Бежать").position
  end

  test "completed turns append memory rather than overwriting it" do
    first = complete_action(@game, summary: "Герой у ворот")
    second = complete_action(@game, summary: "Герой в лесу")
    assert_equal [ 1, 2 ], @game.player_actions.pluck(:position)
    assert_equal [ "Герой у ворот", "Герой в лесу" ], @game.story_summaries.order(:version).pluck(:content)
    assert_equal second.position, @game.latest_summary.through_position
    assert_equal "Герой в лесу", @game.summary
    assert_equal [ first.story_turn, second.story_turn ], @game.story_turns.to_a
  end

  test "latest summary can be removed and earlier memory is restored" do
    complete_action(@game, summary: "Первая память")
    complete_action(@game, summary: "Вторая память")
    assert_raises(ActiveRecord::RecordInvalid) { @game.remove_summary!(@game.story_summaries.order(:version).first) }
    @game.remove_summary!(@game.latest_summary)
    assert_equal "Первая память", @game.summary
  end

  test "summary cannot regress to an earlier history boundary" do
    first = complete_action(@game)
    complete_action(@game)
    assert_no_difference "StorySummary.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "Старое", through_position: first.position) }
      assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "Старое", through_position: first.position.to_s) }
      assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "Предыстория", through_position: 0) }
    end
  end

  test "initial memory can exist before the first action" do
    memory = @game.add_summary!(content: "Предыстория")
    assert_equal 0, memory.through_position
    assert_equal 1, memory.version
    assert_equal "Предыстория", @game.summary
  end

  test "summary without an explicit boundary covers the latest completed action" do
    completed = complete_action(@game)
    @game.submit_action!(command: "Ещё не обработано")
    summary = @game.add_summary!(content: "Уточнённая память")
    assert_equal completed.position, summary.through_position
  end

  test "finishing records completion and disallows further mutations" do
    complete_action(@game)
    @game.finish!
    assert @game.reload.completed?
    assert @game.completed_at
    assert_raises(ActiveRecord::RecordInvalid) { @game.submit_action!(command: "Идти") }
    assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "Новое") }
    assert_raises(ActiveRecord::RecordInvalid) { @game.inventory.add_item!(code: "key", name: "Ключ") }
  end

  test "pending action prevents finishing" do
    @game.submit_action!(command: "Идти")
    assert_raises(ActiveRecord::RecordInvalid) { @game.finish! }
    assert @game.reload.active?
  end

  test "database prevents a second active session even without model validations" do
    attributes = @game.attributes.except("id").merge("title" => "Дубликат")
    assert_raises(ActiveRecord::RecordNotUnique) { GameSession.insert_all!([ attributes ]) }
    assert_equal 1, @game.user.game_sessions.active.count
  end

  test "pending image request prevents finishing even after narration was applied" do
    action = complete_action(@game)
    image = action.request_ai!(purpose: "image", provider: "test", model_identifier: "image", payload: { "prompt" => "Лес" })
    assert_raises(ActiveRecord::RecordInvalid) { @game.finish! }
    image.fail!(message: "Недоступен")
    assert @game.finish!.completed?
  end
end
