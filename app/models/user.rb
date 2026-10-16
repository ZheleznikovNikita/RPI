class User < ApplicationRecord
  has_secure_password
  has_many :adventures, dependent: :destroy

  before_validation :normalize_email

  validates :name, presence: true, length: { maximum: 40 }
  validates :email, presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :password_confirmation, presence: true, if: -> { password.present? }
  validate :password_strength, if: -> { password.present? }

  def start_adventure!(title:)
    adventures.create!(title: title)
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
