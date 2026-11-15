export const labels = {
  platform: {flutter: 'iOS / Android', mini: '微信小程序', admin: '运营后台'},
  role: {customer: '客户', member: '成员', operator: '运营'},
  flow: {auth: '登录与验证', discover: '发现与选人', booking: '下单', fulfillment: '履约与售后', member: '成员工作台', account: '资料与设置'},
  state: {ready: '正常', loading: '加载', empty: '空状态', error: '错误', verification: '验证', success: '完成'}
};

export function stateGroup(screen) {
  if (labels.state[screen.stateGroup]) return screen.stateGroup;
  const value = String(screen.state || '').toLowerCase();
  if (/error|fail|invalid|expired|blocked/.test(value)) return 'error';
  if (/loading|skeleton|busy|submitting/.test(value)) return 'loading';
  if (/empty|no.results/.test(value)) return 'empty';
  if (/verif|otp|code.entry/.test(value)) return 'verification';
  if (/success/.test(value)) return 'success';
  return 'ready';
}

export function matchScreens(screens, filters, favorites = new Set()) {
  const {platform = 'flutter', role = 'all', flow = 'all', state = 'all', query = '', favoriteOnly = false} = filters;
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return screens.filter(screen => {
    const group = stateGroup(screen);
    const text = `${screen.title} ${screen.description || ''} ${labels.flow[screen.flow] || ''} ${labels.state[group]}`.toLowerCase();
    return screen.platform === platform && (role === 'all' || screen.role === role) &&
      (flow === 'all' || screen.flow === flow) && (state === 'all' || group === state) &&
      (!favoriteOnly || favorites.has(screen.id)) && terms.every(term => text.includes(term));
  });
}

// Group every manifest entry, including future flows; a curated ID list silently lost new screens.
export function groupFlows(screens) {
  const keys = [...Object.keys(labels.flow), ...new Set(screens.map(screen => screen.flow).filter(key => !labels.flow[key]))];
  return keys.map(key => ({key, name: labels.flow[key] || '其他页面', screens: orderFlowScreens(screens.filter(screen => screen.flow === key))})).filter(group => group.screens.length);
}

export function orderFlowScreens(screens) {
  const order = screen => Number.isFinite(screen.flowOrder) ? screen.flowOrder : Infinity;
  return [...screens].sort((a,b) => order(a) - order(b));
}

// 浏览范围与缩略图共用同一序列，流程末页不会跳进其他流程。
export function browseSequence(shown, screenId, scope = 'results') {
  const current = shown.find(screen => screen.id === screenId);
  if (!current) return [];
  return scope === 'flow' ? orderFlowScreens(shown.filter(screen =>
    screen.platform === current.platform && screen.flow === current.flow)) : shown;
}

export function galleryCounts(screens, shown, favorites = new Set()) {
  return {
    total: screens.length,
    shown: shown.length,
    platforms: Object.fromEntries(Object.keys(labels.platform).map(key =>
      [key, screens.filter(screen => screen.platform === key).length])),
    favorites: new Set(screens.filter(screen => favorites.has(screen.id)).map(screen => screen.id)).size
  };
}

// 只改变本站 App 入口；保留页面参数，后台、小程序文档和外部链接不变。
export function appPreviewUrl(href) {
  const url = new URL(href, 'https://openni.local');
  if (url.origin !== 'https://openni.local' || !/^\/demo\/?$/.test(url.pathname)) return href;
  url.searchParams.set('device', 'iphone');
  return url.pathname + url.search + url.hash;
}

const repositorySourceRoot = 'https://github.com/nph-cn/openni-club/blob/';

// 生产默认 main；预览构建显式传入分支或提交，避免把截图链接到旧代码。
export function sourceBaseForRef(ref = 'main') {
  const parts = (String(ref).trim() || 'main').split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) throw Error('源码分支名称无效');
  return repositorySourceRoot + parts.map(encodeURIComponent).join('/') + '/';
}

export function sourceHref(screen) {
  let base = sourceBaseForRef();
  try {
    const url = new URL(screen.sourceBase);
    if (url.origin === 'https://github.com' && !url.username && !url.password &&
        url.pathname.startsWith('/nph-cn/openni-club/blob/') && url.pathname.endsWith('/') &&
        !url.search && !url.hash) base = url.href;
  } catch { /* 旧清单没有构建来源时，兼容 main。 */ }
  const parts = String(screen.source || '').replaceAll('\\','/').split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) return base;
  return base + parts.map(encodeURIComponent).join('/');
}

export function screenPreview(screen) {
  if (screen.platform === 'admin') return {href: screen.demo || '/admin/', label:'打开后台 ↗'};
  if (screen.platform === 'mini') return {href: screen.demo || '/guide/05-wechat-release.html', label:'查看小程序运行方式 ↗'};
  const start = screen.previewScreen ?? screen.id;
  const interaction = screen.captureKind === 'interaction';
  return {
    href: appPreviewUrl(interaction || screen.previewScreen ? `/demo/?screen=${encodeURIComponent(start)}` : screen.demo || `/demo/?screen=${encodeURIComponent(start)}`),
    label: interaction ? '打开流程起点 ↗' : '打开此页 ↗'
  };
}

export function parseLocation(search) {
  const params = new URLSearchParams(search);
  const choose = (key, choices, fallback) => choices.includes(params.get(key)) ? params.get(key) : fallback;
  return {
    platform: choose('platform', Object.keys(labels.platform), 'flutter'),
    role: choose('role', ['all', ...Object.keys(labels.role)], 'all'),
    flow: choose('flow', ['all', ...Object.keys(labels.flow)], 'all'),
    state: choose('state', ['all', ...Object.keys(labels.state)], 'all'),
    view: choose('view', ['screens', 'flows'], 'screens'),
    query: (params.get('q') || '').slice(0, 160),
    screenId: params.get('screen') || ''
  };
}

export function gallerySearch(filters, screenId = '') {
  const params = new URLSearchParams();
  for (const key of ['platform', 'role', 'flow', 'state', 'view']) {
    const value = filters[key];
    if (value && value !== 'all' && !(key === 'platform' && value === 'flutter') && !(key === 'view' && value === 'screens')) params.set(key, value);
  }
  if (filters.query) params.set('q', filters.query);
  if (screenId) params.set('screen', screenId);
  return params.size ? `?${params}` : '';
}
