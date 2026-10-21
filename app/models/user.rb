class User < ApplicationRecord
  has_secure_password
  has_many :game_sessions, dependent: :destroy
  has_one :active_game_session, -> { active }, class_name: "GameSession"

  before_validation :normalize_email

  validates :name, presence: true, length: { maximum: 40 }
  validates :email, presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :password_confirmation, presence: true, if: -> { password.present? }
  validate :password_strength, if: -> { password.present? }

  def start_game_session!(title:)
    with_lock do
      game_sessions.active.each(&:destroy!)
      game_sessions.create!(title: title)
    end
  end

  def delete_game_session!(game_session)
    with_lock { game_sessions.find(game_session.id).destroy! }
  end

  def recent_game_sessions
    game_sessions.completed.order(completed_at: :desc, id: :desc).limit(10)
  end

  private

  def password_strength
    return if password.length < 12 || password.bytesize > 72

    if Zxcvbn.test(password, [ name.to_s, email.to_s, email.to_s.split("@").first.to_s ]).score < 3
      errors.add(:password, :too_weak)
    end
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
