module Storytelling
  class Narrator
    ERROR_MESSAGE = "Не удалось получить продолжение истории. Попробуйте отправить действие ещё раз.".freeze
    Result = Data.define(:status, :text)

    def initialize(provider: Rails.configuration.x.narration_provider || OfflineProvider.new)
      @provider = provider
    end

    def call(command:, game_session: nil)
      return Result.new(status: "completed", text: OfflineProvider::MESSAGE) unless game_session

      action, request = prepare_request(game_session, command)
      begin
        request.start!
        # The adapter performs its network call here, outside database locks.
        response = @provider.call(payload: request.request_payload)
        validate_response!(response)
        request.succeed!(response: response)
        turn = action.complete!(request: request, summary: response.fetch("summary"))
        Result.new(status: "completed", text: turn.narration)
      rescue StandardError => error
        Rails.logger.error("Narration failed (#{error.class.name})")
        reject_attempt(action, request, ERROR_MESSAGE)
        Result.new(status: "error", text: ERROR_MESSAGE)
      end
    end

    private

    def prepare_request(game, command)
      game.with_lock do
        action = game.submit_action!(command: command)
        history = game.player_actions.completed.reorder(position: :desc).limit(10).to_a.reverse.map do |previous|
          { "command" => previous.command, "narration" => previous.story_turn&.narration }
        end
        request = action.request_ai!(purpose: "narration", provider: @provider.name, model_identifier: @provider.model_identifier,
          payload: { "command" => command, "summary" => game.summary, "history" => history })
        [ action, request ]
      end
    end

    def validate_response!(response)
      unless response.is_a?(Hash) && %w[narration summary].all? { |key| response[key].is_a?(String) && response[key].present? && response[key].length <= 20_000 }
        raise ArgumentError, "Invalid narrator response"
      end
    end

    def reject_attempt(action, request, message)
      request.reload.fail!(message: message) if request.reload.pending? || request.running?
      action.reload.cancel! if action.reload.pending?
    end
  end
end
