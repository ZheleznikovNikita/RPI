(function () {
  "use strict";
  document.addEventListener("DOMContentLoaded", function () {
    var form = document.querySelector("[data-command-form]");
    if (!form) return;
    var input = form.querySelector('[name="command"]');
    var button = form.querySelector("[data-send-command]");
    var history = document.querySelector("[data-story-history]");
    var skip = document.querySelector("[data-skip-typing]");
    var announcement = document.querySelector("[data-story-announcement]");
    var feedback = document.getElementById("command-feedback");
    var busy = false, finishTyping = null, timeout;
    var feedbackDefault = feedback.dataset.defaultFeedback || feedback.textContent;
    var draftKey = form.dataset.draftKey;
    var hasSubmitted = history.querySelector("[data-story-text]") !== null;

    function saveDraft() {
      try {
        if (input.value) sessionStorage.setItem(draftKey, input.value);
        else sessionStorage.removeItem(draftKey);
      } catch (_error) { /* Typing and submission also work without browser storage. */ }
    }

    function restoreDraft() {
      try { input.value = (sessionStorage.getItem(draftKey) || "").slice(0, 2000); }
      catch (_error) { /* Leave browser-restored form values intact if storage is blocked. */ }
    }

    function responseError(message) {
      var error = new Error(message);
      error.feedback = message;
      return error;
    }

    restoreDraft();

    function setBusy(value) {
      busy = value;
      input.readOnly = value;
      button.disabled = value;
      button.textContent = value ? "Отправка…" : "Отправить";
      form.setAttribute("aria-busy", String(value));
    }

    function typeText(story, text) {
      return new Promise(function (resolve) {
        if (finishTyping) finishTyping();
        var characters = Array.from(text), position = 0;
        var animated = window.RpiPreferences.get().typewriter && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        function complete() {
          window.clearTimeout(timeout);
          story.textContent = text;
          story.classList.remove("is-typing");
          skip.hidden = true;
          finishTyping = null;
          announcement.textContent = text;
          history.scrollTop = history.scrollHeight;
          resolve();
        }
        finishTyping = complete;
        if (!animated) { complete(); return; }
        story.textContent = "";
        story.classList.add("is-typing");
        skip.hidden = false;
        function tick() {
          position += 1;
          story.textContent = characters.slice(0, position).join("");
          history.scrollTop = history.scrollHeight;
          if (position >= characters.length) complete();
          else timeout = window.setTimeout(tick, 24);
        }
        tick();
      });
    }

    skip.addEventListener("click", function () { if (finishTyping) finishTyping(); });
    document.addEventListener("rpi:preferences", function () { if (!window.RpiPreferences.get().typewriter && finishTyping) finishTyping(); });
    input.addEventListener("input", function () { input.setCustomValidity(""); saveDraft(); });

    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      if (busy) return;
      var command = input.value.trim();
      if (!command || command.length > 2000) {
        input.setCustomValidity("Введите действие длиной от 1 до 2000 символов.");
        input.reportValidity();
        return;
      }
      setBusy(true);
      feedback.hidden = false;
      feedback.textContent = "Ожидаем ответ…";
      feedback.classList.remove("is-error");
      var controller = new AbortController();
      var requestTimeout = window.setTimeout(function () { controller.abort(); }, 20000);
      var receivedResponse = false;
      try {
        var response = await fetch(form.action, {
          method: "POST", body: new FormData(form), credentials: "same-origin", signal: controller.signal,
          headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
        });
        receivedResponse = true;
        var result;
        try { result = await response.json(); }
        catch (_error) {
          if (response.status === 422) throw responseError("Сессия страницы устарела. Обновите страницу и отправьте команду снова.");
          throw responseError(response.ok ? "Сервер вернул неожиданный ответ. Обновите страницу и попробуйте снова." : "Ошибка сервера (HTTP " + response.status + "). Команда сохранена — повторите отправку позже.");
        }
        if (!result || typeof result.text !== "string") throw responseError("Сервер вернул неожиданный ответ. Обновите страницу и попробуйте снова.");
        if (!response.ok) {
          feedback.classList.add("is-error");
          feedback.textContent = result.text;
          return;
        }
        input.value = "";
        hasSubmitted = true;
        saveDraft();
        if (result.game_session_id) {
          form.querySelector('[name="game_session_id"]').value = result.game_session_id;
          var finishForm = document.querySelector("[data-finish-game]");
          if (finishForm) {
            finishForm.hidden = false;
            finishForm.querySelector('[name="game_session_id"]').value = result.game_session_id;
          }
          draftKey = draftKey.replace(/-[^-]+$/, "-" + result.game_session_id);
          form.dataset.draftKey = draftKey;
          saveDraft();
        }
        var entry = document.createElement("article");
        entry.className = "story-entry";
        var echo = document.createElement("p");
        echo.className = "player-echo";
        echo.dataset.playerEcho = "";
        echo.textContent = "Ваше действие: " + command;
        var story = document.createElement("p");
        story.dataset.storyText = "";
        entry.appendChild(echo);
        entry.appendChild(story);
        history.appendChild(entry);
        button.textContent = "Печатается…";
        feedback.textContent = "Ответ получен.";
        await typeText(story, result.text);
        feedback.textContent = feedbackDefault;
        feedback.hidden = true;
      } catch (error) {
        feedback.classList.add("is-error");
        feedback.hidden = false;
        feedback.textContent = error.feedback || (receivedResponse ? "Ответ получен, но не удалось показать продолжение. Обновите страницу." : "Не удалось связаться с сервером. Текст сохранён в поле — попробуйте отправить ещё раз.");
      } finally {
        window.clearTimeout(requestTimeout);
        setBusy(false);
        input.focus({ preventScroll: true });
      }
    });

    var animatedStory = history.querySelector('[data-animate="true"]');
    if (animatedStory) {
      setBusy(true);
      typeText(animatedStory, animatedStory.textContent).finally(function () { setBusy(false); });
    } else history.scrollTop = history.scrollHeight;
    if (hasSubmitted && !feedback.classList.contains("is-error")) feedback.hidden = true;
    window.addEventListener("pagehide", function () { saveDraft(); if (finishTyping) finishTyping(); });
    window.addEventListener("pageshow", function (event) { if (event.persisted) restoreDraft(); });
  });
})();
