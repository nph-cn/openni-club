import {
  labels, platformTabs, stateGroup, matchScreens, groupFlows, flowLabel, parseLocation, gallerySearch,
  browseSequence, galleryCounts, galleryStats, platformSummary, appPreviewUrl, screenPreview, sourceHref
} from './gallery-model.js';

const $ = selector => document.querySelector(selector);
const names = labels;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
let screens = [], loadError = false, currentId = '';
let detailScope = 'results';
let {platform, role, flow, state, query, view, screenId: initialScreen} = parseLocation(location.search);
let favoriteOnly = false;
let favorites;
try {
  const stored = JSON.parse(localStorage.getItem('openni:favorites') || '[]');
  favorites = new Set(Array.isArray(stored) ? stored.filter(id => typeof id === 'string') : []);
} catch {
  favorites = new Set();
}
const dialog = $('#detail');
const node = (tag, text, className) => { const item = document.createElement(tag); if (text !== undefined) item.textContent = text; if (className) item.className = className; return item; };
const filters = () => ({platform, role, flow, state, query, view, favoriteOnly});
const matched = () => matchScreens(screens, filters(), favorites);
const detailList = () => browseSequence(matched(), currentId, detailScope);
for (const link of document.querySelectorAll('a[href^="/demo/"]')) link.href = appPreviewUrl(link.getAttribute('href'));

// 详情内切换浏览范围：当前流程 / 当前筛选结果。
const browseMode = node('div', undefined, 'detail-browse-mode');
browseMode.setAttribute('role', 'group');
browseMode.setAttribute('aria-label', '浏览范围');
for (const [scope, label] of [['flow', '当前流程'], ['results', '筛选结果']]) {
  const button = node('button', label);
  button.type = 'button';
  button.dataset.browseScope = scope;
  button.onclick = () => { detailScope = scope; const current = screens.find(screen => screen.id === currentId); if (current) show(current); };
  browseMode.append(button);
}
$('#detail-sequence').before(browseMode);

function locationFor(screenId = '') { return `${location.pathname}${gallerySearch(filters(), screenId)}${location.hash}`; }
function writeLocation(screenId = '') { history.replaceState(null, '', locationFor(screenId)); }
function buttons(key, value) {
  document.querySelectorAll(`button[data-${key}]`).forEach(button => {
    const selected = button.dataset[key] === value;
    button.classList.toggle('selected', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
}
function syncControls() {
  $('#state-filter').value = state;
  if (document.activeElement !== $('#search')) $('#search').value = query;
  buttons('platform', platform);
  buttons('view', view);
  $('#favorites').classList.toggle('selected', favoriteOnly);
  $('#favorites').setAttribute('aria-pressed', String(favoriteOnly));
  const note = $('#platform-note');
  if (note) {
    note.textContent = platform === 'flutter'
      ? 'iOS 与 Android 共用同一套 Flutter 界面，截图在 iPhone 预览壳中采集，另含 Android 主题变体。'
      : platform === 'mini'
        ? '微信小程序为原生实现，截图来自微信开发者工具的运行画面。'
        : '运营后台为桌面端页面，截图为 1266×712 浏览器运行画面。';
  }
}
function screenImage(screen) {
  const img = node('img');
  img.alt = `${names.platform[screen.platform] || ''} · ${screen.title}`;
  img.width = screen.width || 390;
  img.height = screen.height || 844;
  img.loading = 'lazy';
  img.decoding = 'async';
  img.dataset.loaded = 'false';
  img.onload = () => img.dataset.loaded = 'true';
  img.onerror = () => { img.dataset.loaded = 'error'; img.alt = `${screen.title} · 图片未加载`; };
  img.src = screen.image;
  return img;
}

/* ------------------------------------------------------------------ *
 * 首页叙事区：真实统计、三个客户端概览、俱乐部能力清单（全部来自构建数据）
 * ------------------------------------------------------------------ */
let statsAnimated = false, statsInView = false, screensReady = false, overviewBuilt = false, statsFallback = 0, capPlatform = '';
const statIds = {total: 'stat-screens', flows: 'stat-flows', clients: 'stat-clients', interactions: 'stat-interactions'};

function setStatTargets(stats) {
  const values = {total: stats.total, flows: stats.flows, clients: stats.clients, interactions: stats.interactions};
  for (const [key, id] of Object.entries(statIds)) {
    const el = document.getElementById(id);
    if (el) el.dataset.target = String(values[key]);
  }
}
function paintStats() {
  document.querySelectorAll('.stat-value[data-target]').forEach(el => { el.textContent = el.dataset.target; });
}
function animateStats() {
  if (statsAnimated) { paintStats(); return; }
  const elements = [...document.querySelectorAll('.stat-value[data-target]')];
  if (!elements.length) return;
  statsAnimated = true;
  if (reduceMotion.matches) { paintStats(); return; }
  const started = performance.now(), duration = 1100;
  const tick = now => {
    const progress = Math.min(1, (now - started) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    for (const el of elements) el.textContent = String(Math.round(Number(el.dataset.target || 0) * eased));
    if (progress < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function representativeScreens(platformKey, limit) {
  const pool = screens.filter(screen => screen.platform === platformKey);
  const byFlow = new Map();
  for (const screen of pool) {
    if (screen.stateGroup === 'ready' && !byFlow.has(screen.flow)) byFlow.set(screen.flow, screen);
  }
  const picks = [...byFlow.values()].slice(0, limit);
  for (const screen of pool) {
    if (picks.length >= limit) break;
    if (!picks.includes(screen)) picks.push(screen);
  }
  return picks;
}
function scrollToGallery() {
  document.querySelector('#gallery-region')?.scrollIntoView({behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'start'});
}
const clientMeta = {
  flutter: {title: 'iOS / Android', badge: 'APP', note: 'iPhone 预览壳 · 2×', link: '只看 App 界面'},
  mini: {title: '微信小程序', badge: 'MINI', note: '微信开发者工具', link: '只看小程序界面'},
  admin: {title: '运营后台', badge: 'OPS', note: '1266×712 · 浏览器', link: '只看后台界面'}
};
function buildClients(stats) {
  const grid = $('#client-cards');
  if (!grid) return;
  grid.replaceChildren();
  let index = 0;
  for (const tab of platformTabs) {
    const count = stats.platforms[tab.key] || 0;
    if (!count) continue;
    const meta = clientMeta[tab.key] || {title: tab.label, badge: 'CLIENT', note: '', link: '只看本端'};
    const flows = new Set(screens.filter(screen => screen.platform === tab.key).map(screen => screen.flow)).size;
    const card = node('article', undefined, 'client-card');
    card.dataset.reveal = '';
    card.style.setProperty('--reveal-delay', `${index * 80}ms`);
    const head = node('div', undefined, 'client-card-head');
    head.append(node('span', `${String(index + 1).padStart(2, '0')} / ${meta.badge}`), node('span', `${flows} 条流程`));
    const title = node('h3');
    title.append(node('span', meta.title), node('em', tab.key === 'flutter' ? 'FLUTTER' : tab.key === 'mini' ? 'NATIVE' : 'DESKTOP'));
    const countRow = node('div', undefined, 'client-count');
    countRow.append(node('strong', String(count)), node('span', '张真实截图'));
    const desc = node('p', tab.hint || tab.label, 'client-desc');
    const shots = node('div', undefined, 'client-shots' + (tab.key === 'admin' ? ' is-landscape' : ''));
    for (const screen of representativeScreens(tab.key, tab.key === 'admin' ? 2 : 3)) {
      const img = screenImage(screen);
      img.alt = `${meta.title} · ${screen.title}`;
      img.loading = 'lazy';
      shots.append(img);
    }
    const foot = node('div', undefined, 'client-foot');
    foot.append(node('span', meta.note));
    const action = node('button', `${meta.link} ${count} 张 `);
    action.type = 'button';
    action.className = 'client-link';
    action.setAttribute('aria-label', `在界面图库中只看${meta.title}，共 ${count} 张截图`);
    action.append(node('span', '→'));
    action.onclick = () => { platform = tab.key; flow = 'all'; role = 'all'; state = 'all'; query = ''; favoriteOnly = false; view = 'flows'; render(); scrollToGallery(); };
    foot.append(action);
    card.append(head, title, countRow, desc, shots, foot);
    grid.append(card);
    index += 1;
  }
}
function filterToFlow(group) {
  if (!screens.some(screen => screen.platform === platform && screen.flow === group.key)) {
    const alt = ['flutter', 'mini', 'admin'].find(key => screens.some(screen => screen.platform === key && screen.flow === group.key));
    if (alt) platform = alt;
  }
  flow = group.key; role = 'all'; state = 'all'; query = ''; favoriteOnly = false; view = 'flows';
  render();
  scrollToGallery();
}
function filterToPlatform(key) {
  platform = key; flow = 'all'; role = 'all'; state = 'all'; query = ''; favoriteOnly = false; view = 'flows';
  render();
  scrollToGallery();
}
function capRow(reveal = true) {
  const li = node('li', undefined, 'cap-row');
  if (reveal) li.dataset.reveal = '';
  return li;
}
function buildCapabilities(stats, {reveal = true} = {}) {
  const list = $('#capability-list');
  if (!list) return;
  list.replaceChildren();
  const platformScreens = screens.filter(screen => screen.platform === platform);
  const groups = groupFlows(platformScreens);
  const scope = $('#cap-scope');
  if (scope) scope.textContent = `${names.platform[platform] || '全部客户端'} · ${groups.length} 条业务流程`;
  let index = 0;
  for (const group of groups) {
    const li = capRow(reveal);
    const button = node('button');
    button.type = 'button';
    button.className = 'cap-button';
    button.setAttribute('aria-label', `按「${group.name}」筛选图库，共 ${group.screens.length} 个界面`);
    button.append(node('span', String(index + 1).padStart(2, '0'), 'cap-num'));
    const body = node('span', undefined, 'cap-body');
    body.append(node('span', group.name, 'cap-title'), node('span', group.intro || '', 'cap-desc'));
    const count = node('span', undefined, 'cap-count');
    count.append(node('b', String(group.screens.length)), node('span', '个界面'));
    button.append(body, count, node('span', '→', 'cap-arrow'));
    button.onclick = () => filterToFlow(group);
    li.append(button);
    list.append(li);
    index += 1;
  }
  const adminCount = stats.platforms.admin || 0;
  if (adminCount && platform !== 'admin') {
    const li = capRow(reveal);
    const button = node('button');
    button.type = 'button';
    button.className = 'cap-button';
    button.setAttribute('aria-label', `只看运营后台界面，共 ${adminCount} 张`);
    button.append(node('span', String(index + 1).padStart(2, '0'), 'cap-num'));
    const body = node('span', undefined, 'cap-body');
    body.append(node('span', '运营后台', 'cap-title'), node('span', '派单工作台、订单、服务目录、结算与公告，桌面端运营工作台。', 'cap-desc'));
    const count = node('span', undefined, 'cap-count');
    count.append(node('b', String(adminCount)), node('span', '张界面'));
    button.append(body, count, node('span', '→', 'cap-arrow'));
    button.onclick = () => filterToPlatform('admin');
    li.append(button);
    list.append(li);
    index += 1;
  }
  const li = capRow(reveal);
  li.classList.add('cap-row-static');
  const link = node('a');
  link.className = 'cap-button';
  link.href = '/guide/';
  link.setAttribute('aria-label', '打开文档：开源许可、品牌配置与部署说明');
  link.append(node('span', String(index + 1).padStart(2, '0'), 'cap-num'));
  const body = node('span', undefined, 'cap-body');
  body.append(node('span', '开源与白标', 'cap-title'), node('span', 'MIT License；单配置文件生成三端品牌；文档与脚本随仓库提供。', 'cap-desc'));
  const count = node('span', undefined, 'cap-count');
  count.append(node('b', 'MIT'), node('span', '许可'));
  link.append(body, count, node('span', '↗', 'cap-arrow'));
  li.append(link);
  list.append(li);
}
function buildOverview(stats) {
  buildClients(stats);
  buildCapabilities(stats);
}

function updateHeroStats() {
  const stats = galleryStats(screens);
  screensReady = true;
  setStatTargets(stats);
  // 数据到达即开始计分（页面上方不可见时动画也已完成，避免出现占位符）。
  animateStats();
  if (!statsFallback) statsFallback = setTimeout(() => {
    if (!statsAnimated) paintStats();
  }, 2400);
  document.querySelectorAll('.js-screen-total').forEach(el => { el.textContent = String(stats.total); });
  $('#platform-summary').textContent = `${platformSummary(stats).join(' · ')} · 共 ${stats.total} 张运行截图`;
  if (!overviewBuilt) { buildOverview(stats); overviewBuilt = true; capPlatform = platform; }
  else if (capPlatform !== platform) { buildCapabilities(stats, {reveal: false}); capPlatform = platform; }
  observeReveals();
}

function render({sync = true} = {}) {
  const shown = matched(), counts = galleryCounts(screens, shown, favorites);
  syncControls();
  renderSidebar();
  if (screens.length) updateHeroStats();
  $('#result-count').textContent = `本端 ${counts.platforms[platform] || 0} / 全站 ${counts.total} 张 · 当前 ${counts.shown} 张`;
  $('#favorites span').textContent = counts.favorites;
  for (const button of document.querySelectorAll('[data-platform]')) {
    const count = counts.platforms[button.dataset.platform] || 0;
    button.hidden = !count;
    const badge = button.querySelector('span');
    if (badge) badge.textContent = count;
  }
  const heading = favoriteOnly ? '我的收藏' : view === 'flows' ? '界面图库' : '全部界面';
  $('#view-heading .heading-text').textContent = heading;
  $('#total-count').textContent = counts.shown;
  const platformFlowCount = new Set(screens.filter(screen => screen.platform === platform).map(screen => screen.flow)).size;
  $('#hero-screen-count').textContent = `${names.platform[platform] || '全部客户端'} · ${platformFlowCount} 条业务流程`;
  const active = [
    role !== 'all' ? names.role[role] : null,
    flow !== 'all' ? flowLabel(flow) : null,
    state !== 'all' ? names.state[state] : null,
    query ? `“${query}”` : null,
    favoriteOnly ? '已收藏' : null
  ].filter(Boolean);
  $('#active-filters').hidden = !active.length;
  $('#filter-summary').textContent = active.join(' / ');
  $('#gallery').replaceChildren();
  if (!shown.length) {
    $('#empty').hidden = false;
    $('#empty h3').textContent = favoriteOnly ? '还没有收藏界面' : '没有找到这个界面';
    $('#empty p').textContent = favoriteOnly ? '在界面卡片右下角点收藏，随时回到这里。' : '试试其他关键词或筛选条件。';
    $('#reset-empty').textContent = favoriteOnly ? '查看全部界面' : '清除筛选';
  } else {
    $('#empty').hidden = true;
    if (view === 'flows') renderFlows(shown); else renderCards($('#gallery'), shown);
  }
  if (sync) writeLocation();
}
function renderCards(container, items) {
  const grid = node('div', undefined, 'screen-grid' + (platform === 'admin' ? ' grid-landscape' : ''));
  for (const screen of items) grid.append(screenCard(screen, {showFlow: view === 'screens'}));
  container.append(grid);
}
function renderFlows(shown) {
  for (const [index, group] of groupFlows(shown).entries()) {
    const section = node('section', undefined, 'flow-block');
    section.dataset.flow = group.key;
    const head = node('header', undefined, 'flow-block-head');
    const title = node('div', undefined, 'flow-block-title');
    title.append(node('span', String(index + 1).padStart(2, '0'), 'flow-number'), node('h3', group.name), node('span', `${group.screens.length} 个界面`, 'flow-count'));
    const start = node('button');
    start.type = 'button';
    start.className = 'flow-play';
    start.append(node('span', '顺序浏览'), node('span', '→'));
    start.setAttribute('aria-label', `按顺序浏览${group.name}，共 ${group.screens.length} 屏`);
    start.onclick = () => show(group.screens[0], {scope: 'flow'});
    head.append(title, start);
    section.append(head);
    if (group.intro) section.append(node('p', group.intro, 'flow-intro'));
    const grid = node('div', undefined, 'screen-grid' + (platform === 'admin' ? ' grid-landscape' : ''));
    for (const screen of group.screens) grid.append(screenCard(screen, {showFlow: false}));
    section.append(grid);
    $('#gallery').append(section);
  }
}
function screenCard(screen, {showFlow = false} = {}) {
  const article = node('article', undefined, 'screen-card');
  const open = node('button', undefined, 'screen-open');
  open.type = 'button';
  open.setAttribute('aria-label', `查看「${screen.title}」大图、说明与原图下载`);
  const shot = node('span', undefined, 'screen-shot');
  shot.append(screenImage(screen));
  open.append(shot, node('span', names.capture[screen.captureKind] || '查看大图', 'screen-open-hint'));
  open.onclick = () => show(screen, {scope: view === 'flows' ? 'flow' : 'results'});
  const caption = node('div', undefined, 'screen-caption');
  const text = node('div', undefined, 'screen-caption-text');
  text.append(node('p', screen.title, 'screen-name'));
  const tags = node('p', undefined, 'screen-tags');
  const group = stateGroup(screen);
  // 正常状态不占标签位，异常/加载/空状态才值得在卡片上强调。
  if (group !== 'ready') tags.append(node('span', names.state[group], `state-pill state-${group}`));
  if (screen.captureKind === 'interaction') tags.append(node('span', '交互状态', 'kind-pill'));
  if (screen.capturePlatform === 'android') tags.append(node('span', 'Android', 'kind-pill'));
  if (screen.role === 'member') tags.append(node('span', '成员端', 'role-pill'));
  if (showFlow && screen.flow) tags.append(node('span', flowLabel(screen.flow), 'flow-pill'));
  text.append(tags);
  const saved = favorites.has(screen.id);
  const bookmark = node('button', undefined, 'bookmark' + (saved ? ' saved' : ''));
  bookmark.type = 'button';
  bookmark.setAttribute('aria-label', `${saved ? '取消收藏' : '收藏'}${screen.title}`);
  bookmark.setAttribute('aria-pressed', String(saved));
  bookmark.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>';
  bookmark.onclick = () => toggleFavorite(screen, bookmark);
  caption.append(text, bookmark);
  article.append(open, caption);
  return article;
}
function toggleFavorite(screen, button) {
  const saved = favorites.has(screen.id);
  if (saved) favorites.delete(screen.id); else favorites.add(screen.id);
  try { localStorage.setItem('openni:favorites', JSON.stringify([...favorites])); } catch { /* 隐私模式忽略。 */ }
  const nowSaved = !saved;
  button.classList.toggle('saved', nowSaved);
  button.setAttribute('aria-pressed', String(nowSaved));
  button.setAttribute('aria-label', `${nowSaved ? '取消收藏' : '收藏'}${screen.title}`);
  $('#favorites span').textContent = new Set(screens.filter(item => favorites.has(item.id)).map(item => item.id)).size;
  if (favoriteOnly) render();
}
function show(screen, {scope = detailScope} = {}) {
  detailScope = scope;
  const sequenceHadFocus = $('#detail-sequence').contains(document.activeElement);
  const sequenceScroll = $('#detail-sequence').scrollLeft;
  currentId = screen.id;
  const group = stateGroup(screen);
  $('#detail-title').textContent = screen.title;
  $('#detail-platform').textContent = names.platform[screen.platform] || '';
  const stateBadge = $('#detail-state');
  stateBadge.hidden = group === 'ready';
  stateBadge.textContent = names.state[group];
  $('#detail-state-text').textContent = names.state[group];
  $('#detail-flow').textContent = names.flow[screen.flow] || '其他流程';
  $('#detail-description').textContent = screen.description || '该界面在清单中尚未登记说明。';
  const capture = $('#detail-capture');
  capture.textContent = screen.device === 'iPhone preview'
    ? `iPhone 预览壳 · ${screen.captureKind === 'interaction' ? '交互状态截图' : '完整页面截图'} · 非真机拍摄`
    : screen.capture || '';
  capture.title = screen.capture || '';
  capture.hidden = !capture.textContent;
  const source = screen.source;
  const sourceTarget = $('#detail-source');
  if (source) sourceTarget.replaceChildren(Object.assign(node('a', source + ' ↗'), {href: sourceHref(screen), target: '_blank', rel: 'noreferrer'}));
  else sourceTarget.replaceChildren(node('span', '未登记源码路径'));
  const img = $('#detail-img');
  img.hidden = false;
  $('#detail-image-error').hidden = true;
  img.alt = screen.title;
  img.width = screen.width || 390;
  img.height = screen.height || 844;
  img.onload = () => { img.hidden = false; $('#detail-image-error').hidden = true; };
  img.onerror = () => { img.hidden = true; $('#detail-image-error').hidden = false; };
  img.src = screen.image;
  const preview = screenPreview(screen);
  $('#detail-demo').href = preview.href;
  $('#detail-demo').textContent = preview.label;
  const download = $('#detail-download');
  download.href = screen.image;
  download.setAttribute('download', String(screen.image).split('/').pop());
  dialog.classList.toggle('wide-detail', screen.platform === 'admin');
  dialog.classList.remove('zoomed');
  dialog.classList.remove('is-fullscreen');
  $('#toggle-zoom').textContent = '放大';
  $('#toggle-zoom').setAttribute('aria-label', '按原图放大');
  $('#toggle-zoom').setAttribute('aria-pressed', 'false');
  $('#toggle-fullscreen').textContent = '全屏';
  $('#toggle-fullscreen').setAttribute('aria-label', '全屏查看');
  $('#toggle-fullscreen').setAttribute('aria-pressed', 'false');
  $('#copy-link').textContent = '复制链接';
  const list = detailList(), index = list.findIndex(item => item.id === screen.id);
  $('#detail-window').textContent = `${detailScope === 'flow' ? '当前流程' : '筛选结果'} · ${list.length} 张`;
  $('#detail-position').textContent = `${detailScope === 'flow' ? '本流程' : '筛选结果'} ${index + 1} / ${list.length}`;
  $('#detail-index').textContent = String(index + 1).padStart(2, '0');
  const stageIndex = $('#detail-stage-index');
  if (stageIndex) stageIndex.textContent = `${String(index + 1).padStart(2, '0')} / ${String(list.length).padStart(2, '0')} — ${names.flow[screen.flow] || ''}`;
  $('#previous-screen').disabled = index <= 0;
  $('#next-screen').disabled = index >= list.length - 1;
  browseMode.querySelectorAll('button').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.browseScope === detailScope)));
  const sequence = $('#detail-sequence');
  sequence.replaceChildren();
  sequence.setAttribute('aria-label', detailScope === 'flow' ? '当前流程的界面' : '当前筛选结果的界面');
  for (const [step, related] of list.entries()) {
    const button = node('button');
    button.type = 'button';
    button.dataset.screen = related.id;
    button.setAttribute('aria-label', `第 ${step + 1} 张：${related.title}`);
    button.setAttribute('aria-current', String(related.id === screen.id));
    button.title = related.title;
    const thumb = screenImage(related);
    thumb.alt = '';
    button.append(thumb, node('span', `${String(step + 1).padStart(2, '0')} ${related.title}`));
    button.onclick = () => show(related);
    sequence.append(button);
  }
  if (!dialog.open) dialog.showModal();
  $('.detail-body').scrollTop = 0;
  $('.detail-stage').scrollTop = 0;
  writeLocation(screen.id);
  sequence.scrollLeft = sequenceScroll;
  const current = sequence.querySelector('[aria-current=true]');
  if (sequenceHadFocus) current?.focus({preventScroll: true});
  if (current) {
    const left = current.offsetLeft - sequence.offsetLeft, right = left + current.offsetWidth;
    if (left < sequence.scrollLeft) sequence.scrollLeft = left;
    else if (right > sequence.scrollLeft + sequence.clientWidth) sequence.scrollLeft = right - sequence.clientWidth;
  }
}
function renderSidebar() {
  const sidebar = $('#flow-sidebar'), scroll = sidebar.scrollLeft;
  const focused = sidebar.contains(document.activeElement) ? document.activeElement.dataset.flow : null;
  sidebar.replaceChildren();
  const subset = matchScreens(screens, {...filters(), flow: 'all'}, favorites);
  const entries = [['all', '全部界面', subset.length], ...groupFlows(subset).map(group => [group.key, group.name, group.screens.length])];
  for (const [key, title, count] of entries) {
    const button = node('button', title);
    button.type = 'button';
    button.dataset.flow = key;
    button.setAttribute('aria-pressed', String(flow === key));
    button.append(node('span', String(count)));
    button.onclick = () => { flow = flow === key ? 'all' : key; render(); };
    sidebar.append(button);
  }
  sidebar.scrollLeft = scroll;
  if (focused) {
    const current = Array.from(sidebar.querySelectorAll('button')).find(button => button.dataset.flow === focused);
    current?.focus({preventScroll: true});
    current?.scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'instant'});
  }
}
function next(offset) {
  const list = detailList(), index = list.findIndex(item => item.id === currentId);
  if (list[index + offset]) show(list[index + offset]);
}
$('#close-detail').onclick=()=>dialog.close();
dialog.addEventListener('close', () => { currentId = ''; writeLocation(); });
$('#previous-screen').onclick = () => next(-1);
$('#next-screen').onclick = () => next(1);
function toggleFullscreen() {
  const active = dialog.classList.toggle('is-fullscreen');
  $('#toggle-fullscreen').textContent = active ? '退出全屏' : '全屏';
  $('#toggle-fullscreen').setAttribute('aria-label', active ? '退出全屏' : '全屏查看');
  $('#toggle-fullscreen').setAttribute('aria-pressed', String(active));
}
dialog.addEventListener('keydown', event => {
  if (event.altKey || event.ctrlKey || event.metaKey || /INPUT|TEXTAREA|SELECT/.test(event.target.tagName)) return;
  if (event.key === 'ArrowLeft') { event.preventDefault(); next(-1); }
  if (event.key === 'ArrowRight') { event.preventDefault(); next(1); }
  if (event.key === 'f' || event.key === 'F') { event.preventDefault(); toggleFullscreen(); }
  if (event.key === 'Escape' && dialog.classList.contains('is-fullscreen')) { event.preventDefault(); toggleFullscreen(); }
});
dialog.addEventListener('click', event => {
  if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
  }
});
$('#toggle-zoom').onclick = () => {
  const zoomed = dialog.classList.toggle('zoomed');
  $('#toggle-zoom').textContent = zoomed ? '适合屏幕' : '放大';
  $('#toggle-zoom').setAttribute('aria-label', zoomed ? '缩小至适合屏幕' : '按原图放大');
  $('#toggle-zoom').setAttribute('aria-pressed', String(zoomed));
};
$('#toggle-fullscreen').onclick = toggleFullscreen;
$('#copy-link').onclick = async () => {
  try {
    const url = new URL(location.href);
    url.search = gallerySearch({...filters(), view: 'screens'}, currentId);
    url.hash = 'gallery-region';
    await navigator.clipboard.writeText(url.href);
    $('#copy-link').textContent = '已复制';
  } catch {
    $('#copy-link').textContent = '请复制地址栏';
  }
};
$('#retry-image').onclick = () => { const screen = screens.find(item => item.id === currentId); if (screen) show(screen); };
document.querySelectorAll('[data-platform]').forEach(button => {
  button.onclick = () => {
    platform = button.dataset.platform;
    if (role !== 'all' && !screens.some(screen => screen.platform === platform && screen.role === role)) role = 'all';
    if (flow !== 'all' && !screens.some(screen => screen.platform === platform && screen.flow === flow)) flow = 'all';
    render();
  };
});
$('#state-filter').onchange = event => { state = event.target.value; render(); };
document.querySelectorAll('[data-view]').forEach(button => {
  button.onclick = () => { view = button.dataset.view; favoriteOnly = false; render(); };
});
$('#favorites').onclick = () => { favoriteOnly = !favoriteOnly; render(); };
$('#search').oninput = event => { query = event.target.value.trim(); render(); };
$('#search').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); query = ''; $('#search').value = ''; render(); }
});
function reset() { role = 'all'; flow = 'all'; state = 'all'; query = ''; favoriteOnly = false; render(); }
$('#reset').onclick = reset;
$('#reset-empty').onclick = () => loadError ? loadScreens() : reset();
document.addEventListener('keydown', event => {
  if (event.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) && !dialog.open) { event.preventDefault(); $('#search').focus(); }
});

async function loadScreens() {
  loadError = false;
  $('#gallery-loading').hidden = false;
  $('#empty').hidden = true;
  $('#gallery').setAttribute('aria-busy', 'true');
  try {
    const response = await fetch('/screens.json');
    if (!response.ok) throw Error('index');
    const data = await response.json();
    if (!Array.isArray(data)) throw Error('index');
    screens = data;
    for (const button of document.querySelectorAll('[data-platform]')) {
      const count = screens.filter(screen => screen.platform === button.dataset.platform).length;
      button.hidden = !count;
      const badge = button.querySelector('span');
      if (badge) badge.textContent = count;
    }
    const requested = screens.find(screen => screen.id === initialScreen);
    if (requested) {
      platform = requested.platform;
      if (!matched().includes(requested)) { role = 'all'; flow = 'all'; state = 'all'; query = ''; favoriteOnly = false; }
    }
    render();
    if (requested) show(requested, {scope: view === 'flows' ? 'flow' : 'results'});
    initialScreen = '';
  } catch {
    loadError = true;
    $('#empty').hidden = false;
    $('#empty h3').textContent = '界面目录未能加载';
    $('#empty p').textContent = '请检查构建产物 /screens.json 是否存在。';
    $('#reset-empty').textContent = '重新加载';
  } finally {
    $('#gallery-loading').hidden = true;
    $('#gallery').setAttribute('aria-busy', 'false');
  }
}

// 首页角色预览只使用清单中存在的运行截图，点击后进入相应流程。
function openStageScreen(screen) {
  platform = screen.platform;
  role = 'all';
  flow = 'all';
  state = 'all';
  query = '';
  favoriteOnly = false;
  render({sync: false});
  show(screen, {scope: 'flow'});
}
const stageRoles={
  customer: {screenId: 'home', extraIds: ['services', 'player', 'booking'], alt: '用户端首页运行截图', caption: '用户端 · 首页、服务与预约入口', browse: '查看用户端界面', demo: '/demo/?device=iphone'},
  member: {screenId: 'member', extraIds: ['member_orders', 'availability', 'earnings'], alt: '成员端工作台运行截图', caption: '成员端 · 接单、可约时段与收入', browse: '查看成员端界面', demo: '/demo/?screen=member&device=iphone'},
  operator: {screenId: 'admin-dispatch', extraIds: ['admin-orders', 'admin-services'], alt: '运营后台派单工作台运行截图', caption: '运营后台 · 派单、订单与服务目录', browse: '查看后台界面', demo: '/admin/'}
};
let stageRequest = 0;
async function setStage(key) {
  const config = stageRoles[key];
  if (!config) return;
  const screen = screens.find(item => item.id === config.screenId), imageUrl = screen?.image;
  if (!imageUrl) return;
  const request = ++stageRequest, image = new Image();
  image.src = imageUrl;
  try { await image.decode(); } catch { return; }
  if (request !== stageRequest) return;
  const target = $('#stage-image');
  target.src = imageUrl;
  target.alt = config.alt || '';
  target.width = screen.width || 390;
  target.height = screen.height || 844;
  $('#stage-open').setAttribute('aria-label', `查看${screen.title || config.caption}截图`);
  $('#stage-open').onclick = () => openStageScreen(screen);
  const extra = $('#stage-extra');
  extra.replaceChildren();
  for (const id of config.extraIds) {
    const related = screens.find(item => item.id === id);
    if (!related) continue;
    const button = node('button', undefined, 'stage-screen');
    button.type = 'button';
    button.setAttribute('aria-label', `查看${related.title}截图`);
    button.append(screenImage(related));
    button.onclick = () => openStageScreen(related);
    extra.append(button);
  }
  $('#product-stage').dataset.role = key;
  $('#stage-caption').textContent = config.caption;
  $('#stage-launch').href = config.demo;
  $('#stage-launch').textContent = key === 'operator' ? '打开后台 ↗' : '打开 App ↗';
  $('#stage-browse').dataset.exploreRole = key;
  $('#stage-browse').replaceChildren(node('span', config.browse), node('span', '↘'));
  $('#stage-panel').setAttribute('aria-labelledby', `role-${key}`);
  document.querySelectorAll('[data-stage-role]').forEach(button => {
    const selected = button.dataset.stageRole === key;
    button.setAttribute('aria-selected', String(selected));
    button.tabIndex = selected ? 0 : -1;
  });
  if (!reduceMotion.matches) $('#stage-panel').animate([{opacity: .45}, {opacity: 1}], {duration: 220, easing: 'ease-out'});
}
const roleTabs=[...document.querySelectorAll('[data-stage-role]')];
roleTabs.forEach((button, index) => {
  button.onclick = () => setStage(button.dataset.stageRole);
  button.onkeydown = event => {
    let target;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') target = (index + 1) % roleTabs.length;
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') target = (index + roleTabs.length - 1) % roleTabs.length;
    else if (event.key === 'Home') target = 0;
    else if (event.key === 'End') target = roleTabs.length - 1;
    else return;
    event.preventDefault();
    roleTabs[target].focus();
    setStage(roleTabs[target].dataset.stageRole);
  };
});
document.querySelectorAll('[data-explore-role]').forEach(link => {
  link.onclick = () => {
    const value = link.dataset.exploreRole;
    role = value === 'all' ? 'all' : value;
    platform = value === 'operator' || value === 'admin' ? 'admin' : 'flutter';
    flow = 'all';
    state = 'all';
    query = '';
    favoriteOnly = false;
    render();
  };
});

/* ---------------- 页面级动效与装饰（尊重减少动态偏好） ---------------- */
let revealObserver = null;
function observeReveals() {
  const nodes = [...document.querySelectorAll('[data-reveal]:not(.is-visible)')];
  if (!nodes.length) return;
  if (reduceMotion.matches || !('IntersectionObserver' in window)) {
    nodes.forEach(el => el.classList.add('is-visible'));
    return;
  }
  if (!revealObserver) {
    revealObserver = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    }, {threshold: .12, rootMargin: '0px 0px -8% 0px'});
  }
  nodes.forEach(el => revealObserver.observe(el));
}

const progressBar = $('#scroll-progress');
let scrollTicking = false;
function paintScroll() {
  const y = window.scrollY || document.documentElement.scrollTop;
  document.body.classList.toggle('is-scrolled', y > 8);
  const max = document.documentElement.scrollHeight - window.innerHeight;
  if (progressBar) progressBar.style.transform = `scaleX(${max > 0 ? Math.min(1, y / max) : 0})`;
  scrollTicking = false;
}
function requestScrollPaint() {
  if (scrollTicking) return;
  scrollTicking = true;
  requestAnimationFrame(paintScroll);
}
addEventListener('scroll', requestScrollPaint, {passive: true});
addEventListener('resize', requestScrollPaint, {passive: true});

const statsBand = document.querySelector('.stats-band');
if (statsBand) {
  if (reduceMotion.matches || !('IntersectionObserver' in window)) {
    statsInView = true;
    if (screensReady) animateStats();
  } else {
    const statsObserver = new IntersectionObserver(entries => {
      if (!entries.some(entry => entry.isIntersecting)) return;
      statsInView = true;
      if (screensReady) animateStats();
      statsObserver.disconnect();
    }, {threshold: .3});
    statsObserver.observe(statsBand);
  }
}
const backToTop = $('#back-to-top');
if (backToTop) backToTop.onclick = () => window.scrollTo({top: 0, behavior: reduceMotion.matches ? 'auto' : 'smooth'});

syncControls();
paintScroll();
observeReveals();
await loadScreens();
await setStage('customer');
observeReveals();
