class GameSession < ApplicationRecord
  belongs_to :user
  has_one :inventory, dependent: :destroy
  has_many :story_summaries, dependent: :destroy
  has_many :player_actions, -> { order(:position) }, dependent: :destroy
  has_many :ai_requests, through: :player_actions
  has_many :story_turns, through: :ai_requests

  after_create :create_inventory!

  enum :status, { active: "active", completed: "completed" }, validate: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :user_id, uniqueness: { conditions: -> { active } }, if: :active?
  validates :health, :stamina, numericality: { only_integer: true, in: 0..100 }
  validates :completed_at, presence: true, if: :completed?

  def latest_summary
    story_summaries.order(version: :desc).first
  end

  def summary
    latest_summary&.content.to_s
  end

  def submit_action!(command:)
    with_lock do
      ensure_active!
      if player_actions.pending.exists?
        errors.add(:base, "Сначала завершите или отмените предыдущее действие")
        raise ActiveRecord::RecordInvalid, self
      end
      player_actions.create!(command: command, position: (player_actions.maximum(:position) || 0) + 1)
    end
  end

  def add_summary!(content:, through_position: nil)
    with_lock do
      ensure_active!
      position = through_position.nil? ? (player_actions.completed.maximum(:position) || 0) : through_position
      record = story_summaries.build(content: content, through_position: position, version: (story_summaries.maximum(:version) || 0) + 1)
      previous = latest_summary
      if previous && record.through_position && record.through_position < previous.through_position
        errors.add(:base, "Нельзя заменить память сюжета саммэри более раннего действия")
        raise ActiveRecord::RecordInvalid, self
      end
      record.save!
      record
    end
  end

  def remove_summary!(story_summary)
    with_lock do
      ensure_active!
      record = story_summaries.find(story_summary.id)
      unless record == latest_summary
        errors.add(:base, "Удалять можно только последнюю версию саммэри")
        raise ActiveRecord::RecordInvalid, self
      end
      record.destroy!
    end
  end

  def finish!
    with_lock do
      ensure_active!
      if player_actions.pending.exists? || ai_requests.where(status: %w[pending running]).exists?
        errors.add(:base, "В сессии остались незавершённые действия или запросы")
        raise ActiveRecord::RecordInvalid, self
      end
      update!(status: :completed, completed_at: Time.current)
    end
    self
  end

  def ensure_active!
    return if active?

    errors.add(:base, "Игровая сессия завершена")
    raise ActiveRecord::RecordInvalid, self
  end
end
