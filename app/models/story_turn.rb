class StoryTurn < ApplicationRecord
  belongs_to :ai_request
  has_one :player_action, through: :ai_request
  has_one :game_session, through: :player_action

  validates :ai_request_id, uniqueness: true
  validates :narration, presence: true, length: { maximum: 20_000 }
  validate :successful_narration_request
  validate :one_turn_per_action

  private

  def successful_narration_request
    return unless ai_request

    unless ai_request.purpose_narration? && ai_request.succeeded?
      errors.add(:ai_request, "должен быть успешным запросом рассказчика для этого действия")
    end
    if ai_request.response_payload.is_a?(Hash) && narration != ai_request.response_payload["narration"]
      errors.add(:narration, "должно совпадать с принятым ответом рассказчика")
    end
  end

  def one_turn_per_action
    return unless ai_request

    existing = StoryTurn.joins(:ai_request).where(ai_requests: { player_action_id: ai_request.player_action_id })
    existing = existing.where.not(id: id) if persisted?
    errors.add(:ai_request, "для этого действия уже принят рассказ") if existing.exists?
  end
end
