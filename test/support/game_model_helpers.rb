module GameModelHelpers
  def create_game_user(email: "#{SecureRandom.hex(8)}@example.test")
    User.create!(name: "Игрок", email: email, password: "Lantern!Orbit7Cedar", password_confirmation: "Lantern!Orbit7Cedar")
  end

  def create_game_session
    create_game_user.start_game_session!(title: "Тропа")
  end

  def successful_request(action, purpose: "narration", response: { "narration" => "Вы нашли тропу" })
    request = action.request_ai!(purpose: purpose, provider: "test", model_identifier: "test-model", payload: { "prompt" => action.command })
    request.start!
    request.succeed!(response: response)
  end

  def complete_action(game_session, command: "Осмотреться", summary: "Герой вышел на тропу")
    action = game_session.submit_action!(command: command)
    action.complete!(request: successful_request(action), summary: summary)
    action
  end
end
