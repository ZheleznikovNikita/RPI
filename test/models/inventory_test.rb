require "test_helper"

class InventoryTest < ActiveSupport::TestCase
  setup { @inventory = create_game_session.inventory }

  test "adds and stacks items with the same normalized code" do
    first = @inventory.add_item!(code: " Potion ", name: "Зелье", quantity: 2, description: "Восстанавливает здоровье")
    second = @inventory.add_item!(code: "potion", name: "Другое имя", quantity: 3)
    assert_equal first.id, second.id
    assert_equal 5, first.reload.quantity
    assert_equal "Зелье", first.name
    assert_equal "Восстанавливает здоровье", first.description
    assert_equal 1, @inventory.inventory_items.count
  end

  test "partially removes a stack and deletes it when exhausted" do
    item = @inventory.add_item!(code: "potion", name: "Зелье", quantity: 3)
    @inventory.remove_item!(code: " POTION ", quantity: 2)
    assert_equal 1, item.reload.quantity
    @inventory.remove_item!(code: "potion")
    assert_not InventoryItem.exists?(item.id)
  end

  test "invalid removal does not change a stack" do
    item = @inventory.add_item!(code: "potion", name: "Зелье", quantity: 2)
    assert_raises(ActiveRecord::RecordInvalid) { @inventory.remove_item!(code: "potion", quantity: 3) }
    assert_raises(ActiveRecord::RecordNotFound) { @inventory.remove_item!(code: "missing") }
    assert_equal 2, item.reload.quantity
  end

  test "quantities must be positive integers for both operations" do
    [ 0, -1, 1.5, "2", nil ].each do |quantity|
      assert_raises(ArgumentError) { @inventory.add_item!(code: "key", name: "Ключ", quantity: quantity) }
      assert_raises(ArgumentError) { @inventory.remove_item!(code: "key", quantity: quantity) }
    end
    assert_empty @inventory.inventory_items
  end

  test "failed addition rolls back stack changes" do
    item = @inventory.add_item!(code: "coin", name: "Монета", quantity: 1_000_000)
    assert_raises(ActiveRecord::RecordInvalid) { @inventory.add_item!(code: "coin", name: "Монета") }
    assert_equal 1_000_000, item.reload.quantity
    assert_no_difference "InventoryItem.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @inventory.add_item!(code: "", name: "") }
    end
  end

  test "items in different sessions are isolated" do
    own = @inventory.add_item!(code: "key", name: "Мой ключ", quantity: 2)
    other = create_game_session.inventory
    foreign = other.add_item!(code: "key", name: "Чужой ключ", quantity: 3)
    @inventory.remove_item!(code: "key")
    assert_equal 1, own.reload.quantity
    assert_equal 3, foreign.reload.quantity
  end

  test "completed session cannot mutate its inventory" do
    @inventory.add_item!(code: "key", name: "Ключ")
    @inventory.game_session.finish!
    assert_raises(ActiveRecord::RecordInvalid) { @inventory.remove_item!(code: "key") }
    assert_raises(ActiveRecord::RecordInvalid) { @inventory.add_item!(code: "key", name: "Ключ") }
  end

  test "only one inventory belongs to a session" do
    assert_not Inventory.new(game_session: @inventory.game_session).valid?
  end
end
