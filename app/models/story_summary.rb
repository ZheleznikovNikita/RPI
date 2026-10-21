class StorySummary < ApplicationRecord
  belongs_to :game_session
  belongs_to :player_action, optional: true

  validates :content, presence: true, length: { maximum: 20_000 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :game_session_id }
  validate :completed_action_in_same_session

  private

  def completed_action_in_same_session
    return unless player_action

    unless player_action.game_session_id == game_session_id && player_action.completed?
      errors.add(:player_action, "должно быть завершённым действием этой игровой сессии")
    end
  end
end
