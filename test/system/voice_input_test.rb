require "application_system_test_case"

class VoiceInputSystemTest < ApplicationSystemTestCase
  test "voice becomes an editable draft and typed text restores the send button" do
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      window.SpeechRecognition = class {
        start() { window.voiceRecognition = this; this.onstart(); }
        stop() {
          this.onresult({results: [Object.assign([{transcript: 'Осмотреть ворота'}], {isFinal: true})]});
          this.onend();
        }
        abort() {}
      };
    JS
    visit game_path
    assert_selector "[data-voice-input]:not([disabled])"
    page.execute_script(<<~JS)
      var mic = document.querySelector('[data-voice-input]');
      mic.dispatchEvent(new KeyboardEvent('keydown', {key: ' '}));
      mic.dispatchEvent(new KeyboardEvent('keyup', {key: ' '}));
    JS
    assert_field "Команда игрока", with: "Осмотреть ворота"
    assert_button "Отправить"
    assert_no_selector ".player-echo"
    fill_in "Команда игрока", with: ""
    assert_selector "[data-voice-input]"
    assert_no_button "Отправить"
  end
end
