class StoryTurn < ApplicationRecord
  belongs_to :adventure

  validates :command, presence: true, length: { maximum: 2_000 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :adventure_id }
  validate :response_contract

  def narration
    response.is_a?(Hash) ? response["narration"] : nil
  end

  private

  def response_contract
    unless response.is_a?(Hash) && %w[narration summary].all? { |key| response[key].is_a?(String) && response[key].present? }
      errors.add(:response, "должен содержать строки narration и summary")
      return
    end

    errors.add(:response, "превышает допустимую длину текста") if response["narration"].length > 20_000 || response["summary"].length > 20_000
  end
end
