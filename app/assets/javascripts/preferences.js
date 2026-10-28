(function () {
  "use strict";
  var key = "rpi-player-preferences";
  var settings = { volume: 35, musicEnabled: true, typewriter: true };

  function restore() {
    settings = { volume: 35, musicEnabled: true, typewriter: true };
    try {
      var saved = JSON.parse(localStorage.getItem(key) || "{}");
      if (!saved || typeof saved !== "object") return;
      if (Number.isFinite(saved.volume)) settings.volume = Math.max(0, Math.min(100, saved.volume));
      if (typeof saved.musicEnabled === "boolean") settings.musicEnabled = saved.musicEnabled;
      if (typeof saved.typewriter === "boolean") settings.typewriter = saved.typewriter;
    } catch (_error) { /* The controls still work when storage is unavailable. */ }
  }

  function refresh() {
    document.querySelectorAll('[data-setting="volume"]').forEach(function (input) { input.value = settings.volume; });
    document.querySelectorAll("[data-volume-output]").forEach(function (output) { output.textContent = Math.round(settings.volume) + "%"; });
    document.querySelectorAll('[data-setting="typewriter"]').forEach(function (input) { input.checked = settings.typewriter; });
    document.dispatchEvent(new CustomEvent("rpi:preferences", { detail: Object.assign({}, settings) }));
  }

  function update(changes) {
    Object.assign(settings, changes);
    try { localStorage.setItem(key, JSON.stringify(settings)); }
    catch (_error) {
      document.querySelectorAll("[data-preferences-status]").forEach(function (node) {
        node.textContent = "Настройки действуют сейчас. Браузер запретил их сохранение после закрытия страницы.";
      });
    }
    refresh();
  }

  restore();
  window.RpiPreferences = { get: function () { return Object.assign({}, settings); }, update: update };
  document.addEventListener("DOMContentLoaded", function () {
    refresh();
    document.querySelectorAll("[data-setting]").forEach(function (input) {
      input.addEventListener("input", function () {
        if (input.dataset.setting === "volume") update({ volume: Number(input.value) });
        if (input.dataset.setting === "typewriter") update({ typewriter: input.checked });
      });
    });
  });
  window.addEventListener("storage", function (event) { if (event.key === key || event.key === null) { restore(); refresh(); } });
  window.addEventListener("pageshow", function (event) { if (event.persisted) { restore(); refresh(); } });
})();
