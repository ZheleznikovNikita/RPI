class Inventory < ApplicationRecord
  belongs_to :game_session
  has_many :inventory_items, dependent: :destroy

  validates :game_session_id, uniqueness: true

  def add_item!(code:, name:, quantity: 1, description: "")
    validate_quantity!(quantity)
    game_session.with_lock do
      game_session.ensure_active!
      item = inventory_items.find_or_initialize_by(code: code.to_s.strip.downcase)
      item.assign_attributes(name: name, description: description, quantity: 0) if item.new_record?
      item.quantity += quantity
      item.save!
      item
    end
  end

  def remove_item!(code:, quantity: 1)
    validate_quantity!(quantity)
    game_session.with_lock do
      game_session.ensure_active!
      item = inventory_items.find_by!(code: code.to_s.strip.downcase)
      if item.quantity < quantity
        item.errors.add(:quantity, "недостаточно предметов")
        raise ActiveRecord::RecordInvalid, item
      end

      if item.quantity == quantity
        item.destroy!
      else
        item.update!(quantity: item.quantity - quantity)
      end
      item
    end
  end

  private

  def validate_quantity!(quantity)
    raise ArgumentError, "Количество должно быть положительным целым числом" unless quantity.is_a?(Integer) && quantity.positive?
  end
end
