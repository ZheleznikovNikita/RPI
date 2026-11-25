require "test_helper"

class MusicMoodsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper
  Provider = Struct.new(:mood, :payloads) do
    def name = "music-test"
    def model_identifier = "stub"
    def call(payload:)
      payloads << payload.deep_dup
      { "narration" => "История продолжается.", "summary" => "Герой продолжает путь.", "music_mood" => mood }
    end
  end

  setup do
    @previous = Rails.configuration.x.narration_provider
    @provider = Provider.new("battle", [])
    Rails.configuration.x.narration_provider = @provider
    @player = create_game_user
    @game = @player.start_game_session!
    post login_path, params: { email: @player.email, password: "Lantern!Orbit7Cedar" }
    clear_enqueued_jobs
  end
  teardown { Rails.configuration.x.narration_provider = @previous }

  def turn
    post game_path, params: { command: "Продолжить", game_session_id: @game.id }, as: :json, headers: { "X-RPI-Live" => "1" }
    assert_response :accepted
    perform_enqueued_jobs
  end

  test "new games start calm and accepted responses persist all moods and broadcast without another AI call" do
    assert_equal "calm", @game.current_music_mood
    Storytelling::MusicMood::VALUES.each do |mood|
      @provider.mood = mood
      turn
      assert_equal mood, @game.reload.current_music_mood
      get game_state_path
      assert_select "[data-music-scene][data-music-mood=?]", mood
      assert_includes JSON.parse(broadcasts("private_game_user_#{@player.id}").last), "data-music-mood=\"#{mood}\""
      get game_path
      assert_select "[data-game][data-music-mood=?]", mood
    end
    assert_equal 6, @provider.payloads.size
    assert_equal "calm", @provider.payloads.first["music_mood"]
    assert_equal "sad", @provider.payloads.last["music_mood"]
  end

  test "unknown missing and repeated moods preserve valid state and its original time" do
    turn
    first_time = @game.reload.music_mood_changed_at
    [ "battle", "invalid", nil, { "mood" => "battle" } ].each do |mood|
      @provider.mood = mood
      turn
      assert_equal "battle", @game.reload.current_music_mood
      assert_equal first_time, @game.music_mood_changed_at
    end
    NarrationJob.perform_now(@game.ai_requests.reorder(id: :desc).first.id)
    assert_equal first_time, @game.reload.music_mood_changed_at
  end

  test "victory expires across reload without replaying on repeated updates and a later victory can start again" do
    travel_to Time.current.change(usec: 0) do
      @provider.mood = "victory"
      turn
      began = @game.reload.music_mood_changed_at
      travel 5.seconds
      turn
      assert_equal began, @game.reload.music_mood_changed_at
      assert_equal "victory", @game.current_music_mood
      travel 12.seconds
      get game_path
      assert_select '[data-game][data-music-mood="calm"]'
      turn
      assert_equal "calm", @provider.payloads.last["music_mood"]
      assert_operator @game.reload.music_mood_changed_at, :>, began
    end
  end

  test "game restart resets mood and user state cannot leak through snapshots" do
    turn
    foreign = create_game_session
    foreign.update!(music_mood: "sad", music_mood_changed_at: Time.current)
    get game_state_path, params: { user_id: foreign.user_id, game_session_id: foreign.id }
    assert_select '[data-music-scene][data-music-mood="battle"]'
    post start_game_path, params: { replace_game_session_id: @game.id }
    assert_equal "calm", @player.reload.active_game_session.current_music_mood
    assert_equal "sad", foreign.reload.current_music_mood
  end

  test "mood rolls back with a failed acceptance and saved responses recover mood once" do
    action = @game.submit_action!(command: "Идти")
    request = successful_request(action, response: { "narration" => "Тайна.", "summary" => "Руины.", "music_mood" => "mystery" })
    assert_raises(ActiveRecord::RecordInvalid) { action.complete!(request: request, summary: " ") }
    assert_equal "calm", @game.reload.current_music_mood
    action.update_columns(updated_at: 4.minutes.ago)
    get game_state_path
    assert_equal "mystery", @game.reload.current_music_mood
    changed_at = @game.music_mood_changed_at
    get game_state_path
    assert_equal changed_at, @game.reload.music_mood_changed_at
    assert_empty @provider.payloads
  end
end
