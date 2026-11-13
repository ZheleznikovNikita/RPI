(function () {
  "use strict";
  document.addEventListener("DOMContentLoaded", function () {
    var form = document.querySelector('[data-command-form][data-live="true"]');
    if (!form) return;
    var input = form.querySelector('[name="command"]');
    var button = form.querySelector('[data-send-command]');
    var feedback = document.getElementById("command-feedback");
    var source = document.querySelector("turbo-cable-stream-source");
    var connection = document.querySelector("[data-live-connection]");
    var seen = new Set(Array.from(document.querySelectorAll(".story-entry[id]")).map(function (entry) { return entry.id; }));
    var gameId = form.querySelector('[name="game_session_id"]').value;
    var sending = false, pending = false, ended = false, typing = false, finishTyping = null;
    var revision = 0, syncing = false, timer, stopped = false;
    var draftKey = form.dataset.draftKey;
    var skip = document.querySelector('[data-skip-typing]');
    function save() {
      try { if (input.value) sessionStorage.setItem(draftKey, input.value); else sessionStorage.removeItem(draftKey); } catch (_) {}
    }
    function restore() {
      try { input.value = (sessionStorage.getItem(draftKey) || "").slice(0, 2000); } catch (_) {}
    }
    function controls() {
      input.readOnly = sending || pending || typing || ended;
      button.disabled = input.readOnly;
      button.textContent = pending ? "Ожидаем ответ…" : typing ? "Печатается…" : "Отправить";
      form.setAttribute("aria-busy", String(sending || pending || typing));
    }
    function status(text, error) {
      feedback.hidden = !text;
      feedback.textContent = text;
      feedback.classList.toggle("is-error", !!error);
    }
    function animate(story) {
      var text = story.textContent, chars = Array.from(text), position = 0, timeout;
      if (!window.RpiPreferences.get().typewriter || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      typing = true;
      story.textContent = "";
      skip.hidden = false;
      finishTyping = function () {
        clearTimeout(timeout); story.textContent = text; typing = false; skip.hidden = true; finishTyping = null; controls();
      };
      function tick() {
        story.textContent = chars.slice(0, ++position).join("");
        var history = document.querySelector('[data-story-history]');
        history.scrollTop = history.scrollHeight;
        if (position < chars.length) timeout = setTimeout(tick, 24); else finishTyping();
      }
      tick();
    }
    function update(snapshot) {
      var nextId = snapshot.dataset.gameId;
      ended = !nextId && !!gameId;
      pending = snapshot.dataset.pending === "true";
      if (snapshot.dataset.failed === "true" && !input.value && !sending) { input.value = snapshot.dataset.retryCommand; save(); }
      if (nextId && nextId !== gameId) {
        gameId = nextId;
        form.querySelector('[name="game_session_id"]').value = gameId;
        save();
        draftKey = draftKey.replace(/-[^-]+$/, "-" + gameId);
        form.dataset.draftKey = draftKey;
        restore();
        var finishForm = document.querySelector('[data-finish-game]');
        if (finishForm) { finishForm.hidden = false; finishForm.querySelector('[name="game_session_id"]').value = gameId; }
        var inventory = document.querySelector('turbo-frame#inventory_contents[src]');
        if (inventory && inventory.complete && typeof inventory.reload === 'function') inventory.reload();
      }
      if (nextId) {
        document.querySelector('.story-label').textContent = snapshot.dataset.title;
        document.querySelectorAll('.stat-row').forEach(function (row, index) {
          var value = index === 0 ? snapshot.dataset.health : snapshot.dataset.stamina;
          row.querySelector('strong').textContent = value;
          row.querySelector('.bar i').style.width = value + '%';
        });
      }
      var fresh = Array.from(snapshot.querySelectorAll('.story-entry[id]')).filter(function (entry) { return !seen.has(entry.id); });
      snapshot.querySelectorAll('.story-entry[id]').forEach(function (entry) { seen.add(entry.id); });
      if (fresh.length) {
        var story = fresh[fresh.length - 1].querySelector('[data-story-text]');
        document.querySelector('[data-story-announcement]').textContent = story.textContent;
        animate(story);
      }
      status(ended ? "Прохождение завершено или заменено. Перейдите в главное меню." : pending ? "Рассказчик готовит ответ…" : snapshot.dataset.failed === "true" ? "Не удалось получить продолжение истории. Попробуйте отправить действие ещё раз." : snapshot.querySelector('.story-entry') ? "" : feedback.dataset.defaultFeedback, snapshot.dataset.failed === "true");
      controls();
      var history = document.querySelector('[data-story-history]');
      if (history) history.scrollTop = history.scrollHeight;
    }
    // Both WebSocket broadcasts and recovery GETs use the same Turbo Stream renderer.
    document.addEventListener("turbo:before-stream-render", function (event) {
      if (event.target.getAttribute("target") !== "live-state") return;
      var template = event.target.querySelector('template');
      var snapshot = template && template.content.querySelector('[data-live-snapshot]');
      if (!snapshot) return;
      var nextRevision = Number(snapshot.dataset.revision);
      if (nextRevision <= revision || (!snapshot.dataset.gameId && !gameId)) { event.preventDefault(); return; }
      revision = nextRevision;
      var render = event.detail.render;
      event.detail.render = async function (stream) {
        // Turbo waits for a repaint after before-stream-render. A newer snapshot
        // may have arrived during that wait, so check again before changing DOM.
        if (nextRevision !== revision) return;
        if (finishTyping) finishTyping();
        await render(stream);
        var current = document.querySelector('#live-state [data-live-snapshot]');
        if (current) update(current);
      };
    });
    async function sync() {
      if (syncing || stopped) return;
      syncing = true;
      try {
        var response = await fetch(form.dataset.stateUrl, { credentials: "same-origin", cache: "no-store", headers: { Accept: "text/vnd.turbo-stream.html" }, signal: AbortSignal.timeout(10000) });
        if (response.status === 401) { ended = true; status("Войдите в аккаунт снова.", true); controls(); return; }
        if (response.ok) window.Turbo.renderStreamMessage(await response.text());
      } catch (_) { connection.textContent = "Нет связи с сервером. Переподключение…"; }
      finally { syncing = false; }
    }
    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      if (sending || pending || typing || ended) return;
      if (!input.value.trim() || input.value.length > 2000) { input.reportValidity(); return; }
      sending = true; controls(); status("Отправляем действие…");
      try {
        var csrf = document.querySelector('meta[name="csrf-token"]');
        var response = await fetch(form.action, { method: "POST", credentials: "same-origin", body: new FormData(form), signal: AbortSignal.timeout(15000), headers: { Accept: "application/json", "X-RPI-Live": "1", "X-CSRF-Token": csrf ? csrf.content : "" } });
        var result = await response.json();
        if (!response.ok) { status(result.text || "Не удалось отправить действие.", true); return; }
        input.value = ""; save();
        var current = document.querySelector('[data-live-snapshot]');
        pending = !current || Number(current.dataset.requestId) < result.request_id || current.dataset.pending === "true";
        if (pending) status(result.text);
      } catch (_) {
        status("Связь прервалась. Проверяем, было ли принято действие; текст сохранён.", true);
      } finally {
        sending = false;
        var snapshot = document.querySelector('[data-live-snapshot]');
        if (snapshot && (!result || !result.request_id || Number(snapshot.dataset.requestId) >= result.request_id)) update(snapshot);
        controls(); await sync();
      }
    });
    skip.addEventListener('click', function () { if (finishTyping) finishTyping(); });
    document.addEventListener('rpi:preferences', function () { if (!window.RpiPreferences.get().typewriter && finishTyping) finishTyping(); });
    input.addEventListener('input', save);
    var observer = new MutationObserver(function () {
      connection.textContent = source.hasAttribute('connected') ? "Живые обновления подключены." : "Переподключение живых обновлений…";
      if (source.hasAttribute('connected')) sync();
    });
    observer.observe(source, { attributes: true, attributeFilter: [ 'connected' ] });
    function start() { stopped = false; clearInterval(timer); timer = setInterval(sync, 15000); sync(); }
    restore(); start();
    window.addEventListener('pagehide', function () { stopped = true; clearInterval(timer); save(); if (finishTyping) finishTyping(); });
    window.addEventListener('pageshow', function (event) { if (event.persisted) { restore(); start(); } });
  });
})();
