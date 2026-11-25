const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const source = require('node:fs').readFileSync('app/assets/javascripts/music.js', 'utf8');

// Real Web Audio is covered in browser tests. This fake clock verifies precise
// scheduling and teardown without sleeps, audio hardware or paid API requests.
async function harness(options = {}) {
  let now = 0, id = 0, allowed = !options.blocked;
  const timers = new Map(), contexts = [], listeners = {}, windowListeners = {};
  const prefs = { musicEnabled: true, volume: 35, ...options.prefs };
  class Param {
    constructor() { this.value = 0; this.events = []; }
    setValueAtTime(v, t) { assert.ok(Number.isFinite(v + t)); this.events.push(['set', v, t]); this.value = v; }
    linearRampToValueAtTime(v, t) { this.setValueAtTime(v, t); this.events.push(['linear', v, t]); }
    exponentialRampToValueAtTime(v, t) { assert.ok(v > 0); this.setValueAtTime(v, t); }
    setTargetAtTime(v, t) { this.setValueAtTime(v, t); }
    cancelScheduledValues() {}
  }
  class Node {
    constructor(c) { this.c = c; ['gain', 'frequency', 'Q', 'delayTime'].forEach(k => this[k] = new Param()); c.nodes.push(this); }
    connect() { this.connected = true; }
    disconnect() { this.connected = false; }
    start(t) { assert.ok(t >= this.c.currentTime); this.started = true; }
    stop(t = this.c.currentTime) { this.stopAt = t; if (t <= this.c.currentTime) this.end(); }
    end() { if (!this.ended) { this.ended = true; if (this.onended) this.onended(); } }
  }
  class Audio {
    constructor() { this.state = 'suspended'; this.currentTime = 0; this.sampleRate = 48000; this.nodes = []; this.destination = {}; contexts.push(this); }
    createGain() { return new Node(this); }
    createOscillator() { return new Node(this); }
    createBufferSource() { return new Node(this); }
    createBiquadFilter() { return new Node(this); }
    createDelay() { return new Node(this); }
    createBuffer(_c, n) { return { getChannelData: () => new Float32Array(n) }; }
    createDynamicsCompressor() { const n = new Node(this); ['threshold', 'knee', 'ratio', 'attack', 'release'].forEach(k => n[k] = new Param()); return n; }
    resume() { if (!allowed) return Promise.reject(new Error('autoplay')); this.state = 'running'; return Promise.resolve(); }
    suspend() { this.state = 'suspended'; return Promise.resolve(); }
    close() { this.state = 'closed'; return Promise.resolve(); }
  }
  const status = { textContent: '' }, toggle = { setAttribute() {}, addEventListener(n, f) { this[n] = f; } };
  const document = {
    hidden: false, querySelector: () => options.settings ? null : { dataset: { musicMood: options.mood || 'calm', musicGameId: '1' } },
    querySelectorAll: s => s === '[data-music-toggle]' ? [toggle] : [status],
    addEventListener(n, f) { (listeners[n] ||= []).push(f); }
  };
  const emit = (name, event = {}) => (listeners[name] || []).forEach(f => f(event));
  const window = {
    AudioContext: options.unsupported ? undefined : Audio,
    RpiPreferences: { get: () => ({ ...prefs }), update: p => { Object.assign(prefs, p); emit('rpi:preferences'); } },
    setInterval(f, ms) { timers.set(++id, { f, at: now + ms / 1000, interval: ms / 1000 }); return id; },
    setTimeout(f, ms) { timers.set(++id, { f, at: now + ms / 1000 }); return id; },
    clearInterval(i) { timers.delete(i); }, clearTimeout(i) { timers.delete(i); },
    addEventListener(n, f) { (windowListeners[n] ||= []).push(f); }
  };
  class ClockDate extends Date { static now() { return 1800000000000 + now * 1000; } }
  vm.runInNewContext(source, { window, document, Date: ClockDate, clearInterval: window.clearInterval, clearTimeout: window.clearTimeout });
  async function flush() { await Promise.resolve(); await Promise.resolve(); }
  async function advance(seconds) {
    const end = now + seconds;
    while (now < end - 1e-9) {
      const dt = Math.min(0.025, end - now); now += dt;
      contexts.forEach(c => { if (c.state === 'running') c.currentTime += dt; c.nodes.forEach(n => { if (n.stopAt <= c.currentTime) n.end(); }); });
      for (const [key, t] of [...timers]) if (t.at <= now + 1e-9) { if (t.interval) t.at += t.interval; else timers.delete(key); t.f(); }
      await flush();
    }
  }
  emit('DOMContentLoaded'); await flush();
  return { music: window.RpiMusic, contexts, timers, advance, flush, status,
    setMood(mood, extra = {}) { window.RpiMusic.setScene({ musicMood: mood, musicGameId: '1', ...extra }); },
    async prefs(p) { window.RpiPreferences.update(p); await flush(); },
    async visibility(hidden) { document.hidden = hidden; emit('visibilitychange'); await flush(); },
    async gesture() { allowed = true; emit('pointerdown', { target: { closest: () => null } }); await flush(); },
    emitWindow(n, e = {}) { (windowListeners[n] || []).forEach(f => f(e)); }, iso: () => new Date(ClockDate.now()).toISOString()
  };
}

test('six distinctive complete scores have required tempos and notes actually scheduled', async () => {
  const h = await harness(), fingerprints = new Set();
  const ranges = { calm:[60,80], battle:[130,160], tension:[45,65], mystery:[60,90], sad:[50,70], victory:[100,130] };
  for (const [mood, s] of Object.entries(h.music.soundtracks)) {
    assert.ok(s.tempo >= ranges[mood][0] && s.tempo <= ranges[mood][1]);
    assert.ok(h.music.scores[mood].length > 90);
    assert.ok(s.bars * 4 * 60 / s.tempo >= (mood === 'victory' ? 16 : 50));
    fingerprints.add(JSON.stringify([s.chords, s.melody, s.rhythm, s.pad, s.lead]));
  }
  assert.equal(fingerprints.size, 6); await h.advance(1);
  assert.equal(h.music.inspect().mood, 'calm'); assert.ok(h.contexts[0].nodes.some(n => n.started));
});

test('same mood does not restart; 2.5-second crossfade uses one context', async () => {
  const h = await harness();
  for (let i = 0; i < 5; i++) { h.setMood('calm'); await h.flush(); }
  assert.equal(h.music.inspect().layersCreated, 1);
  h.setMood('battle'); await h.flush(); assert.equal(h.music.inspect().layers.length, 2);
  const ramps = h.contexts[0].nodes.flatMap(n => n.gain.events).filter(e => e[0] === 'linear' && e[2] === 2.5);
  assert.ok(ramps.some(e => e[1] === 0) && ramps.some(e => e[1] === 1));
  await h.advance(2.6); assert.deepEqual(Array.from(h.music.inspect().layers), ['battle']);
  assert.equal(h.music.inspect().contextsCreated, 1);
});

test('rapid changes never exceed two layers and resolve to the last requested mood', async () => {
  const h = await harness();
  for (const mood of ['battle','tension','mystery','sad','battle','mystery']) {
    h.setMood(mood); await h.advance(0.08); assert.ok(h.music.inspect().layers.length <= 2);
  }
  await h.advance(5.2); assert.deepEqual(Array.from(h.music.inspect().layers), ['mystery']);
  assert.equal(h.music.inspect().contextsCreated, 1);
});

test('disabled updates cannot enable music; every theme obeys zero and changed volume', async () => {
  const h = await harness({ prefs: { musicEnabled: false } });
  h.setMood('battle'); await h.flush(); assert.equal(h.contexts.length, 0);
  await h.prefs({ musicEnabled: true }); assert.equal(h.music.inspect().mood, 'battle');
  await h.prefs({ volume: 0 }); await h.advance(0.1); assert.equal(h.music.inspect().contextState, 'suspended');
  h.setMood('sad'); await h.flush(); assert.equal(h.music.inspect().contextState, 'suspended');
  await h.prefs({ volume: 100 }); await h.advance(3); assert.deepEqual(Array.from(h.music.inspect().layers), ['sad']);
  for (const mood of Object.keys(h.music.soundtracks)) {
    h.setMood(mood, { musicChangedAt: h.iso() }); await h.advance(3);
    await h.prefs({ volume: 25 }); assert.equal(h.music.inspect().masterVolume, 0.1);
  }
  await h.prefs({ musicEnabled: false }); await h.advance(0.1);
  h.setMood('battle'); await h.flush(); assert.equal(h.music.inspect().contextState, 'suspended');
});

test('victory finishes, repeated snapshots do not replay it and hidden elapsed time is respected', async () => {
  const h = await harness(), began = h.iso();
  h.setMood('victory', { musicChangedAt: began }); await h.advance(4);
  const created = h.music.inspect().layersCreated;
  h.setMood('victory', { musicChangedAt: began }); await h.flush(); assert.equal(h.music.inspect().layersCreated, created);
  await h.visibility(true); await h.advance(20); await h.visibility(false); await h.advance(3);
  assert.deepEqual(Array.from(h.music.inspect().layers), ['calm']);
  h.setMood('victory', { musicChangedAt: '2020-01-01T00:00:00Z' }); await h.flush(); assert.equal(h.music.inspect().mood, 'calm');
});

test('autoplay gesture, visibility, pagehide resource cleanup and BFCache restore', async () => {
  const h = await harness({ blocked: true }); assert.equal(h.music.inspect().contextState, 'suspended');
  await h.gesture(); await h.advance(0.2); assert.equal(h.music.inspect().contextState, 'running');
  await h.visibility(true); await h.advance(0.1); assert.equal(h.music.inspect().contextState, 'suspended');
  await h.visibility(false); await h.flush(); assert.equal(h.music.inspect().contextsCreated, 1);
  h.emitWindow('pagehide'); assert.equal(h.music.inspect().nodes, 0); assert.equal(h.timers.size, 0);
  assert.equal(h.contexts[0].state, 'closed'); assert.ok(h.contexts[0].nodes.every(n => !n.connected));
  h.emitWindow('pageshow', { persisted: true }); await h.flush(); assert.equal(h.music.inspect().contextState, 'running');
  h.setMood('sad', { musicEnded: 'true' }); await h.flush(); assert.equal(h.music.inspect().contextState, 'closed');
});

test('all backgrounds loop without resetting or accumulating sources', async () => {
  for (const mood of ['calm','battle','tension','mystery','sad']) {
    const h = await harness({ mood }), s = h.music.soundtracks[mood];
    await h.advance(s.bars * 4 * 60 / s.tempo + 1);
    assert.equal(h.music.inspect().layersCreated, 1);
    assert.ok(h.music.inspect().nodes > 0 && h.music.inspect().nodes < 80);
  }
});

test('unknown moods preserve state; settings and unsupported browsers do not start audio', async () => {
  const h = await harness({ mood: 'mystery' });
  for (const mood of ['unknown', undefined]) { h.setMood(mood); await h.flush(); assert.equal(h.music.inspect().mood, 'mystery'); }
  const settings = await harness({ settings: true }); await settings.prefs({ musicEnabled: true }); assert.equal(settings.contexts.length, 0);
  const unsupported = await harness({ unsupported: true }); await unsupported.gesture(); assert.equal(unsupported.contexts.length, 0);
});
