(function () {
  "use strict";
  document.addEventListener("DOMContentLoaded", function () {
    var form = document.querySelector("[data-command-form]");
    if (!form) return;
    var input = form.querySelector('[name="command"]');
    var send = form.querySelector("[data-send-command]");
    var mic = form.querySelector("[data-voice-input]");
    var status = form.querySelector("[data-voice-status]");
    var Engine = window.SpeechRecognition || window.webkitSpeechRecognition;
    var session = null, held = false, pointer = null;

    function refresh() {
      var empty = input.value.length === 0;
      mic.hidden = !empty;
      send.hidden = empty;
      mic.disabled = !Engine || input.readOnly || send.disabled;
      if (!session) status.textContent = empty && !Engine ? "Голосовой ввод недоступен в этом браузере. Введите команду текстом." : "";
      if (session && (input.readOnly || send.disabled || !empty)) cancel();
    }
    function cancel() {
      if (!session) return;
      var old = session;
      session = null; held = false; pointer = null;
      clearTimeout(old.timeout);
      old.engine.abort();
      mic.setAttribute("aria-pressed", "false");
      mic.classList.remove("is-recording");
      refresh();
    }
    function finish(current) {
      if (session !== current) return;
      session = null; held = false; pointer = null;
      clearTimeout(current.timeout);
      mic.setAttribute("aria-pressed", "false");
      mic.classList.remove("is-recording");
      if (!current.error && !input.value && !input.readOnly && !send.disabled) {
        var text = current.text.trim();
        input.value = text.slice(0, input.maxLength > 0 ? input.maxLength : 2000);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
      refresh();
      status.textContent = current.error || (input.value ? "Речь распознана. Проверьте текст и нажмите «Отправить»." : "Речь не распознана. Удерживайте микрофон и попробуйте ещё раз.");
    }
    function start() {
      if (session || !Engine || input.value || input.readOnly || send.disabled) return;
      held = true;
      var current = { engine: new Engine(), text: "", started: false };
      session = current;
      var engine = current.engine;
      engine.lang = "ru-RU";
      engine.continuous = true;
      engine.interimResults = false;
      engine.onstart = function () {
        if (session !== current) return;
        current.started = true;
        if (!held) engine.stop();
        else status.textContent = "Идёт запись. Отпустите кнопку, чтобы распознать речь.";
      };
      engine.onresult = function (event) {
        if (session !== current) return;
        current.text = Array.from(event.results).filter(function (result) { return result.isFinal; }).map(function (result) { return result[0].transcript; }).join(" ");
      };
      engine.onerror = function (event) {
        current.error = ({ "not-allowed": "Разрешите доступ к микрофону в настройках браузера.", "audio-capture": "Микрофон недоступен. Проверьте подключение.", "network": "Нет связи с сервисом распознавания. Попробуйте ещё раз.", "language-not-supported": "Браузер не поддерживает распознавание русской речи." })[event.error] || "Не удалось распознать речь. Попробуйте ещё раз или введите текст.";
        finish(current);
      };
      engine.onend = function () { finish(current); };
      mic.setAttribute("aria-pressed", "true");
      mic.classList.add("is-recording");
      status.textContent = "Подключаем микрофон…";
      current.timeout = setTimeout(cancel, 60000);
      try { engine.start(); } catch (_) { current.error = "Не удалось включить микрофон. Проверьте разрешения браузера."; finish(current); }
    }
    function release() {
      if (!session || !held) return;
      held = false;
      status.textContent = "Распознаём речь…";
      // A permission prompt can delay onstart until after pointerup.
      if (session.started) session.engine.stop();
    }
    mic.addEventListener("pointerdown", function (event) {
      if (event.button !== 0 || session) return;
      event.preventDefault();
      start();
      if (session) { pointer = event.pointerId; mic.setPointerCapture(pointer); }
    });
    mic.addEventListener("pointerup", function (event) { if (event.pointerId === pointer) release(); });
    mic.addEventListener("pointercancel", cancel);
    mic.addEventListener("lostpointercapture", release);
    mic.addEventListener("contextmenu", function (event) { event.preventDefault(); });
    mic.addEventListener("keydown", function (event) {
      if (event.key === " " || event.key === "Enter") { event.preventDefault(); if (!event.repeat) start(); }
      if (event.key === "Escape") cancel();
    });
    mic.addEventListener("keyup", function (event) { if (event.key === " " || event.key === "Enter") { event.preventDefault(); release(); } });
    mic.addEventListener("blur", cancel);
    input.addEventListener("input", refresh);
    // Existing guest/live controllers own busy state and restore drafts.
    new MutationObserver(refresh).observe(input, { attributes: true, attributeFilter: ["readonly"] });
    new MutationObserver(refresh).observe(send, { attributes: true, attributeFilter: ["disabled"] });
    document.addEventListener("visibilitychange", function () { if (document.hidden) cancel(); });
    window.addEventListener("blur", cancel);
    window.addEventListener("pagehide", cancel);
    window.addEventListener("pageshow", refresh);
    refresh();
  });
})();
