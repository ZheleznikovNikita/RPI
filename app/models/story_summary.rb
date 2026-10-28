class StorySummary < ApplicationRecord
  belongs_to :game_session

  validates :content, presence: true, length: { maximum: 20_000 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :game_session_id }
  validates :through_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :completed_history_boundary

  private

  def completed_history_boundary
    return unless game_session && through_position&.positive?

    unless game_session.player_actions.completed.exists?(position: through_position)
      errors.add(:through_position, "должна указывать границу завершённой истории этой сессии")
    end
  end
end
