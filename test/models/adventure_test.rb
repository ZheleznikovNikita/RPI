require "test_helper"

class AdventureTest < ActiveSupport::TestCase
  setup do
    user = User.create!(name: "Игрок", email: "adventure@example.com", password: "Lantern!Orbit7Cedar", password_confirmation: "Lantern!Orbit7Cedar")
    @adventure = user.start_adventure!(title: "Тропа")
    @response = { "narration" => "Вы нашли тропу", "summary" => "Герой вышел на тропу" }
  end

  # Validation and defaults
  test "starts with full stats and requires valid ownership title and ranges" do
    assert_equal [ 100, 100, "active", "" ], @adventure.attributes.values_at("health", "stamina", "status", "summary")
    @adventure.assign_attributes(user: nil, title: "", health: -1, stamina: 101, status: "unknown")
    assert_not @adventure.valid?
    %i[user title health stamina status].each { |field| assert @adventure.errors[field].any? }
  end

  # Transactional story persistence
  test "records consecutive turns and replaces memory with latest summary" do
    first = @adventure.record_turn!(command: "Осмотреться", response: @response)
    second = @adventure.record_turn!(command: "Идти", response: @response.merge("summary" => "Герой идёт дальше"))
    assert_equal [ 1, 2 ], [ first.position, second.position ]
    assert_equal "Герой идёт дальше", @adventure.reload.summary
    assert_equal [ first, second ], @adventure.story_turns.to_a
  end

  test "invalid response leaves both history and summary unchanged" do
    @adventure.record_turn!(command: "Идти", response: @response)
    assert_no_difference "StoryTurn.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @adventure.record_turn!(command: "Идти", response: { "summary" => "Потеря" }) }
    end
    assert_equal @response["summary"], @adventure.reload.summary
  end

  # Lifecycle
  test "finished adventure rejects further turns" do
    @adventure.finish!
    assert @adventure.reload.completed?
    assert_no_difference "StoryTurn.count" do
      error = assert_raises(ActiveRecord::RecordInvalid) { @adventure.record_turn!(command: "Идти", response: @response) }
      assert_includes error.record.errors[:base], "Приключение завершено"
    end
  end
end
