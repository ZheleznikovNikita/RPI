class AiRequest < ApplicationRecord
  belongs_to :player_action
  has_one :story_turn, dependent: :destroy
  has_one :game_session, through: :player_action

  enum :purpose, { narration: "narration", summary: "summary", image: "image" }, prefix: true, validate: true
  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

  validates :provider, presence: true, length: { maximum: 100 }
  validates :model_identifier, presence: true, length: { maximum: 200 }
  validates :purpose, uniqueness: { scope: :player_action_id, conditions: -> { where(status: %w[pending running]) } }, if: -> { pending? || running? }
  validates :error_message, presence: true, if: :failed?
  validates :error_message, length: { maximum: 2_000 }
  validates :started_at, presence: true, if: -> { running? || succeeded? }
  validates :finished_at, presence: true, if: -> { succeeded? || failed? }
  validate :payload_contract
  validate :available_action, on: :create

  def start!
    with_lock do
      ensure_status!(:pending)
      player_action.ensure_request_allowed!(purpose)
      update!(status: :running, started_at: Time.current)
    end
    self
  end

  def succeed!(response:)
    with_lock do
      ensure_status!(:running)
      update!(status: :succeeded, response_payload: response, finished_at: Time.current)
    end
    self
  end

  def fail!(message:)
    with_lock do
      ensure_status!(:pending, :running)
      update!(status: :failed, error_message: message, finished_at: Time.current)
    end
    self
  end

  def retry!
    with_lock do
      ensure_status!(:failed)
      player_action.request_ai!(purpose: purpose, provider: provider, model_identifier: model_identifier, payload: request_payload.deep_dup)
    end
  end

  private

  def available_action
    return unless player_action

    if player_action.cancelled? || !player_action.game_session.active? || (purpose_narration? && player_action.completed?)
      errors.add(:player_action, "не принимает новые запросы этого типа")
    end
  end

  def ensure_status!(*allowed)
    return if allowed.map(&:to_s).include?(status)

    errors.add(:status, "недопустимый переход состояния")
    raise ActiveRecord::RecordInvalid, self
  end

  def payload_contract
    errors.add(:request_payload, "должен быть непустым JSON-объектом") unless request_payload.is_a?(Hash) && request_payload.present?
    return unless succeeded?

    key = { "narration" => "narration", "summary" => "summary", "image" => "image_url" }[purpose]
    value = response_payload[key] if response_payload.is_a?(Hash) && key
    unless value.is_a?(String) && value.present? && value.length <= 20_000
      errors.add(:response_payload, "должен содержать непустую строку #{key} длиной до 20000 символов")
    end
  end
end
