require "test_helper"

class DataRelationshipsTest < ActiveSupport::TestCase
  test "foreign keys form a tree without undirected cycles" do
    connection = ActiveRecord::Base.connection
    tables = %w[users game_sessions inventories inventory_items player_actions ai_requests story_turns story_summaries]
    roots = tables.index_with { |table| table }
    root = ->(table) { roots[table] == table ? table : root.call(roots.fetch(table)) }
    edge_count = 0

    tables.each do |table|
      connection.foreign_keys(table).each do |foreign_key|
        from = root.call(table)
        to = root.call(foreign_key.to_table)
        assert_not_equal from, to, "Cycle at #{table} → #{foreign_key.to_table}"
        roots[from] = to
        edge_count += 1
      end
    end

    assert_equal tables.length - 1, edge_count
    assert_equal 1, tables.map { |table| root.call(table) }.uniq.size
    assert_not_includes StorySummary.column_names, "player_action_id"
    assert_not_includes StoryTurn.column_names, "player_action_id"
  end
end
