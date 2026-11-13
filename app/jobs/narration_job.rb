class NarrationJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = AiRequest.find_by(id: request_id)
    return unless request

    Storytelling::Narrator.new.perform_request(request)
  end
end
