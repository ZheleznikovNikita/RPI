const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const source = require('node:fs').readFileSync('app/assets/javascripts/voice_input.js', 'utf8');

function harness({ supported = true, draft = '' } = {}) {
  function element() {
    return { listeners: {}, value: '', classList: { add() {}, remove() {} },
      addEventListener(name, fn) { this.listeners[name] = fn; },
      dispatchEvent(event) { this.listeners[event.type]?.(event); },
      setAttribute(name, value) { this[name] = value; }, setPointerCapture() {} };
  }
  const input = element(), send = element(), mic = element(), status = element();
  input.value = draft; input.maxLength = 2000;
  const selectors = { '[name="command"]': input, '[data-send-command]': send, '[data-voice-input]': mic, '[data-voice-status]': status };
  const form = { querySelector: s => selectors[s] }, document = element(), window = element();
  document.querySelector = () => form;
  const engines = [], observers = [], timers = new Set();
  class Engine {
    constructor() { engines.push(this); }
    start() { this.running = true; }
    stop() { this.stopped = true; }
    abort() { this.aborted = true; }
  }
  if (supported) window.SpeechRecognition = Engine;
  vm.runInNewContext(source, { window, document, Event: class { constructor(type) { this.type = type; } },
    MutationObserver: class { constructor(fn) { observers.push(fn); } observe() {} },
    setTimeout(fn) { timers.add(fn); return fn; }, clearTimeout(fn) { timers.delete(fn); } });
  document.listeners.DOMContentLoaded();
  const press = () => mic.listeners.pointerdown({ button: 0, pointerId: 1, preventDefault() {} });
  const release = () => mic.listeners.pointerup({ pointerId: 1 });
  const result = (engine, text) => engine.onresult({ results: [Object.assign([{ transcript: text }], { isFinal: true })] });
  return { input, send, mic, status, engines, observers, press, release, result, window, timers };
}

test('hold records Russian, release stops, result becomes an editable draft without submitting', () => {
  const h = harness();
  assert.equal(h.send.hidden, true);
  h.press(); const engine = h.engines[0]; engine.onstart();
  assert.equal(engine.lang, 'ru-RU');
  h.result(engine, 'Осмотреть ворота');
  assert.equal(h.input.value, '');
  h.release(); assert.equal(engine.stopped, true);
  engine.onend();
  assert.equal(h.input.value, 'Осмотреть ворота');
  assert.equal(h.send.hidden, false);
  assert.equal(h.mic.hidden, true);
  assert.equal(h.timers.size, 0);
});

test('existing text and busy game prevent recording; clearing restores microphone', () => {
  const h = harness({ draft: 'Текст' });
  h.press(); assert.equal(h.engines.length, 0);
  h.input.value = ''; h.input.dispatchEvent({ type: 'input' });
  assert.equal(h.mic.hidden, false);
  h.input.readOnly = true; h.observers[0](); h.press();
  assert.equal(h.engines.length, 0);
});

test('release while waiting for permission stops as soon as recognition starts', () => {
  const h = harness(); h.press(); h.release();
  h.engines[0].onstart(); assert.equal(h.engines[0].stopped, true);
});

test('cancel ignores late results and restores controls', () => {
  const h = harness(); h.press(); const engine = h.engines[0];
  h.window.listeners.pagehide();
  assert.equal(engine.aborted, true);
  h.result(engine, 'Поздний результат'); engine.onend();
  assert.equal(h.input.value, ''); assert.equal(h.mic['aria-pressed'], 'false');
});

test('permission errors, empty results, unsupported browsers preserve text input', () => {
  const h = harness(); h.press(); h.engines[0].onerror({ error: 'not-allowed' });
  assert.match(h.status.textContent, /Разрешите/);
  h.press(); h.engines[1].onend(); assert.match(h.status.textContent, /не распознана/);
  const unsupported = harness({ supported: false });
  assert.equal(unsupported.mic.disabled, true);
  unsupported.input.value = 'Вручную'; unsupported.input.dispatchEvent({ type: 'input' });
  assert.equal(unsupported.send.hidden, false);
});

test('keyboard hold and cancellation on busy state', () => {
  const h = harness();
  h.mic.listeners.keydown({ key: ' ', preventDefault() {} });
  const engine = h.engines[0]; engine.onstart();
  h.mic.listeners.keyup({ key: ' ', preventDefault() {} });
  assert.equal(engine.stopped, true);
  h.send.disabled = true; h.observers[1]();
  assert.equal(engine.aborted, true);
});
