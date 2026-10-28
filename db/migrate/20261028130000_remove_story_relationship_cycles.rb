class RemoveStoryRelationshipCycles < ActiveRecord::Migration[8.1]
  def up
    verify_existing_ownership!

    add_column :story_summaries, :through_position, :integer, null: false, default: 0
    execute <<~SQL
      UPDATE story_summaries
      SET through_position = COALESCE(
        (SELECT position FROM player_actions WHERE player_actions.id = story_summaries.player_action_id), 0
      )
    SQL
    add_check_constraint :story_summaries, "through_position >= 0", name: "story_summaries_through_position_nonnegative"
    remove_reference :story_summaries, :player_action, foreign_key: true
    remove_reference :story_turns, :player_action, foreign_key: true
  end

  def down
    add_reference :story_summaries, :player_action, foreign_key: true
    add_reference :story_turns, :player_action, foreign_key: true, index: { unique: true }
    execute <<~SQL
      UPDATE story_summaries
      SET player_action_id = (
        SELECT id FROM player_actions
        WHERE player_actions.game_session_id = story_summaries.game_session_id
          AND player_actions.position = story_summaries.through_position
      )
    SQL
    execute <<~SQL
      UPDATE story_turns
      SET player_action_id = (SELECT player_action_id FROM ai_requests WHERE ai_requests.id = story_turns.ai_request_id)
    SQL
    change_column_null :story_turns, :player_action_id, false
    remove_check_constraint :story_summaries, name: "story_summaries_through_position_nonnegative"
    remove_column :story_summaries, :through_position
  end

  private

  def verify_existing_ownership!
    invalid_turn = select_value(<<~SQL)
      SELECT story_turns.id FROM story_turns
      LEFT JOIN ai_requests ON ai_requests.id = story_turns.ai_request_id
      WHERE ai_requests.id IS NULL OR ai_requests.player_action_id != story_turns.player_action_id
      LIMIT 1
    SQL
    invalid_summary = select_value(<<~SQL)
      SELECT story_summaries.id FROM story_summaries
      LEFT JOIN player_actions ON player_actions.id = story_summaries.player_action_id
      WHERE story_summaries.player_action_id IS NOT NULL
        AND (player_actions.id IS NULL OR player_actions.game_session_id != story_summaries.game_session_id)
      LIMIT 1
    SQL
    if invalid_turn || invalid_summary
      raise ActiveRecord::MigrationError, "Обнаружены противоречивые связи истории. Исправьте их перед изменением схемы."
    end
  end
end
