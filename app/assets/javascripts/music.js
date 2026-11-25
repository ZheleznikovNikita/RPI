(function () {
  "use strict";
  // Original numerical scores and synthesis, CC0-1.0. No recordings or network calls.
  var soundtracks = {
    calm: {label:"Спокойствие",tempo:72,bars:32,pad:"sine",lead:"sine",cutoff:2200,
      chords:[[48,55,60,64],[53,57,60,65],[57,60,64,67],[55,59,62,67],[50,57,62,65],[53,60,64,69],[55,59,62,69],[48,55,60,64]],
      melody:[[72,76,79,76],[77,76,72,69],[76,79,81,79],[74,71,67,null],[74,77,81,77],[76,72,69,72],[74,79,77,71],[72,67,64,null]],
      rhythm:[0,1.5,2.5,3.25],lengths:[1.35,0.85,0.65,0.65]},
    battle: {label:"Сражение",tempo:144,bars:32,pad:"sawtooth",lead:"square",cutoff:1800,
      chords:[[50,57,62,65],[46,53,58,62],[48,55,60,64],[45,52,57,61],[50,57,62,65],[53,60,65,69],[43,50,55,58],[45,52,57,61]],
      melody:[[74,74,77,76,74,69,72,73],[74,70,77,74,70,65,69,70],[72,72,76,74,72,67,71,72],[73,69,76,73,69,64,67,69],[77,76,74,81,77,74,72,74],[77,81,84,81,79,77,76,72],[79,74,77,74,70,67,69,70],[73,null,76,73,69,73,76,null]],
      rhythm:[0,0.5,1,1.5,2,2.5,3,3.5],lengths:[0.28,0.2,0.3,0.2,0.28,0.2,0.3,0.2]},
    tension: {label:"Напряжение",tempo:54,bars:32,pad:"triangle",lead:"sine",cutoff:650,
      chords:[[33,34,40],[34,40,45],[33,40,46],[40,41,47],[36,37,43],[34,40,46],[31,37,38],[33,34,40]],
      melody:[[61,null,null,60],[null,58,null,null],[64,null,65,null],[null,null,59,null],[61,null,null,63],[null,58,null,null],[59,null,58,null],[null,null,61,null]],
      rhythm:[0.5,1.75,2.25,3.5],lengths:[0.7,0.3,0.6,0.25]},
    mystery: {label:"Тайна / магия",tempo:78,bars:32,pad:"sine",lead:"bell",cutoff:4500,
      chords:[[45,52,59,64],[53,60,64,71],[48,55,62,67],[52,59,66,71],[50,57,64,69],[45,52,60,67],[53,59,64,71],[52,59,64,68]],
      melody:[[88,83,null,86],[89,null,88,83],[86,91,null,83],[90,null,87,null],[88,93,null,86],[91,null,88,84],[95,89,null,88],[87,null,83,null]],
      rhythm:[0,1.25,2.5,3.25],lengths:[3,2.5,2,3]},
    sad: {label:"Грусть / трагедия",tempo:58,bars:32,pad:"sine",lead:"triangle",cutoff:1100,
      chords:[[45,52,57,60],[50,57,62,65],[53,60,65,69],[52,59,64,67],[48,55,60,64],[50,57,60,65],[52,59,64,68],[45,52,57,60]],
      melody:[[76,72,71,69],[74,72,69,null],[77,76,72,69],[71,67,64,null],[72,71,67,64],[69,65,64,null],[68,71,76,71],[69,null,64,null]],
      rhythm:[0,1.75,2.75,3.5],lengths:[1.6,0.9,0.65,1.4]},
    victory: {label:"Победа / триумф",tempo:120,bars:8,pad:"triangle",lead:"sawtooth",cutoff:3200,
      chords:[[48,55,60,64],[53,60,65,69],[55,62,67,71],[48,55,64,67],[57,64,69,72],[53,60,65,69],[55,59,62,67],[48,55,60,64]],
      melody:[[72,76,79,84],[81,77,81,84],[83,79,86,83],[84,79,76,79],[81,84,88,84],[89,84,81,77],[79,83,86,83],[84,null,null,null]],
      rhythm:[0,1,1.5,3],lengths:[0.85,0.4,1.3,0.8]}
  };
  var FADE = 2.5, LOOKAHEAD = 0.18, VICTORY_SECONDS = 16;
  var AudioEngine = window.AudioContext || window.webkitAudioContext;
  var context, master, compressor, noise, timer, pauseTimer;
  var layers = [], target = "calm", scene = {mood:"calm",changedAt:null,gameId:"guest",ended:false};
  var gamePage = false, disposed = false, resetRequested = false, fadeEnds = 0, contextsCreated = 0, layersCreated = 0;

  function valid(mood) { return typeof mood === "string" && Object.prototype.hasOwnProperty.call(soundtracks, mood); }
  function event(events, beat, pitch, length, instrument, strength) {
    if (pitch !== null) events.push({beat:beat,pitch:pitch,length:length,instrument:instrument,strength:strength});
  }
  function compose(mood) {
    var score = soundtracks[mood], events = [];
    for (var bar = 0; bar < score.bars; bar++) {
      var section = Math.floor(bar / 8), index = bar % 8, chord = score.chords[index], beat = bar * 4;
      var quiet = section === 2, energetic = mood === "battle" || mood === "victory";
      if (!energetic && (mood !== "tension" || bar % 2 === 0)) chord.forEach(function (pitch) {
        event(events, beat, pitch, mood === "tension" ? 7.5 : 4.5, "pad", quiet ? 0.022 : 0.03);
      });
      if (energetic) {
        [0,1.5,2,3.5].forEach(function (offset) {
          event(events, beat + offset, chord[0] - 12, 0.3, "bass", 0.075);
          if (offset === 0 || offset === 2) chord.slice(1).forEach(function (pitch) { event(events, beat + offset, pitch, 0.35, "pad", 0.025); });
        });
        [0,2].forEach(function (offset) { event(events, beat + offset, 0, 0.35, "kick", 0.13); });
        [1,3].forEach(function (offset) { event(events, beat + offset, 0, 0.18, "snare", 0.06); });
        if (mood === "battle") for (var hit = 0; hit < 8; hit++) event(events, beat + hit / 2, 0, 0.07, "hat", hit % 2 ? 0.028 : 0.018);
      } else {
        event(events, beat, chord[0] - (mood === "tension" ? 0 : 12), mood === "tension" ? 0.6 : 3.8, "bass", mood === "tension" ? 0.065 : 0.045);
        if (mood === "tension" && bar % 4 !== 3) event(events, beat + 2.75, chord[0], 0.4, "bass", 0.04);
      }
      var phrase = score.melody[index];
      score.rhythm.forEach(function (offset, step) {
        if (quiet && step === 1) return;
        var pitch = phrase[step];
        if (pitch !== null && section === 1 && index % 2 === 0) pitch += mood === "tension" ? -12 : 12;
        if (pitch !== null && section === 3 && index % 2 === 1) pitch -= 12;
        event(events, beat + offset, pitch, mood === "victory" && bar === 7 ? 5 : score.lengths[step], "lead", quiet ? 0.055 : energetic ? 0.065 : 0.075);
      });
      if ((section === 1 || section === 3) && mood !== "tension" && bar % 2 === 0) chord.slice(1).forEach(function (pitch, step) {
        event(events, beat + 0.75 + step, pitch + 12, 0.65, "answer", 0.027);
      });
    }
    return events.sort(function (a, b) { return a.beat - b.beat; });
  }
  var scores = {};
  Object.keys(soundtracks).forEach(function (mood) { scores[mood] = compose(mood); });
  function status(text) { document.querySelectorAll("[data-music-status]").forEach(function (node) { node.textContent = text; }); }
  function refresh() {
    var preferences = window.RpiPreferences.get();
    document.querySelectorAll("[data-music-toggle]").forEach(function (button) {
      button.setAttribute("aria-pressed", String(preferences.musicEnabled));
      button.textContent = preferences.musicEnabled ? "Выключить музыку" : "Включить музыку";
      button.disabled = !AudioEngine;
    });
    if (!AudioEngine) status("Этот браузер не поддерживает воспроизведение музыки.");
    else if (!preferences.musicEnabled) status("Музыка выключена.");
    else if (preferences.volume === 0) status("Громкость установлена на 0%.");
    else if (context && context.state === "running") status("Сейчас играет: " + soundtracks[target].label);
    else if (gamePage && !scene.ended) status("Для запуска музыки нажмите на игровой экран.");
  }
  function resolvedMood() {
    if (scene.mood === "victory" && scene.changedAt && Date.now() / 1000 >= scene.changedAt + VICTORY_SECONDS) return "calm";
    return scene.mood;
  }
  function destroyLayer(layer) {
    layer.nodes.forEach(function (record) {
      try { record.source.stop(); } catch (_) { /* Already ended. */ }
      record.nodes.forEach(function (node) { node.disconnect(); });
    });
    layer.nodes.clear(); layer.graph.forEach(function (node) { node.disconnect(); });
    layers = layers.filter(function (other) { return other !== layer; });
  }
  function createLayer(mood, gain) {
    var bus = context.createGain(), input = context.createGain();
    input.connect(bus); bus.gain.value = gain; bus.connect(master);
    var graph = [input,bus];
    if (mood === "mystery") {
      var delay = context.createDelay(1), wet = context.createGain(), feedback = context.createGain();
      delay.delayTime.value = 0.34; wet.gain.value = 0.22; feedback.gain.value = 0.18;
      input.connect(delay); delay.connect(wet); wet.connect(bus); delay.connect(feedback); feedback.connect(delay);
      graph.push(delay, wet, feedback);
    }
    var elapsed = mood === "victory" && scene.changedAt ? Math.max(0, Date.now() / 1000 - scene.changedAt) : 0;
    var layer = {mood:mood,bus:bus,input:input,graph:graph,nodes:new Set(),cursor:0,cycle:0,start:context.currentTime + 0.05 - elapsed};
    var seconds = 60 / soundtracks[mood].tempo;
    while (layer.cursor < scores[mood].length && scores[mood][layer.cursor].beat * seconds < elapsed) layer.cursor++;
    layers.push(layer); layersCreated++;
    return layer;
  }
  function changeTheme() {
    target = resolvedMood();
    if (!context || context.state !== "running" || !layers.length || fadeEnds > context.currentTime) return;
    if (layers[0].mood === target && !resetRequested) return;
    resetRequested = false;
    var old = layers[0], now = context.currentTime, incoming = createLayer(target, 0);
    old.bus.gain.cancelScheduledValues(now); old.bus.gain.setValueAtTime(1, now);
    old.bus.gain.linearRampToValueAtTime(0, now + FADE);
    incoming.bus.gain.setValueAtTime(0, now); incoming.bus.gain.linearRampToValueAtTime(1, now + FADE);
    fadeEnds = now + FADE;
  }
  function playNote(layer, entry, start, seconds) {
    var audio = layer.audio || context;
    var score = soundtracks[layer.mood], duration = Math.max(0.035, entry.length * seconds);
    var envelope = audio.createGain(), filter = audio.createBiquadFilter(), source;
    var drum = entry.instrument === "hat" || entry.instrument === "snare";
    if (drum) {
      source = audio.createBufferSource(); source.buffer = layer.noise || noise;
      filter.type = entry.instrument === "hat" ? "highpass" : "bandpass";
      filter.frequency.value = entry.instrument === "hat" ? 6500 : 1800; filter.Q.value = 0.7;
    } else {
      source = audio.createOscillator();
      source.type = entry.instrument === "kick" ? "sine" : entry.instrument === "pad" ? score.pad : entry.instrument === "bass" ? "triangle" : score.lead === "bell" ? "sine" : score.lead;
      if (entry.instrument === "kick") {
        duration = 0.22; source.frequency.setValueAtTime(145, start); source.frequency.exponentialRampToValueAtTime(42, start + 0.18);
      } else source.frequency.value = 440 * Math.pow(2, (entry.pitch - 69) / 12);
      filter.type = "lowpass"; filter.frequency.value = entry.instrument === "bass" ? 650 : score.cutoff; filter.Q.value = 0.5;
    }
    var softPad = entry.instrument === "pad" && layer.mood !== "battle" && layer.mood !== "victory";
    var attack = softPad ? Math.min(0.6, duration / 3) : 0.012;
    envelope.gain.setValueAtTime(0, start); envelope.gain.linearRampToValueAtTime(entry.strength, start + attack);
    envelope.gain.exponentialRampToValueAtTime(0.0001, start + duration); envelope.gain.linearRampToValueAtTime(0, start + duration + 0.02);
    source.connect(filter); filter.connect(envelope); envelope.connect(layer.input);
    var record = {source:source,nodes:[source,filter,envelope]}; layer.nodes.add(record);
    source.onended = function () { record.nodes.forEach(function (node) { node.disconnect(); }); layer.nodes.delete(record); };
    source.start(start); source.stop(start + duration + 0.025);
    if (score.lead === "bell" && entry.instrument === "lead") playNote(layer,
      Object.assign({}, entry, {pitch:entry.pitch + 19.1,instrument:"answer",strength:entry.strength * 0.22,length:entry.length * 0.55}), start, seconds);
  }
  function scheduleLayer(layer) {
    var score = soundtracks[layer.mood], events = scores[layer.mood], seconds = 60 / score.tempo;
    var now = context.currentTime, horizon = now + LOOKAHEAD, cycleLength = score.bars * 4 * seconds;
    if (layer.mood !== "victory" && now - layer.start > (layer.cycle + 1) * cycleLength) {
      layer.cycle = Math.floor((now - layer.start) / cycleLength); layer.cursor = 0;
    }
    for (var count = 0; count < 512; count++) {
      if (layer.cursor >= events.length) { if (layer.mood === "victory") return; layer.cursor = 0; layer.cycle++; }
      var entry = events[layer.cursor], at = layer.start + layer.cycle * cycleLength + entry.beat * seconds;
      if (at > horizon) return;
      if (at >= now) playNote(layer, entry, at, seconds);
      layer.cursor++;
    }
  }
  function tick() {
    if (!context || context.state !== "running" || disposed || scene.ended) return;
    if (fadeEnds && context.currentTime >= fadeEnds) { destroyLayer(layers[0]); fadeEnds = 0; }
    changeTheme(); layers.forEach(scheduleLayer); refresh();
  }
  function buildContext() {
    context = new AudioEngine(); contextsCreated++;
    master = context.createGain(); master.gain.value = 0;
    compressor = context.createDynamicsCompressor();
    compressor.threshold.value = -16; compressor.knee.value = 12; compressor.ratio.value = 4;
    compressor.attack.value = 0.006; compressor.release.value = 0.18;
    master.connect(compressor); compressor.connect(context.destination);
    // Deterministic noise synthesized in memory for percussion; not a loaded sample.
    noise = createNoise(context);
    context.onstatechange = refresh;
  }
  function createNoise(audio) {
    var buffer = audio.createBuffer(1, Math.ceil(audio.sampleRate * 0.5), audio.sampleRate);
    var data = buffer.getChannelData(0), seed = 98317;
    for (var i = 0; i < data.length; i++) { seed = (1664525 * seed + 1013904223) >>> 0; data[i] = seed / 2147483648 - 1; }
    return buffer;
  }
  // Development/QA: renders the same synthesizer without playback or file export.
  async function renderPreview(mood, seconds) {
    if (!valid(mood)) throw new Error("Unknown music mood");
    seconds = Math.max(1, Math.min(20, Number(seconds) || 4));
    var OfflineEngine = window.OfflineAudioContext || window.webkitOfflineAudioContext;
    if (!OfflineEngine) throw new Error("Offline Web Audio is unavailable");
    var audio = new OfflineEngine(1, Math.ceil(seconds * 44100), 44100), output = audio.createGain();
    output.gain.value = 0.4; output.connect(audio.destination);
    var layer = { mood: mood, input: output, nodes: new Set(), audio: audio, noise: createNoise(audio) };
    scores[mood].forEach(function (entry) {
      var at = entry.beat * 60 / soundtracks[mood].tempo;
      if (at < seconds) playNote(layer, entry, at, 60 / soundtracks[mood].tempo);
    });
    return audio.startRendering();
  }
  async function start() {
    if (!AudioEngine || !gamePage || disposed || scene.ended) return;
    var preferences = window.RpiPreferences.get();
    if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden) return;
    try {
      if (!context) buildContext();
      var activeContext = context;
      await activeContext.resume();
      if (context !== activeContext || disposed) return;
      preferences = window.RpiPreferences.get();
      if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden || scene.ended) { await activeContext.suspend(); return; }
      clearTimeout(pauseTimer); master.gain.setTargetAtTime(preferences.volume / 100 * 0.4, context.currentTime, 0.06);
      target = resolvedMood(); if (!layers.length) { createLayer(target, 1); resetRequested = false; }
      tick(); if (!timer) timer = window.setInterval(tick, 25);
    } catch (_) { status("Музыку пока не удалось запустить. Нажмите на игровой экран ещё раз."); }
    refresh();
  }
  function sync() {
    clearTimeout(pauseTimer);
    var preferences = window.RpiPreferences.get();
    if (!preferences.musicEnabled || preferences.volume === 0 || document.hidden || scene.ended) {
      clearInterval(timer); timer = null;
      if (context && context.state === "running") {
        var activeContext = context;
        master.gain.setTargetAtTime(0, context.currentTime, 0.015);
        pauseTimer = window.setTimeout(function () { if (context === activeContext) activeContext.suspend().catch(function () {}); }, 70);
      }
      refresh();
    } else start();
  }
  function close() {
    disposed = true; clearInterval(timer); clearTimeout(pauseTimer); timer = null; fadeEnds = 0;
    layers.slice().forEach(destroyLayer);
    if (context) { var old = context; context = null; old.onstatechange = null; master.disconnect(); compressor.disconnect(); old.close().catch(function () {}); }
    noise = null;
  }
  function setScene(data) {
    var gameId = String(data.musicGameId || "guest"), mood = valid(data.musicMood) ? data.musicMood : scene.mood;
    var changedAt = Date.parse(data.musicChangedAt || "") / 1000;
    if (mood === "victory" && !Number.isFinite(changedAt)) changedAt = scene.mood === "victory" && scene.gameId === gameId ? scene.changedAt : Date.now() / 1000;
    if (gameId !== scene.gameId) {
      resetRequested = true; disposed = false;
      mood = valid(data.musicMood) ? data.musicMood : "calm";
    } else if (mood === "victory" && changedAt !== scene.changedAt) resetRequested = true;
    scene = {mood:mood,changedAt:Number.isFinite(changedAt) ? changedAt : null,gameId:gameId,ended:data.musicEnded === "true"};
    target = resolvedMood(); if (scene.ended) { close(); refresh(); return; } sync();
  }
  window.RpiMusic = {
    setScene:setScene,
    inspect:function () { return {mood:target,sceneMood:scene.mood,contextState:context ? context.state : "closed",
      contextsCreated:contextsCreated,layersCreated:layersCreated,layers:layers.map(function (layer) { return layer.mood; }),
      nodes:layers.reduce(function (total, layer) { return total + layer.nodes.size; }, 0),fading:fadeEnds > 0,
      masterVolume:window.RpiPreferences.get().volume / 100 * 0.4}; },
    soundtracks:soundtracks,scores:scores,renderPreview:renderPreview
  };
  document.addEventListener("DOMContentLoaded", function () {
    var game = document.querySelector("[data-game]"); gamePage = !!game; refresh();
    document.querySelectorAll("[data-music-toggle]").forEach(function (button) {
      button.addEventListener("click", function () { window.RpiPreferences.update({musicEnabled:!window.RpiPreferences.get().musicEnabled}); });
    });
    if (game) {
      setScene(game.dataset);
      var unlock = function (event) { if (!event.target.closest("[data-music-toggle]")) start(); };
      document.addEventListener("pointerdown", unlock); document.addEventListener("keydown", unlock);
    }
  });
  document.addEventListener("rpi:preferences", sync); document.addEventListener("visibilitychange", sync);
  window.addEventListener("pagehide", close);
  window.addEventListener("pageshow", function (event) { if (event.persisted && !scene.ended) { disposed = false; sync(); } });
})();
