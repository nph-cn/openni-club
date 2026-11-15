import { createDeltaStage } from './delta-stage.js';

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const reduceMedia = window.matchMedia('(prefers-reduced-motion: reduce)');

const PLATES = {
  entry: './assets/operations-scene.jpg',
  operations: './assets/operations-scene.jpg',
  warfare: './assets/warfare-scene.jpg',
  spaceport: './assets/spaceport-scene.jpg',
  valley: './assets/longbow-valley-scene.jpg',
  squad: './assets/operations-scene.jpg',
  deploy: './assets/warfare-scene.jpg',
};

const modes = {
  operations: {
    title: '烽火地带',
    category: '探索 / 搜集 / 撤离',
    description: '进入战局，规划路线与装备，在信息沟通和战术配合中寻找撤离机会。',
    goal: '带出搜集到的物资并撤离',
    rhythm: '潜行、交火与路线判断交替',
    slot: '路线沟通 · 队内报点',
    plate: PLATES.operations,
    label: 'OPERATIONS',
    index: '01 / 02',
    caption: '烽火地带 · 城市战斗场景',
  },
  warfare: {
    title: '全面战场',
    category: '进攻 / 防守 / 协同',
    description: '在大规模战场中配合队友推进目标。步兵与载具共同参与，让每个位置的行动形成合力。',
    goal: '推进目标点并守住阵线',
    rhythm: '载具推进、阵地攻防与协同',
    slot: '载具协同 · 阵地支援',
    plate: PLATES.warfare,
    label: 'WARFARE',
    index: '02 / 02',
    caption: '全面战场 · 海岸与载具场景',
  },
};

const maps = {
  spaceport: {
    name: '航天基地',
    subtitle: 'SPACE CITY',
    code: 'SCN-01',
    plate: PLATES.spaceport,
    description: '从开阔区域到建筑内部，和小队一起观察地形、沟通路线。',
  },
  valley: {
    name: '长弓溪谷',
    subtitle: 'LAYALI GROVE',
    code: 'SCN-02',
    plate: PLATES.valley,
    description: '穿行山地与建筑之间，观察视野变化，和队友一起安排下一段路线。',
  },
};

const chapters = [
  { id: 'entry', index: 0, code: 'ENTRY', light: false, operator: true },
  { id: 'modes', index: 1, code: 'MODES', light: true, operator: false },
  { id: 'maps', index: 2, code: 'TERRAIN', light: false, operator: false },
  { id: 'squad', index: 3, code: 'SQUAD', light: true, operator: true },
  { id: 'deploy', index: 4, code: 'DEPLOY', light: false, operator: false },
];

const sections = chapters.map((chapter) => ({ ...chapter, el: $(chapter.id) }));
const squadWindow = document.querySelector('.squad-window');
const topbar = document.querySelector('.topbar');
const railProgress = $('rail-progress');
const hudChapter = $('hud-chapter');
const hudScroll = $('hud-scroll');
const hudViewport = $('hud-viewport');
const hudStage = $('hud-stage');
const hudClock = $('hud-clock');
const motionToggle = $('motion-toggle');
const stageStatus = $('stage-status');
const filmDialog = $('film-dialog');
const filmVideo = $('film-video');
const fallbackPlate = $('fallback-plate');
const fallbackOperator = $('fallback-operator');

let modeKey = 'operations';
let mapKey = 'spaceport';
let userPaused = reduceMedia.matches;
let activeIndex = -1;
let scanRun = -1; // 0..1 重新扫描动画
let scanAuto = 0;
let lastScanTime = 0;
let lastNow = 0;
let entryReveal = 0;
let squadReveal = 0;
let stageReadyAnnounced = false;

const stage = createDeltaStage($('delta-stage'), {
  onFallback(reason) {
    document.body.classList.add('no-stage');
    document.body.classList.remove('stage-booting');
    hudStage.textContent = 'STAGE FALLBACK';
    stageStatus.textContent = `WebGL 不可用，已使用静态画面降级（${reason}）`;
  },
});

if (!stage) {
  document.body.classList.add('no-stage');
  document.body.classList.remove('stage-booting');
  hudStage.textContent = 'STAGE FALLBACK';
} else {
  hudStage.textContent = 'STAGE WEBGL2';
  if (new URLSearchParams(location.search).has('debug')) window.__deltaStage = stage;
  stage.setOperator('./assets/operation-role.webp');
  stage.setPlate(PLATES.entry);
  stage.setScene({ reduce: userPaused ? 1 : 0, opAlpha: 0, dust: 0.9 });
  // 纹理加载完成前保留首帧静态底图；加载后由 stage 移除 stage-booting。
  window.setTimeout(() => {
    if (document.body.classList.contains('stage-booting')) {
      document.body.classList.remove('stage-booting');
    }
  }, 4000);
}

applyMotionState();
setMode(modeKey, { immediate: true });
setMap(mapKey, { immediate: true });
preloadPlates();

/* ───────── 交互：模式 / 地图 ───────── */
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
  if (activeIndex === 1 || immediate) applyPlate(data.plate, immediate);
  updateFallbackOperator(false);
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
  $('rescan').classList.remove('is-active');
  if (activeIndex === 2 || immediate) applyPlate(data.plate, immediate);
  startScan({ restart: true });
}

function applyPlate(url, immediate = false) {
  const target = url || PLATES.entry;
  if (fallbackPlate.getAttribute('src') !== target) fallbackPlate.src = target;
  if (!stage) return;
  if (immediate) {
    stage.setPlate(target);
    stage.render();
  } else {
    stage.setPlate(target);
  }
}

function updateFallbackOperator(show) {
  fallbackOperator.style.opacity = show ? '1' : '0';
}

/* ───────── 键盘可用的 tabs ───────── */
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
wireTabs('[data-mode]', (button, buttons) => {
  selectTab(buttons, button);
  setMode(button.dataset.mode);
});
wireTabs('[data-map]', (button, buttons) => {
  selectTab(buttons, button);
  setMap(button.dataset.map);
});

/* ───────── 扫描 ───────── */
function startScan({ restart = false } = {}) {
  scanRun = 0;
  lastScanTime = performance.now();
  if (restart && !userPaused) {
    const button = $('rescan');
    button.classList.add('is-active');
    window.clearTimeout(startScan.timer);
    startScan.timer = window.setTimeout(() => button.classList.remove('is-active'), 1800);
  }
  if (userPaused) scanRun = 1;
}
$('rescan').addEventListener('click', () => startScan({ restart: true }));

/* ───────── 影像弹层 ───────── */
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
  filmVideo.play().catch(() => {});
});
$('close-film').addEventListener('click', () => filmDialog.close());
filmDialog.addEventListener('click', (event) => {
  if (event.target !== filmDialog) return;
  const rect = filmDialog.getBoundingClientRect();
  const outside = event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom;
  if (outside) filmDialog.close();
});
filmDialog.addEventListener('close', () => {
  filmVideo.pause();
  $('open-film').focus();
});

/* ───────── 动态开关 / 减少动态 ───────── */
function applyMotionState() {
  document.body.classList.toggle('reduce-motion', userPaused);
  motionToggle.setAttribute('aria-pressed', String(userPaused));
  motionToggle.innerHTML = userPaused ? '恢复动态 <span aria-hidden="true">▷</span>' : '暂停动态 <span aria-hidden="true">Ⅱ</span>';
  const fallback = document.body.classList.contains('no-stage');
  if (stage) stage.setScene({ reduce: userPaused ? 1 : 0 });
  hudStage.textContent = fallback ? 'STAGE FALLBACK' : userPaused ? 'STAGE STATIC' : 'STAGE WEBGL2';
  updateFallbackOperator(activeIndex === 0 || activeIndex === 3);
}
motionToggle.addEventListener('click', () => {
  userPaused = !userPaused;
  applyMotionState();
});
reduceMedia.addEventListener('change', () => {
  userPaused = reduceMedia.matches;
  applyMotionState();
});

/* ───────── 预加载 ───────── */
function preloadPlates() {
  const urls = new Set([...Object.values(PLATES), './assets/operation-role.webp']);
  let index = 0;
  const next = () => {
    if (index >= urls.size) return;
    const url = [...urls][index++];
    const img = new Image();
    img.decoding = 'async';
    img.src = url;
    img.onload = img.onerror = () => window.setTimeout(next, 120);
  };
  if ('requestIdleCallback' in window) requestIdleCallback(next, { timeout: 2500 });
  else window.setTimeout(next, 900);
}

/* ───────── 时钟 / HUD ───────── */
function updateClock() {
  const now = new Date();
  hudClock.textContent = now.toLocaleTimeString('zh-CN', { hour12: false });
}
updateClock();
window.setInterval(updateClock, 1000);

function updateViewport() {
  hudViewport.textContent = `VIEWPORT ${window.innerWidth} × ${window.innerHeight}`;
}
updateViewport();

/* ───────── 主循环 ───────── */
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
  const sectionTop = section.el.offsetTop;
  const sectionHeight = Math.max(1, section.el.offsetHeight);
  const chapterProgress = clamp((scroll + vh * 0.5 - sectionTop) / sectionHeight, 0, 1);
  return { vh, scroll, global, index, chapterProgress, section };
}

function buildScene({ vh, global, index, chapterProgress }) {
  const scene = { progress: global, tint: [1, 1, 1], reveal: 0, opAlpha: 0, dust: 0.4, scanActive: 0, scanPos: 0, zoom: 1.03, panX: 0, panY: 0, vignette: 0.74, grain: 0.045, reduce: userPaused ? 1 : 0 };
  if (index === 0) {
    scene.zoom = lerp(1.02, 1.11, chapterProgress);
    scene.panY = lerp(0.0, 0.024, chapterProgress);
    scene.dust = 0.95;
    scene.opAlpha = 1;
    scene.reveal = entryReveal;
    scene.tint = [1.0, 0.995, 0.97];
  } else if (index === 1) {
    scene.zoom = 1.04 + chapterProgress * 0.035;
    scene.panY = lerp(0.0, 0.015, chapterProgress);
    scene.dust = 0.42;
    scene.tint = [1.0, 1.0, 0.985];
  } else if (index === 2) {
    scene.zoom = lerp(1.05, 1.14, chapterProgress);
    scene.panX = lerp(-0.02, 0.02, chapterProgress);
    scene.panY = lerp(0.012, -0.012, chapterProgress);
    scene.dust = 0.3;
    scene.scanActive = 1;
    scene.scanPos = scanRun >= 0 ? scanRun : scanAuto;
    scene.tint = [0.94, 1.0, 0.98];
    scene.vignette = 0.8;
  } else if (index === 3) {
    scene.zoom = 1.02;
    scene.dust = 0.34;
    scene.opAlpha = 1;
    scene.reveal = squadReveal;
    scene.tint = [1.0, 0.995, 0.965];
    scene.vignette = 0.66;
  } else {
    scene.zoom = lerp(1.03, 1.12, chapterProgress);
    scene.panY = lerp(0, 0.02, chapterProgress);
    scene.dust = 0.75;
    scene.tint = [1.0, 0.985, 0.95];
    scene.vignette = 0.82;
  }
  return scene;
}

function operatorFrame(index) {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const mobile = vw < 860;
  if (index === 0) {
    if (mobile) {
      return { box: { x: 0, y: vh * 0.4, w: vw, h: vh * 0.68 }, fit: 'contain', anchor: 'center' };
    }
    return { box: { x: vw * 0.36, y: -vh * 0.09, w: vw * 0.74, h: vh * 1.16 }, fit: 'cover', anchor: 'rb' };
  }
  if (index === 3 && squadWindow) {
    const rect = squadWindow.getBoundingClientRect();
    const pad = Math.max(8, rect.width * 0.03);
    if (mobile) {
      return { box: { x: rect.left, y: rect.top - rect.height * 0.12, w: rect.width, h: rect.height * 1.16 }, fit: 'contain', anchor: 'center' };
    }
    return { box: { x: rect.left + pad, y: rect.top - rect.height * 0.1, w: rect.width - pad * 2, h: rect.height * 1.12 }, fit: 'contain', anchor: 'center' };
  }
  return null;
}

function updateDom(metrics) {
  const { index, section, global, scroll, vh } = metrics;
  if (index !== activeIndex) {
    activeIndex = index;
    document.body.classList.toggle('is-light', section.light);
    document.querySelectorAll('[data-nav]').forEach((link) => {
      if (link.dataset.nav === section.id) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    });
    document.querySelectorAll('[data-rail]').forEach((link) => {
      if (link.dataset.rail === section.id) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    });
    const plate = index === 0 ? PLATES.entry
      : index === 1 ? modes[modeKey].plate
      : index === 2 ? maps[mapKey].plate
      : index === 3 ? PLATES.squad
      : PLATES.deploy;
    applyPlate(plate);
    updateFallbackOperator(Boolean(section.operator));
    hudChapter.textContent = `CH.${String(index).padStart(2, '0')} / ${section.code}`;
    if (index === 2) startScan();
    if (index === 0) entryReveal = Math.max(entryReveal, 0.05);
    stageStatus.textContent = `当前章节：${section.code}`;
  }
  topbar.classList.toggle('is-scrolled', scroll > 40);
  railProgress.style.height = `${(global * 100).toFixed(1)}%`;
  hudScroll.textContent = `SCROLL ${String(Math.round(global * 100)).padStart(3, '0')}%`;

  const windowVisible = squadWindow && squadWindow.getBoundingClientRect().top < vh * 0.9;
  if (index === 3 && windowVisible) {
    const rect = squadWindow.getBoundingClientRect();
    squadReveal = clamp((vh * 0.92 - rect.top) / (vh * 0.5), 0, 1);
    $('squad-link-state').textContent = squadReveal > 0.6 ? 'LINKED 04 / 04' : 'LINKING…';
  }
  if (index === 2) {
    const scanLabel = scanRun >= 0 && scanRun < 1 ? 'SCANNING' : 'READY';
    $('rescan').classList.toggle('is-active', scanLabel === 'SCANNING');
  }
}

function frame(now) {
  requestAnimationFrame(frame);
  const dt = lastNow ? Math.min(0.05, (now - lastNow) / 1000) : 0.016;
  lastNow = now;
  if (document.hidden) return;

  if (!userPaused) {
    entryReveal = Math.min(1, entryReveal + dt * 0.55);
  } else if (entryReveal < 1) {
    entryReveal = 1;
  }

  if (scanRun >= 0) {
    scanRun += dt * 0.55;
    if (scanRun >= 1) { scanRun = -1; }
  }
  if (scanRun < 0) scanAuto = (Math.sin(now * 0.00016) * 0.5 + 0.5) * 0.9 + 0.05;

  const metrics = measure();
  updateDom(metrics);
  const scene = buildScene(metrics);
  const frameInfo = operatorFrame(metrics.index);
  if (frameInfo) {
    scene.opBox = frameInfo.box;
    scene.opBoxFit = frameInfo.fit;
    scene.opBoxAnchor = frameInfo.anchor;
  }
  if (stage) {
    stage.setScene(scene);
    stage.render();
  }
}

window.addEventListener('resize', () => {
  updateViewport();
  if (stage) stage.resize();
});
window.addEventListener('scroll', () => { /* 主循环已处理 */ }, { passive: true });

requestAnimationFrame(frame);
