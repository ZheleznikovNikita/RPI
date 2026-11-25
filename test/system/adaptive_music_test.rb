require "application_system_test_case"

class AdaptiveMusicTest < ApplicationSystemTestCase
  if ENV["RPI_MUSIC_BROWSER"] == "edge"
    Capybara.register_driver :music_edge do |app|
      options = Selenium::WebDriver::Edge::Options.new
      options.add_argument("--headless=new")
      Capybara::Selenium::Driver.new(app, browser: :edge, options: options)
    end
    driven_by :music_edge
  end
  setup do
    @player = create_game_user
    @game = @player.start_game_session!
    visit login_path
    fill_in "Email", with: @player.email
    fill_in "Пароль", with: "Lantern!Orbit7Cedar"
    click_button "Войти"
    assert_current_path profile_path
    page.execute_script("window.RpiPreferences.update({musicEnabled:true,volume:35,typewriter:false})")
    visit game_path
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    find(".scene-card").click
    assert_music("contextState", "running")
  end

  def assert_music(key, expected)
    actual = nil
    Selenium::WebDriver::Wait.new(timeout: 8).until do
      actual = page.evaluate_script("window.RpiMusic.inspect()[#{key.to_json}]")
      expected.is_a?(Numeric) ? (actual - expected).abs < 0.000001 : actual == expected
    end
    expected.is_a?(Numeric) ? assert_in_delta(expected, actual, 0.000001) : assert_equal(expected, actual)
  end

  test "real Web Audio renders all six scores as distinct finite non-clipping audio" do
    result = page.evaluate_async_script(<<~JS)
      var done = arguments[0];
      (async function() {
        var results = [];
        for (var mood of Object.keys(window.RpiMusic.soundtracks)) {
          var buffer = await window.RpiMusic.renderPreview(mood, 4);
          var samples = buffer.getChannelData(0), peak = 0, energy = 0, fingerprint = 0;
          for (var i = 0; i < samples.length; i++) {
            if (!Number.isFinite(samples[i])) throw new Error('Non-finite audio');
            peak = Math.max(peak, Math.abs(samples[i])); energy += samples[i] * samples[i];
            if (i % 101 === 0) fingerprint += samples[i] * (i % 17 + 1);
          }
          results.push({mood:mood,peak:peak,rms:Math.sqrt(energy/samples.length),fingerprint:fingerprint});
        }
        done({results:results});
      })().catch(function(error) { done({error:String(error)}); });
    JS
    assert_nil result["error"], result["error"]
    assert_equal 6, result.fetch("results").size
    result["results"].each do |score|
      assert_operator score["rms"], :>, 0.0001, score["mood"]
      assert_operator score["peak"], :<, 0.98, score["mood"]
    end
    assert_equal 6, result["results"].map { |r| r["fingerprint"].round(4) }.uniq.size
    assert_music("contextsCreated", 1)
  end

  test "story broadcasts change music without restarting same atmosphere and restore it after reload" do
    previous = Rails.configuration.x.narration_provider
    provider = Object.new
    def provider.name = "music-test"
    def provider.model_identifier = "stub"
    def provider.call(payload:)
      { "narration" => "Бой продолжается.", "summary" => "Герой сражается.", "music_mood" => "battle" }
    end
    Rails.configuration.x.narration_provider = provider
    2.times do
      fill_in "Команда игрока", with: "Обратиться к противнику"
      click_button "Отправить"
      assert_text "Рассказчик готовит ответ"
      perform_enqueued_jobs
      assert_music("layers", [ "battle" ])
      assert_music("contextsCreated", 1)
      assert_music("layersCreated", 2)
    end
    refresh
    find(".scene-card").click
    assert_music("layers", [ "battle" ])
    assert_equal "battle", @game.reload.music_mood
  ensure
    Rails.configuration.x.narration_provider = previous
  end

  test "muted plot changes stay silent volume persists and page exit closes resources" do
    page.execute_script("window.RpiPreferences.update({musicEnabled:false})")
    assert_music("contextState", "suspended")
    page.execute_script("window.RpiMusic.setScene({musicMood:'tension',musicGameId:#{@game.id.to_s.to_json}})")
    assert_music("contextState", "suspended")
    page.execute_script("window.RpiPreferences.update({musicEnabled:true,volume:20})")
    find(".scene-card").click
    assert_music("layers", [ "tension" ])
    assert_music("masterVolume", 0.08)
    page.execute_script("window.dispatchEvent(new PageTransitionEvent('pagehide'))")
    assert_music("contextState", "closed")
    assert_music("nodes", 0)
    visit settings_path
    assert_equal 20, page.evaluate_script("window.RpiPreferences.get().volume")
    assert_music("contextsCreated", 0)
  end

  test "preview before the first persisted action stays calm and completion stops music" do
    @game.destroy!
    visit game_path
    find(".scene-card").click
    assert_selector '[data-game][data-music-game-id="guest"]'
    assert_empty find('[data-command-form] input[name="game_session_id"]', visible: :all).value.to_s
    assert_music("contextState", "running")
    assert_music("mood", "calm")
    page.execute_script("window.RpiMusic.setScene({musicMood:'calm',musicGameId:'guest',musicEnded:'true'})")
    assert_music("contextState", "closed")
  end
end
