// 图库数据模型：标签、流程分组、筛选、排序、计数与分享链接。
// 该文件同时被浏览器（app.js）、构建脚本（scripts/build.mjs）和 Node 测试导入，
// 因此保持纯函数，不访问 DOM 或网络。

export const labels = {
  platform: {flutter: 'iOS / Android', mini: '微信小程序', admin: '运营后台'},
  role: {customer: '客户', member: '成员', operator: '运营'},
  // 顺序即图库中业务章节顺序；auth 固定在最前，未知流程会追加在末尾而不是被丢弃。
  flow: {
    auth: '登录与验证',
    discover: '发现与选人',
    booking: '预约与下单',
    fulfillment: '订单与履约',
    member: '成员工作台',
    account: '资料与设置',
    notifications: '消息与通知',
    search: '搜索与筛选',
    states: '加载与异常',
    launch: '启动与欢迎'
  },
  state: {ready: '正常', loading: '加载', empty: '空状态', error: '错误', verification: '验证', success: '完成'},
  capture: {route: '完整页面', interaction: '交互状态'}
};

// 每个业务章节的一句话说明，只描述截图中真实存在的页面类型。
export const flowIntros = {
  auth: '欢迎、登录方式、手机号与验证码的完整验证路径，含错误与验证中状态。',
  discover: '首页、服务与成员名册，含搜索、游戏筛选、关注与连接失败状态。',
  booking: '从服务规格、预约人、日期时段、联系方式到预约核对的完整下单路径。',
  fulfillment: '订单列表与详情：派单、接单、交付核对、取消、售后与评价完成。',
  member: '成员工作台：待接单、服务中、可接时段、交付记录与收入账本。',
  account: '个人中心、通知、设置与隐私，以及俱乐部公告和服务协议。',
  notifications: '客户与成员的通知列表、未读状态和关联订单入口。',
  search: '按关键词、游戏与筛选条件查找服务和成员，含空结果状态。',
  states: '加载骨架、连接失败、空列表与重试等运行状态。',
  launch: '启动与欢迎页，以及进入业务主界面前的入口。'
};

// 平台切换只列出真实存在的客户端；iOS 与 Android 共用一套 Flutter 界面，
// 截图统一在 iPhone 预览壳中采集，另外收录 Android 主题变体，因此合并为一项。
export const platformTabs = [
  {key: 'flutter', label: 'iOS / Android', hint: '同一套 Flutter 界面，含 Android 主题变体'},
  {key: 'mini', label: '微信小程序', hint: '微信原生小程序页面'},
  {key: 'admin', label: '运营后台', hint: '桌面运营工作台'}
];

// 状态筛选项固定展示；真实数量由界面按数据计算，不写死。
export const stateFilters = ['ready', 'loading', 'empty', 'error', 'verification', 'success'];

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

export function flowLabel(key) {
  return labels.flow[key] || '其他流程';
}

export function flowIntro(key) {
  return flowIntros[key] || '';
}

export function matchScreens(screens, filters, favorites = new Set()) {
  const {platform = 'flutter', role = 'all', flow = 'all', state = 'all', query = '', favoriteOnly = false} = filters;
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return screens.filter(screen => {
    const group = stateGroup(screen);
    const text = `${screen.title} ${screen.description || ''} ${flowLabel(screen.flow)} ${labels.state[group]} ${labels.capture[screen.captureKind] || ''}`.toLowerCase();
    return screen.platform === platform && (role === 'all' || screen.role === role) &&
      (flow === 'all' || screen.flow === flow) && (state === 'all' || group === state) &&
      (!favoriteOnly || favorites.has(screen.id)) && terms.every(term => text.includes(term));
  });
}

// 分组每个清单条目，包括未来新增的流程；白名单 ID 会静默丢掉新截图。
export function groupFlows(screens) {
  const keys = [...Object.keys(labels.flow), ...new Set(screens.map(screen => screen.flow).filter(key => !labels.flow[key]))];
  return keys.map(key => ({key, name: flowLabel(key), intro: flowIntro(key), screens: orderFlowScreens(screens.filter(screen => screen.flow === key))})).filter(group => group.screens.length);
}

export function orderFlowScreens(screens) {
  const order = screen => Number.isFinite(screen.flowOrder) ? screen.flowOrder : Infinity;
  return [...screens].sort((a, b) => order(a) - order(b));
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

// 首页 App 介绍区的真实统计：全部来自构建产物，不写死数字。
export function galleryStats(screens) {
  const counts = galleryCounts(screens, screens);
  const flows = new Set(screens.map(screen => screen.flow));
  const roles = new Set(screens.map(screen => screen.role));
  const interactions = screens.filter(screen => screen.captureKind === 'interaction');
  return {
    total: counts.total,
    platforms: counts.platforms,
    clients: Object.values(counts.platforms).filter(count => count > 0).length,
    flows: flows.size,
    roles: roles.size,
    interactions: interactions.length,
    states: new Set(screens.map(screen => stateGroup(screen))).size
  };
}

// 平台切换文案与计数；空平台由界面隐藏，不制造假数量。
export function platformSummary(stats) {
  return platformTabs.filter(tab => (stats.platforms[tab.key] || 0) > 0)
    .map(tab => `${tab.label} ${stats.platforms[tab.key]}`);
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
  const parts = String(screen.source || '').replaceAll('\\', '/').split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) return base;
  return base + parts.map(encodeURIComponent).join('/');
}

export function screenPreview(screen) {
  if (screen.platform === 'admin') return {href: screen.demo || '/admin/', label: '打开后台 ↗'};
  if (screen.platform === 'mini') return {href: screen.demo || '/guide/05-wechat-release.html', label: '查看小程序运行方式 ↗'};
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
    // 默认按业务流程分组浏览；view=screens 为全部界面平铺。
    view: choose('view', ['screens', 'flows'], 'flows'),
    query: (params.get('q') || '').slice(0, 160),
    screenId: params.get('screen') || ''
  };
}

export function gallerySearch(filters, screenId = '') {
  const params = new URLSearchParams();
  for (const key of ['platform', 'role', 'flow', 'state', 'view']) {
    const value = filters[key];
    if (value && value !== 'all' && !(key === 'platform' && value === 'flutter') && !(key === 'view' && value === 'flows')) params.set(key, value);
  }
  if (filters.query) params.set('q', filters.query);
  if (screenId) params.set('screen', screenId);
  return params.size ? `?${params}` : '';
}
