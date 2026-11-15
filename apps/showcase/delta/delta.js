import { createDeltaScene } from './delta-scene.js';

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const reduceMedia = window.matchMedia('(prefers-reduced-motion: reduce)');

const PLATES = {
  hero: './assets/operations-scene.jpg',
  operations: './assets/operations-scene.jpg',
  warfare: './assets/warfare-scene.jpg',
  spaceport: './assets/spaceport-scene.jpg',
  valley: './assets/longbow-valley-scene.jpg',
  squad: './assets/operations-scene.jpg',
  deploy: './assets/warfare-scene.jpg',
};

const modes = {
  operations: {
    category: '探索 / 搜集 / 撤离',
    description: '进入战局，规划路线与装备，在信息沟通和战术配合中寻找撤离机会。',
    goal: '带出搜集到的物资并撤离',
    rhythm: '潜行、交火与路线判断交替',
    slot: '路线沟通 · 队内报点',
    label: 'OPERATIONS',
    index: '01 / 02',
    caption: '烽火地带 · 3D 场景',
    plate: PLATES.operations,
  },
  warfare: {
    category: '进攻 / 防守 / 协同',
    description: '在大规模战场中配合队友推进目标。步兵与载具共同参与，让每个位置的行动形成合力。',
    goal: '推进目标点并守住阵线',
    rhythm: '载具推进、阵地攻防与协同',
    slot: '载具协同 · 阵地支援',
    label: 'WARFARE',
    index: '02 / 02',
    caption: '全面战场 · 3D 场景',
    plate: PLATES.warfare,
  },
};

const maps = {
  spaceport: { name: '航天基地', subtitle: 'SPACE CITY', code: 'SCN-01', plate: PLATES.spaceport, description: '从开阔区域到建筑内部，和小队一起观察地形、沟通路线。' },
  valley: { name: '长弓溪谷', subtitle: 'LAYALI GROVE', code: 'SCN-02', plate: PLATES.valley, description: '穿行山地与建筑之间，观察视野变化，和队友一起安排下一段路线。' },
};

const chapters = [
  { id: 'entry', key: 'hero', code: 'ENTRY', light: false, paper: false, plate: PLATES.hero },
  { id: 'modes', key: 'modes', code: 'MODES', light: true, paper: true, plate: PLATES.operations },
  { id: 'maps', key: 'terrain', code: 'TERRAIN', light: false, paper: false, plate: PLATES.spaceport },
  { id: 'squad', key: 'squad', code: 'SQUAD', light: true, paper: true, plate: PLATES.squad },
  { id: 'deploy', key: 'deploy', code: 'DEPLOY', light: false, paper: false, plate: PLATES.deploy },
];
const sections = chapters.map((c) => ({ ...c, el: $(c.id) }));
const noWebglFallback = PLATES.hero;

const loader = $('loader');
const loaderProgress = $('loader-progress');
const loaderFill = $('loader-fill');
const enterSound = $('enter-sound');
const enterSilent = $('enter-silent');
const canvas = $('scene');
const fallbackPlate = $('fallback-plate');
const fallbackOperator = $('fallback-operator');
const cursor = $('cursor');
const cursorLabel = $('cursor-label');
const topbar = document.querySelector('.topbar');
const hudChapter = $('hud-chapter');
const hudScroll = $('hud-scroll');
const hudViewport = $('hud-viewport');
const hudStage = $('hud-stage');
const hudClock = $('hud-clock');
const stageStatus = $('stage-status');
const railProgress = $('rail-progress');
const filmDialog = $('film-dialog');
const filmVideo = $('film-video');
const menuDialog = $('menu-dialog');
const soundToggle = $('sound-toggle');
const motionToggle = $('motion-toggle');

let modeKey = 'operations';
let mapKey = 'spaceport';
let userPaused = reduceMedia.matches;
let activeKey = '';
let entered = false;
let scene = null;
let sceneReady = false;
let loadProgress = 0;
let filmOpen = false;

/* ───── 文本拆分：逐字显影 ───── */
function splitType(root) {
  const splitNode = (node, counter) => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent;
      if (!text.trim()) return;
      const frag = document.createDocumentFragment();
      for (const ch of text) {
        if (ch === ' ' || ch === '\n') { frag.appendChild(document.createTextNode(' ')); continue; }
        const span = document.createElement('span');
        span.className = 'char';
        span.style.setProperty('--i', counter.n++);
        span.textContent = ch;
        frag.appendChild(span);
      }
      node.replaceWith(frag);
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    if (node.tagName === 'BR') return;
    [...node.childNodes].forEach((child) => splitNode(child, counter));
  };
  const counter = { n: 0 };
  const blocks = [];
  const walk = (el) => {
    [...el.childNodes].forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE && (node.tagName === 'BR' || node.tagName === 'EM' || node.tagName === 'I')) {
        if (node.tagName === 'BR') { blocks.push('br'); return; }
      }
    });
  };
  void walk;
  // 逐行容器：以 <br> 分隔包装
  const lines = [];
  let current = [];
  [...root.childNodes].forEach((node) => {
    if (node.nodeType === Node.ELEMENT_NODE && node.tagName === 'BR') {
      lines.push(current); current = [];
    } else {
      current.push(node);
    }
  });
  lines.push(current);
  root.textContent = '';
  for (const lineNodes of lines) {
    if (!lineNodes.length) continue;
    const line = document.createElement('span');
    line.className = 'tl';
    const holder = document.createElement('span');
    for (const node of lineNodes) holder.appendChild(node);
    splitNode(holder, counter);
    line.appendChild(holder);
    root.appendChild(line);
  }
}

document.querySelectorAll('.hero-title, .reveal-type').forEach((el) => {
  splitType(el);
});

/* ───── 环境声（程序生成，无版权素材） ───── */
class Ambience {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.enabled = false;
    this.whooshGain = null;
  }
  async build() {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return false;
    this.ctx = new Ctx();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.0001;
    this.master.connect(this.ctx.destination);
    const droneGain = this.ctx.createGain();
    droneGain.gain.value = 0.035;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 260;
    filter.Q.value = 0.7;
    droneGain.connect(filter).connect(this.master);
    const oscA = this.ctx.createOscillator();
    oscA.type = 'sine';
    oscA.frequency.value = 55;
    const oscB = this.ctx.createOscillator();
    oscB.type = 'triangle';
    oscB.frequency.value = 82.5;
    oscB.detune.value = 4;
    oscA.connect(droneGain);
    oscB.connect(droneGain);
    oscA.start();
    oscB.start();
    const lfo = this.ctx.createOscillator();
    const lfoGain = this.ctx.createGain();
    lfo.frequency.value = 0.05;
    lfoGain.gain.value = 90;
    lfo.connect(lfoGain).connect(filter.frequency);
    lfo.start();
    // 噪声垫层
    const length = this.ctx.sampleRate * 2;
    const buffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * 0.4;
    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;
    noise.loop = true;
    const noiseFilter = this.ctx.createBiquadFilter();
    noiseFilter.type = 'bandpass';
    noiseFilter.frequency.value = 380;
    noiseFilter.Q.value = 0.5;
    const noiseGain = this.ctx.createGain();
    noiseGain.gain.value = 0.012;
    noise.connect(noiseFilter).connect(noiseGain).connect(this.master);
    noise.start();
    return true;
  }
  async enable() {
    if (!this.ctx) await this.build();
    if (!this.ctx) return false;
    await this.ctx.resume().catch(() => {});
    this.master.gain.cancelScheduledValues(this.ctx.currentTime);
    this.master.gain.linearRampToValueAtTime(0.5, this.ctx.currentTime + 1.4);
    this.enabled = true;
    return true;
  }
  disable() {
    if (!this.ctx) return;
    this.master.gain.cancelScheduledValues(this.ctx.currentTime);
    this.master.gain.linearRampToValueAtTime(0.0001, this.ctx.currentTime + 0.6);
    this.enabled = false;
  }
  async toggle() {
    const on = await this.enable();
    if (!on) return false;
    return true;
  }
  whoosh(strength = 1) {
    if (!this.ctx || !this.enabled) return;
    const { ctx } = this;
    const length = Math.floor(ctx.sampleRate * 0.8);
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 2.2);
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(240, ctx.currentTime);
    filter.frequency.exponentialRampToValueAtTime(1900, ctx.currentTime + 0.55);
    filter.Q.value = 0.9;
    const gain = ctx.createGain();
    gain.gain.value = 0.05 * strength;
    src.connect(filter).connect(gain).connect(this.master);
    src.start();
  }
}
const ambience = new Ambience();

/* ───── 场景初始化 ───── */
function updateLoader(progress) {
  loadProgress = clamp(progress, 0, 1);
  const value = Math.round(loadProgress * 100);
  loaderProgress.textContent = String(value).padStart(3, '0');
  loaderFill.style.transform = `scaleX(${loadProgress.toFixed(3)})`;
}

function setFallbackFor(plate, showOperator) {
  if (fallbackPlate.getAttribute('src') !== plate) fallbackPlate.src = plate;
  fallbackOperator.style.opacity = showOperator ? '1' : '0';
}

function enterSite(withSound) {
  if (entered) return;
  entered = true;
  document.body.classList.remove('is-locked');
  document.body.classList.add('is-entered');
  if (scene) {
    scene.setEntered(true);
  }
  if (withSound) {
    ambience.enable().then(() => {
      soundToggle.setAttribute('aria-pressed', 'true');
    });
  }
  window.setTimeout(() => loader.setAttribute('aria-hidden', 'true'), 900);
  applyMotionState();
}

(async () => {
  applyMotionState();
  document.body.classList.add('is-locked');
  try {
    scene = await createDeltaScene(canvas, {
      onProgress: updateLoader,
      onFallback: (reason) => {
        document.body.classList.add('no-stage');
        hudStage.textContent = 'STAGE FALLBACK';
        stageStatus.textContent = `3D 场景不可用，已使用静态画面降级（${reason}）`;
      },
    });
  } catch (error) {
    console.warn('scene failed', error);
  }
  if (scene) {
    updateLoader(1);
    scene.setReduced(userPaused);
    sceneReady = true;
    hudStage.textContent = userPaused ? 'STAGE STATIC' : 'STAGE 3D';
    fallbackOperator.style.opacity = '1';
    if (new URLSearchParams(location.search).has('debug')) window.__deltaScene = scene;
  } else {
    document.body.classList.add('no-stage');
    hudStage.textContent = 'STAGE FALLBACK';
  }
  enterSound.disabled = false;
  enterSilent.disabled = false;
  if (reduceMedia.matches) {
    // 减少动态时仍保留进入按钮（音频需要用户手势），但跳过入场动画。
    loaderFill.style.transform = 'scaleX(1)';
  }
  setMode(modeKey, { immediate: true });
  setMap(mapKey, { immediate: true });
  updateViewport();
  preloadImages();
})();

enterSound.addEventListener('click', () => enterSite(true));
enterSilent.addEventListener('click', () => enterSite(false));

function preloadImages() {
  const urls = new Set([...Object.values(PLATES), './assets/operation-role.webp']);
  const list = [...urls];
  let i = 0;
  const next = () => {
    if (i >= list.length) return;
    const img = new Image();
    img.decoding = 'async';
    img.src = list[i++];
    img.onload = img.onerror = () => window.setTimeout(next, 100);
  };
  requestIdleCallback ? requestIdleCallback(next, { timeout: 2200 }) : window.setTimeout(next, 800);
}

/* ───── 章节与滚动 ───── */
function measure() {
  const vh = window.innerHeight;
  const scroll = window.scrollY;
  const max = Math.max(1, document.documentElement.scrollHeight - vh);
  const global = clamp(scroll / max, 0, 1);
  const probe = scroll + vh * 0.38;
  let index = 0;
  for (let i = 0; i < sections.length; i++) {
    if (sections[i].el.offsetTop <= probe) index = i;
  }
  const section = sections[index];
  const top = section.el.offsetTop;
  const height = Math.max(1, section.el.offsetHeight);
  const progress = clamp((scroll + vh * 0.5 - top) / height, 0, 1);
  return { vh, scroll, global, index, section, progress };
}

function updateChapter(index, section) {
  const key = section.key;
  if (key === activeKey) return;
  activeKey = key;
  sections.forEach((s) => s.el.classList.toggle('is-active', s.key === key));
  document.body.classList.toggle('is-paper', section.paper);
  document.body.dataset.chapter = key;
  document.querySelectorAll('[data-nav]').forEach((a) => {
    if (a.dataset.nav === key) a.setAttribute('aria-current', 'true');
    else a.removeAttribute('aria-current');
  });
  document.querySelectorAll('[data-rail]').forEach((a) => {
    if (a.dataset.rail === key) a.setAttribute('aria-current', 'true');
    else a.removeAttribute('aria-current');
  });
  hudChapter.textContent = `CH.${String(index).padStart(2, '0')} / ${section.code}`;
  stageStatus.textContent = `当前章节：${section.code}`;
  const plate = key === 'modes' ? modes[modeKey].plate : key === 'terrain' ? maps[mapKey].plate : section.plate;
  setFallbackFor(plate, key === 'hero' || key === 'squad');
  if (scene) {
    scene.setActive(key);
    scene.whoosh?.();
  }
  if (key === 'terrain') startScan();
  ambience.whoosh(0.7);
}

/* ───── 交互：模式 / 地图 ───── */
function setMode(key, { immediate = false } = {}) {
  const data = modes[key];
  if (!data) return;
  modeKey = key;
  $('mode-category').textContent = data.category;
  $('mode-description').textContent = data.description;
  $('mode-goal').textContent = data.goal;
  $('mode-rhythm').textContent = data.rhythm;
  $('mode-slot').textContent = data.slot;
  $('modes-window-index').textContent = data.index;
  $('modes-window-label').textContent = data.label;
  $('modes-caption').textContent = data.caption;
  $('modes-panel').setAttribute('aria-labelledby', `tab-${key}`);
  if (scene) scene.setMode(key);
  if (activeKey === 'modes' || immediate) setFallbackFor(data.plate, false);
}

function setMap(key, { immediate = false } = {}) {
  const data = maps[key];
  if (!data) return;
  mapKey = key;
  $('map-code').textContent = data.code;
  $('map-name').textContent = data.name;
  $('map-subtitle').textContent = data.subtitle;
  $('map-description').textContent = data.description;
  $('map-readout').textContent = `${data.name}官方地图画面`;
  $('map-readout').setAttribute('aria-labelledby', `tab-${key}`);
  if (scene) scene.setMap(key);
  if (activeKey === 'terrain' || immediate) setFallbackFor(data.plate, false);
  startScan({ restart: true });
}

function wireTabs(selector, onSelect) {
  const buttons = [...document.querySelectorAll(selector)];
  buttons.forEach((button, index) => {
    button.addEventListener('click', () => onSelect(button, buttons));
    button.addEventListener('keydown', (event) => {
      let next;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % buttons.length;
      else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index - 1 + buttons.length) % buttons.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = buttons.length - 1;
      if (next !== undefined) {
        event.preventDefault();
        buttons[next].focus();
        buttons[next].click();
      }
    });
  });
  return buttons;
}
function selectTab(buttons, button) {
  buttons.forEach((item) => {
    const selected = item === button;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
  });
}
wireTabs('[data-mode]', (button, buttons) => { selectTab(buttons, button); setMode(button.dataset.mode); });
wireTabs('[data-map]', (button, buttons) => { selectTab(buttons, button); setMap(button.dataset.map); });

/* ───── 扫描 ───── */
let scanTimer = 0;
function startScan({ restart = false } = {}) {
  const button = $('rescan');
  if (restart) {
    button.classList.add('is-active');
    window.clearTimeout(scanTimer);
    scanTimer = window.setTimeout(() => button.classList.remove('is-active'), 2000);
  }
  if (scene) {
    scene.scanPulse?.();
    ambience.whoosh?.(0.4);
  }
}
$('rescan').addEventListener('click', () => startScan({ restart: true }));

/* ───── 影像 / 菜单 ───── */
function loadFilm() {
  const source = filmVideo.querySelector('source');
  if (!source.hasAttribute('src')) {
    source.src = source.dataset.src;
    filmVideo.load();
  }
}
$('open-film').addEventListener('click', () => {
  loadFilm();
  filmVideo.currentTime = 0;
  filmDialog.showModal();
  filmOpen = true;
  filmVideo.play().catch(() => {});
  if (scene) scene.stopVideo?.();
});
$('close-film').addEventListener('click', () => filmDialog.close());
filmDialog.addEventListener('click', (event) => {
  if (event.target !== filmDialog) return;
  const rect = filmDialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) filmDialog.close();
});
filmDialog.addEventListener('close', () => {
  filmVideo.pause();
  filmOpen = false;
  $('open-film').focus();
  if (scene && entered) scene.startVideo?.();
});
$('open-menu').addEventListener('click', () => menuDialog.showModal());
$('close-menu').addEventListener('click', () => menuDialog.close());
menuDialog.addEventListener('click', (event) => {
  if (event.target === menuDialog) menuDialog.close();
});
document.querySelectorAll('[data-menu]').forEach((a) => a.addEventListener('click', () => menuDialog.close()));

/* ───── 声音 / 动态 / 时钟 ───── */
soundToggle.addEventListener('click', async () => {
  if (ambience.enabled) {
    ambience.disable();
    soundToggle.setAttribute('aria-pressed', 'false');
  } else {
    await ambience.enable();
    soundToggle.setAttribute('aria-pressed', 'true');
  }
});

function applyMotionState() {
  document.body.classList.toggle('reduce-motion', userPaused);
  motionToggle.setAttribute('aria-pressed', String(userPaused));
  motionToggle.setAttribute('aria-label', userPaused ? '恢复动态' : '暂停动态');
  if (scene) scene.setReduced(userPaused);
  if (!document.body.classList.contains('no-stage')) hudStage.textContent = userPaused ? 'STAGE STATIC' : 'STAGE 3D';
}
motionToggle.addEventListener('click', () => {
  userPaused = !userPaused;
  applyMotionState();
});
reduceMedia.addEventListener('change', () => {
  userPaused = reduceMedia.matches;
  applyMotionState();
});

function updateClock() {
  hudClock.textContent = new Date().toLocaleTimeString('zh-CN', { hour12: false });
}
updateClock();
window.setInterval(updateClock, 1000);

function updateViewport() {
  hudViewport.textContent = `VIEWPORT ${window.innerWidth} × ${window.innerHeight}`;
}
updateViewport();
window.addEventListener('resize', updateViewport);

/* ───── 指针 / 自定义光标 / 3D 拾取 ───── */
const pointer = { x: window.innerWidth / 2, y: window.innerHeight / 2, tx: window.innerWidth / 2, ty: window.innerHeight / 2 };
const cursorState = { hover: false, label: '', down: false };
let picked = null;

function setCursorHover(hover, label = '') {
  cursorState.hover = hover;
  cursorState.label = label;
  cursor.classList.toggle('is-hover', hover);
  cursorLabel.textContent = label;
}
function setCursorDown(down) {
  cursorState.down = down;
  cursor.classList.toggle('is-hold', down);
}
function updateCursor(dt) {
  pointer.x += (pointer.tx - pointer.x) * (1 - Math.exp(-14 * dt));
  pointer.y += (pointer.ty - pointer.y) * (1 - Math.exp(-14 * dt));
  cursor.style.transform = `translate3d(${pointer.x}px, ${pointer.y}px, 0)`;
}
function pointFromEvent(event) {
  return { x: event.clientX, y: event.clientY };
}
window.addEventListener('pointermove', (event) => {
  if (event.pointerType === 'touch') return;
  pointer.tx = event.clientX;
  pointer.ty = event.clientY;
  const nx = (event.clientX / window.innerWidth) * 2 - 1;
  const ny = -((event.clientY / window.innerHeight) * 2 - 1);
  if (scene) {
    scene.setPointer(nx, ny);
    scene.setPointerNdc(nx, ny);
    const result = scene.pick();
    picked = result;
    scene.setHover(result);
  }
  const target = event.target.closest?.('[data-cursor]');
  if (target) {
    setCursorHover(true, target.dataset.cursor);
  } else if (picked?.type === 'member') {
    setCursorHover(true, '查看成员');
  } else if (picked?.type === 'deploy') {
    setCursorHover(true, '打开 App');
  } else {
    setCursorHover(false);
  }
}, { passive: true });

window.addEventListener('pointerdown', (event) => {
  if (event.target.closest('button,a,dialog')) return;
  const hold = event.target.closest('#hold-button');
  if (hold) {
    hold.classList.add('is-holding');
    scene?.setHold(true);
    setCursorDown(true);
    hold.setPointerCapture?.(event.pointerId);
    return;
  }
  const maps = event.target.closest('#maps');
  if (maps) {
    mapDrag.active = true;
    mapDrag.startX = event.clientX;
    mapDrag.value = 0;
    maps.setPointerCapture?.(event.pointerId);
    setCursorDown(true);
  }
}, true);

window.addEventListener('pointermove', (event) => {
  if (!mapDrag.active) return;
  const value = clamp((event.clientX - mapDrag.startX) / 260, -1, 1);
  mapDrag.value = value;
  scene?.setMapDrag(value);
}, { passive: true });

function releasePointer() {
  document.getElementById('hold-button')?.classList.remove('is-holding');
  scene?.setHold(false);
  setCursorDown(false);
  if (mapDrag.active) {
    mapDrag.active = false;
    window.setTimeout(() => {
      scene?.setMapDrag(0);
    }, 900);
  }
}
window.addEventListener('pointerup', releasePointer);
window.addEventListener('pointercancel', releasePointer);
window.addEventListener('pointerleave', releasePointer);

const mapDrag = { active: false, startX: 0, value: 0 };

window.addEventListener('click', (event) => {
  if (event.target.closest('button,a,dialog')) return;
  if (!picked) return;
  if (picked.type === 'member') window.location.href = '/demo/?screen=player&device=iphone';
  else if (picked.type === 'deploy') window.location.href = '/demo/?screen=service&device=iphone';
});

/* ───── 主循环 ───── */
let last = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = last ? Math.min(0.05, (now - last) / 1000) : 0.016;
  last = now;
  if (document.hidden) return;
  if (document.body.classList.contains('has-cursor') && entered) updateCursor(dt);
  const metrics = measure();
  updateChapter(metrics.index, metrics.section);
  topbar.classList.toggle('is-scrolled', metrics.scroll > 40);
  railProgress.style.height = `${(metrics.global * 100).toFixed(2)}%`;
  hudScroll.textContent = `SCROLL ${String(Math.round(metrics.global * 100)).padStart(3, '0')}%`;
  if (scene) {
    sections.forEach((s) => scene.setProgress(s.key, s.key === metrics.section.key ? metrics.progress : 0));
    if (mapDrag.active) scene.setMapDrag(mapDrag.value);
  }
  // 首屏文字随滚动轻微位移
  const heroSticky = sections[0]?.el.querySelector('.hero-sticky');
  if (heroSticky) {
    const heroProgress = metrics.section.key === 'hero' ? metrics.progress : 0;
    heroSticky.style.setProperty('--hp', heroProgress.toFixed(3));
  }
}
requestAnimationFrame(frame);

/* ── 首屏文字滚动位移（用 CSS 变量驱动） ── */
const styleTag = document.createElement('style');
styleTag.textContent = `
.hero-title{transform:translate3d(0, calc(var(--hp,0) * -70px), 0)}
.hero-ghost{transform:translate3d(0, calc(var(--hp,0) * 90px), 0)}
.hero-lead{transform:translate3d(0, calc(var(--hp,0) * -36px), 0)}
`;
document.head.appendChild(styleTag);
