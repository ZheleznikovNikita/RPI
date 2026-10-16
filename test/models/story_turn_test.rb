require "test_helper"

class StoryTurnTest < ActiveSupport::TestCase
  setup do
    user = User.create!(name: "Игрок", email: "turn@example.com", password: "Lantern!Orbit7Cedar", password_confirmation: "Lantern!Orbit7Cedar")
    @adventure = user.start_adventure!(title: "Тропа")
    @turn = @adventure.story_turns.build(position: 1, command: "Осмотреться", response: { "narration" => "Вы у ворот", "summary" => "Герой у ворот" })
  end

  # Response contract and presentation
  test "reads narration from persisted JSON" do
    @turn.save!
    assert_equal "Вы у ворот", @turn.reload.narration
    assert_kind_of Hash, @turn.response
  end

  test "rejects non object responses missing fields and oversized memory" do
    [ nil, [], "text", {}, { "narration" => 5, "summary" => "x" }, { "narration" => "x", "summary" => " " }, { "narration" => "x", "summary" => "x" * 20_001 } ].each do |response|
      @turn.response = response
      assert_not @turn.valid?
      assert @turn.errors[:response].any?
    end
  end

  # Command and ordering
  test "requires an adventure command and positive integer position" do
    @turn.assign_attributes(adventure: nil, command: "", position: 0)
    assert_not @turn.valid?
    %i[adventure command position].each { |field| assert @turn.errors[field].any? }
  end

  test "positions are unique within an adventure but may repeat in another" do
    @turn.save!
    duplicate = @turn.dup
    assert_not duplicate.valid?
    duplicate.adventure = @adventure.user.start_adventure!(title: "Другой путь")
    assert duplicate.valid?
  end
end
