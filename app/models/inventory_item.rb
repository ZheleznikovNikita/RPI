class InventoryItem < ApplicationRecord
  belongs_to :inventory

  normalizes :code, with: ->(value) { value.strip.downcase }
  validates :code, presence: true, length: { maximum: 80 },
    format: { with: /\A[a-z0-9][a-z0-9_-]*\z/ }, uniqueness: { scope: :inventory_id }
  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
  validates :quantity, numericality: { only_integer: true, in: 1..1_000_000 }
end
