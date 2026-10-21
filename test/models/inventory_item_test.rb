require "test_helper"

class InventoryItemTest < ActiveSupport::TestCase
  setup { @inventory = create_game_session.inventory }

  test "validates identity owner and quantity" do
    item = InventoryItem.new(code: "bad code", name: "", quantity: 0)
    assert_not item.valid?
    %i[inventory code name quantity].each { |field| assert item.errors[field].any? }
  end

  test "limits code name description and stack size" do
    item = @inventory.inventory_items.build(code: "x" * 81, name: "x" * 121, description: "x" * 2_001, quantity: 1_000_001)
    assert_not item.valid?
    %i[code name description quantity].each { |field| assert item.errors[field].any? }
  end

  test "code uniqueness is local to the inventory" do
    @inventory.add_item!(code: "key", name: "Ключ")
    duplicate = @inventory.inventory_items.build(code: " KEY ", name: "Ключ", quantity: 1)
    assert_not duplicate.valid?
    duplicate.inventory = create_game_session.inventory
    assert duplicate.valid?
    assert_equal "key", duplicate.code
  end

  test "database enforces positive stack quantities even when validations are skipped" do
    item = @inventory.add_item!(code: "key", name: "Ключ")
    assert_raises(ActiveRecord::StatementInvalid) { item.update_columns(quantity: 0) }
    assert_equal 1, item.reload.quantity
  end
end
