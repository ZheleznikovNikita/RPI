require "test_helper"

class StorySummaryTest < ActiveSupport::TestCase
  setup do
    @game = create_game_session
    @action = complete_action(@game)
  end

  test "validates text version and session" do
    summary = StorySummary.new(content: " ", version: 0)
    assert_not summary.valid?
    %i[content version game_session].each { |field| assert summary.errors[field].any? }
  end

  test "rejects foreign and unfinished source actions" do
    summary = @game.story_summaries.build(content: "Память", version: 2, player_action: create_game_session.submit_action!(command: "Идти"))
    assert_not summary.valid?
    assert summary.errors[:player_action].any?
    summary.player_action = @game.submit_action!(command: "Идти")
    assert_not summary.valid?
  end

  test "version is unique within session but independent across sessions" do
    duplicate = @game.latest_summary.dup
    assert_not duplicate.valid?
    duplicate.assign_attributes(game_session: create_game_session, player_action: nil)
    assert duplicate.valid?
  end

  test "regeneration appends a version for the same completed action" do
    previous = @game.latest_summary
    updated = @game.add_summary!(content: "Уточнённая память", player_action: @action)
    assert_equal previous.version + 1, updated.version
    assert_equal previous.content, previous.reload.content
    assert_equal "Уточнённая память", @game.summary
  end

  test "foreign summary cannot be removed and oversized content is rejected" do
    other = create_game_session.add_summary!(content: "Чужая память")
    assert_raises(ActiveRecord::RecordNotFound) { @game.remove_summary!(other) }
    assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "x" * 20_001, player_action: @action) }
  end
end
