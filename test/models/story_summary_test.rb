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

  test "rejects missing negative and unfinished history boundaries" do
    unfinished = @game.submit_action!(command: "Идти")
    summary = @game.story_summaries.build(content: "Память", version: 2)
    [ nil, -1, unfinished.position, 999 ].each do |position|
      summary.through_position = position
      assert_not summary.valid?
      assert summary.errors[:through_position].any?
    end
  end

  test "version is unique within session but independent across sessions" do
    duplicate = @game.latest_summary.dup
    assert_not duplicate.valid?
    duplicate.assign_attributes(game_session: create_game_session, through_position: 0)
    assert duplicate.valid?
  end

  test "foreign history cannot supply a missing boundary in this session" do
    foreign_action = complete_action(create_game_session)
    foreign_action = complete_action(foreign_action.game_session)
    summary = @game.story_summaries.build(content: "Чужая память", version: 2, through_position: foreign_action.position)

    assert_not summary.valid?
    assert summary.errors[:through_position].any?
  end

  test "regeneration appends a version for the same completed action" do
    previous = @game.latest_summary
    updated = @game.add_summary!(content: "Уточнённая память", through_position: @action.position)
    assert_equal previous.version + 1, updated.version
    assert_equal [ @action.position, @action.position ], @game.story_summaries.order(:version).pluck(:through_position)
    assert_equal previous.content, previous.reload.content
    assert_equal "Уточнённая память", @game.summary
  end

  test "foreign summary cannot be removed and oversized content is rejected" do
    other = create_game_session.add_summary!(content: "Чужая память")
    assert_raises(ActiveRecord::RecordNotFound) { @game.remove_summary!(other) }
    assert_raises(ActiveRecord::RecordInvalid) { @game.add_summary!(content: "x" * 20_001) }
  end
end
