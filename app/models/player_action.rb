class PlayerAction < ApplicationRecord
  belongs_to :game_session
  has_many :ai_requests, dependent: :destroy
  has_many :story_turns, through: :ai_requests

  enum :status, { pending: "pending", completed: "completed", cancelled: "cancelled" }, validate: true
  validates :command, presence: true, length: { maximum: 2_000 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :game_session_id }
  validates :game_session_id, uniqueness: { conditions: -> { pending } }, if: :pending?

  def story_turn
    story_turns.first
  end

  def request_ai!(purpose:, provider:, model_identifier:, payload:)
    game_session.with_lock do
      reload
      ensure_request_allowed!(purpose.to_s)
      ai_requests.create!(purpose: purpose, provider: provider, model_identifier: model_identifier, request_payload: payload)
    end
  end

  # Applying an AI result and advancing the plot must succeed or roll back together.
  def complete!(request:, summary:)
    game_session.with_lock do
      reload
      source = ai_requests.find(request.id)
      return story_turn if completed? && story_turn&.ai_request_id == source.id

      game_session.ensure_active!
      ensure_pending!
      narration = source.response_payload["narration"] if source.response_payload.is_a?(Hash)
      turn = source.create_story_turn!(narration: narration)
      update!(status: :completed)
      game_session.add_summary!(content: summary, through_position: position)
      turn
    end
  end

  def cancel!
    game_session.with_lock do
      reload
      game_session.ensure_active!
      ensure_pending!
      if ai_requests.where(status: %w[pending running]).exists?
        errors.add(:base, "Сначала завершите или отметьте ошибкой активные запросы")
        raise ActiveRecord::RecordInvalid, self
      end
      update!(status: :cancelled)
    end
    self
  end

  def ensure_request_allowed!(purpose)
    game_session.reload.ensure_active!
    reload
    return if pending? || (completed? && %w[image summary].include?(purpose))

    errors.add(:base, "Нельзя отправить запрос для этого действия")
    raise ActiveRecord::RecordInvalid, self
  end

  private

  def ensure_pending!
    return if pending?

    errors.add(:status, "действие уже обработано")
    raise ActiveRecord::RecordInvalid, self
  end
end
