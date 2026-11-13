class GameChannel < Turbo::StreamsChannel
  def subscribed
    if verified_stream_name_from_params == "game_ui"
      # Never expose a signed token for the actual private stream to the browser.
      stream_from "private_game_user_#{current_user.id}"
    else
      reject
    end
  end
end
