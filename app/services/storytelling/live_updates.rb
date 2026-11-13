module Storytelling
  class LiveUpdates
    def self.broadcast(user)
      game = user.game_sessions.active.first
      Turbo::StreamsChannel.broadcast_update_to("private_game_user_#{user.id}", target: "live-state",
        partial: "game/live_state", locals: { game: game })
    rescue StandardError => error
      Rails.logger.warn("Game broadcast failed (#{error.class.name})")
    end

    def self.expire_stale!(game)
      return unless game

      game.with_lock do
        game.ai_requests.where(status: %w[pending running]).where("ai_requests.updated_at < ?", 3.minutes.ago).each do |request|
          request.fail!(message: Narrator::ERROR_MESSAGE)
          request.player_action.cancel! if request.player_action.pending?
          game.touch
        end
        # Recover a process exit between storing the API response and accepting its turn.
        game.player_actions.pending.where("player_actions.updated_at < ?", 3.minutes.ago).each do |action|
          request = action.ai_requests.succeeded.reorder(id: :desc).first
          next unless request&.purpose_narration? && request.response_payload["summary"].is_a?(String)

          action.complete!(request: request, summary: request.response_payload.fetch("summary"))
          game.touch
        end
      end
    end
  end
end
