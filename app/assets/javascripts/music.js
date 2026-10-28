(function () {
  "use strict";
  // Original ambient score, synthesized locally. No recordings or samples.
  // The composition and its generated audio are dedicated to CC0-1.0.
  var context, master, timer, nextCycle = 0;
  var AudioEngine = window.AudioContext || window.webkitAudioContext;
  var chords = [[57, 60, 64, 71], [53, 57, 60, 67], [48, 55, 59, 64], [55, 59, 62, 69]];
  var melody = [[76, 71, 72, 64], [72, 69, 67, 69], [67, 71, 76, 74], [74, 71, 69, 67]];

  function note(pitch, start, duration, strength, bell) {
    var oscillator = context.createOscillator();
    var envelope = context.createGain();
    oscillator.type = "sine";
    oscillator.frequency.value = 440 * Math.pow(2, (pitch - 69) / 12);
    envelope.gain.setValueAtTime(0, start);
    envelope.gain.linearRampToValueAtTime(strength, start + (bell ? 0.03 : 1.4));
    envelope.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    oscillator.connect(envelope);
    envelope.connect(master);
    oscillator.start(start);
    oscillator.stop(start + duration + 0.1);
    oscillator.onended = function () { oscillator.disconnect(); envelope.disconnect(); };
  }

  function schedule() {
    if (!context || context.state !== "running" || nextCycle > context.currentTime + 2) return;
    var start = Math.max(nextCycle, context.currentTime + 0.08);
    chords.forEach(function (chord, index) {
      chord.forEach(function (pitch) { note(pitch, start + index * 8, 10, 0.16, false); });
      note(chord[0] - 12, start + index * 8, 9, 0.15, false);
      melody[index].forEach(function (pitch, beat) { note(pitch, start + index * 8 + beat * 2 + 0.5, 3, 0.13, true); });
    });
    nextCycle = start + 32;
  }

  function refresh() {
    var enabled = window.RpiPreferences.get().musicEnabled;
    document.querySelectorAll("[data-music-toggle]").forEach(function (button) {
      button.setAttribute("aria-pressed", String(enabled));
      button.textContent = enabled ? "Выключить музыку" : "Включить музыку";
      if (!AudioEngine) button.disabled = true;
    });
  }

  function status(text) {
    document.querySelectorAll("[data-music-status]").forEach(function (node) { node.textContent = text; });
  }

  async function start() {
    if (!AudioEngine) { status("Этот браузер не поддерживает воспроизведение музыки."); return; }
    var preferences = window.RpiPreferences.get();
    if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden) return;
    try {
      if (!context) {
        context = new AudioEngine();
        master = context.createGain();
        master.gain.value = 0;
        master.connect(context.destination);
        nextCycle = 0;
        context.onstatechange = refresh;
      }
      await context.resume();
      if (!context) return;
      preferences = window.RpiPreferences.get();
      if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden) { await context.suspend(); return; }
      master.gain.setTargetAtTime(preferences.volume / 100 * 0.28, context.currentTime, 0.08);
      schedule();
      if (!timer) timer = window.setInterval(schedule, 500);
      status("Фоновая музыка играет. Громкость меняется в настройках.");
    } catch (_error) { status("Музыку пока не удалось запустить. Нажмите кнопку ещё раз."); }
    refresh();
  }

  async function sync() {
    var preferences = window.RpiPreferences.get();
    if (context) {
      master.gain.setTargetAtTime(preferences.volume / 100 * 0.28, context.currentTime, 0.08);
      if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden) {
        await context.suspend().catch(function () {});
        status(preferences.volume === 0 ? "Громкость установлена на 0%." : "Музыка выключена.");
      } else { await start(); }
    } else if (document.querySelector("[data-game]")) await start();
    refresh();
  }

  document.addEventListener("DOMContentLoaded", function () {
    refresh();
    if (!AudioEngine) status("Этот браузер не поддерживает воспроизведение музыки.");
    document.querySelectorAll("[data-music-toggle]").forEach(function (button) {
      button.addEventListener("click", function () {
        var enabled = !window.RpiPreferences.get().musicEnabled;
        window.RpiPreferences.update({ musicEnabled: enabled });
        if (enabled) start();
      });
    });
    if (document.querySelector("[data-game]")) {
      var unlock = function (event) {
        if (event.target.closest("[data-music-toggle]")) return;
        var preferences = window.RpiPreferences.get();
        if ((!context || context.state !== "running") && preferences.musicEnabled && preferences.volume > 0) start();
      };
      document.addEventListener("pointerdown", unlock);
      document.addEventListener("keydown", unlock);
      start();
    }
  });
  document.addEventListener("rpi:preferences", sync);
  document.addEventListener("visibilitychange", sync);
  window.addEventListener("pagehide", function () {
    window.clearInterval(timer);
    timer = null;
    if (context) context.close().catch(function () {});
    context = null;
  });
})();
