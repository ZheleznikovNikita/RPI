class Adventure < ApplicationRecord
  belongs_to :user
  has_many :story_turns, -> { order(:position) }, dependent: :destroy

  enum :status, { active: "active", completed: "completed" }, validate: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :summary, length: { maximum: 20_000 }
  validates :health, :stamina, numericality: { only_integer: true, in: 0..100 }

  # Persist the turn and its memory together so a rejected response cannot lose the plot.
  def record_turn!(command:, response:)
    with_lock do
      unless active?
        errors.add(:base, "Приключение завершено")
        raise ActiveRecord::RecordInvalid, self
      end

      turn = story_turns.create!(command: command, response: response, position: (story_turns.maximum(:position) || 0) + 1)
      update!(summary: response.fetch("summary"))
      turn
    end
  end

  def finish!
    update!(status: :completed)
  end
end
