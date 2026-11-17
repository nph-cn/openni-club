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
  return keys.map(key => ({key, name: labels.flow[key] || '其他页面', screens: screens.filter(screen => screen.flow === key)})).filter(group => group.screens.length);
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
