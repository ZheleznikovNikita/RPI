require "application_system_test_case"

class LiveGameSystemTest < ApplicationSystemTestCase
  setup do
    @player = create_game_user
    @game = @player.start_game_session!(opening: StartingScenes::SCENES.last)
    visit login_path
    fill_in "Email", with: @player.email
    fill_in "Пароль", with: "Lantern!Orbit7Cedar"
    click_button "Войти"
    assert_current_path profile_path
    visit game_path
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    @first = current_window
    @second = open_new_window
    within_window(@second) do
      visit game_path
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      page.execute_script(<<~JS)
        window.rpiDocumentMarker = 'same-document';
        document.querySelector('turbo-cable-stream-source').addEventListener('message', function(event) {
          if (event.data.includes('нейросеть не подключена')) {
            window.completedStreamMessage = event.data;
            this.dataset.completedMessage = 'true';
          }
        });
      JS
    end
  end

  test "accepted command arrives in a second tab through a websocket without navigation" do
    within_window(@first) do
      fill_in "Команда игрока", with: "Осмотреть повозку"
      click_button "Отправить"
      assert_text "Рассказчик готовит ответ"
    end
    within_window(@second) { assert_text "Рассказчик готовит ответ" }
    perform_enqueued_jobs
    [ @first, @second ].each do |window|
      within_window(window) do
        assert_selector ".story-entry", count: 1
        assert_text "Ваше действие: Осмотреть повозку"
        assert_text "нейросеть не подключена"
      end
    end
    within_window(@second) do
      assert_equal "same-document", page.evaluate_script("window.rpiDocumentMarker")
      # A delayed pending broadcast may arrive after the completion broadcast.
      # Wait for the actual completed WS message, independently of DOM recovery GETs.
      assert_selector 'turbo-cable-stream-source[data-completed-message="true"]', visible: :all
      assert_includes page.evaluate_script("window.completedStreamMessage"), "нейросеть не подключена"
    end
    assert_equal 1, @game.story_turns.count
  end

  test "reconnecting a tab restores a missed result without another AI request" do
    within_window(@second) do
      page.execute_script("window.savedSource = document.querySelector('turbo-cable-stream-source'); window.savedSource.remove()")
    end
    within_window(@first) do
      fill_in "Команда игрока", with: "Осмотреть дорогу"
      click_button "Отправить"
      assert_text "Рассказчик готовит ответ"
    end
    perform_enqueued_jobs
    within_window(@first) { assert_selector ".story-entry", count: 1 }
    within_window(@second) do
      page.execute_script("document.querySelector('[data-game]').appendChild(window.savedSource)")
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      assert_selector ".story-entry", count: 1
      assert_text "Осмотреть дорогу"
      assert_equal "same-document", page.evaluate_script("window.rpiDocumentMarker")
    end
    assert_equal 1, @game.ai_requests.count
  end

  test "inventory opens through a lazy Turbo Frame" do
    @game.inventory.add_item!(code: "key", name: "Ключ от клетки")
    within_window(@first) do
      find("[data-open-inventory]").click
      assert_selector "turbo-frame#inventory_contents[complete]"
      assert_text "Ключ от клетки"
      find("[data-close-inventory]").click
      assert_no_selector "dialog[open]"
    end
  end

  test "a delayed older stream cannot replace a newer pending state" do
    within_window(@first) do
      page.execute_script(<<~JS)
        window.rpiDelayOld = function(event) {
          if (event.target.getAttribute('target') !== 'live-state') return;
          if (!event.target.querySelector('template').content.querySelector('[data-delayed-test]')) return;
          var render = event.detail.render;
          event.detail.render = async function(stream) {
            document.body.dataset.oldRenderWaiting = 'true';
            await new Promise(function(resolve) { window.releaseOldRender = resolve; });
            await render(stream);
            document.body.dataset.oldRenderFinished = 'true';
          };
        };
        document.addEventListener('turbo:before-stream-render', window.rpiDelayOld);
        var snapshot = document.querySelector('[data-live-snapshot]').cloneNode(true);
        window.testRevision = Math.max(Number(snapshot.dataset.revision), Date.now() / 1000) + 10;
        snapshot.dataset.revision = window.testRevision;
        snapshot.dataset.delayedTest = 'true';
        window.Turbo.renderStreamMessage('<turbo-stream action="update" target="live-state"><template>' + snapshot.outerHTML + '</template></turbo-stream>');
      JS
      assert_selector 'body[data-old-render-waiting="true"]'
      page.execute_script(<<~JS)
        var snapshot = document.querySelector('[data-live-snapshot]').cloneNode(true);
        snapshot.dataset.revision = window.testRevision + 1;
        snapshot.dataset.pending = 'true';
        window.Turbo.renderStreamMessage('<turbo-stream action="update" target="live-state"><template>' + snapshot.outerHTML + '</template></turbo-stream>');
      JS
      assert_selector '[data-live-snapshot][data-pending="true"]', visible: :all
      page.execute_script("window.releaseOldRender()")
      assert_selector 'body[data-old-render-finished="true"]'
      assert_selector '[data-live-snapshot][data-pending="true"]', visible: :all
      assert_text "Рассказчик готовит ответ"
    end
  end

  test "real in-process async worker completes a command without manual job execution" do
    previous = NarrationJob.queue_adapter
    previous_test_adapter = NarrationJob._test_adapter
    adapter = ActiveJob::QueueAdapters::AsyncAdapter.new(min_threads: 1, max_threads: 1)
    # TestHelper can override queue_adapter after earlier tests load this job.
    NarrationJob.disable_test_adapter
    NarrationJob.queue_adapter = adapter
    assert_same adapter, NarrationJob.queue_adapter
    within_window(@first) do
      fill_in "Команда игрока", with: "Проверить колёса"
      click_button "Отправить"
      assert_selector ".story-entry", count: 1
      assert_text "нейросеть не подключена"
    end
    within_window(@second) do
      assert_selector ".story-entry", count: 1
      assert_text "Проверить колёса"
    end
    assert_equal 1, @game.story_turns.count
  ensure
    adapter&.shutdown(wait: true)
    NarrationJob.queue_adapter = previous
    NarrationJob.enable_test_adapter(previous_test_adapter)
  end
end
