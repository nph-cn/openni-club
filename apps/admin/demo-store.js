// 示例工作台的本地预览存储。
// 未连接后端时，打手分级、游戏类目与能力开关的改动只写入 localStorage；
// 连接后端后不读取也不写入本层，保持原有只读/真实接口行为。
const STORAGE_KEY = 'openni-admin-demo-preview-v1';
const SECTIONS = ['players', 'games', 'features'];

function readOverlay() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

// 用本机预览数据覆盖示例快照中的对应数组；其他字段仍来自快照。
export function applyDemoOverlay(snapshot) {
  const overlay = readOverlay();
  if (!overlay) return snapshot;
  const next = {...snapshot};
  for (const section of SECTIONS) {
    if (Array.isArray(overlay[section]) && overlay[section].length) next[section] = clone(overlay[section]);
  }
  return next;
}

export function saveDemoSection(section, records) {
  if (!SECTIONS.includes(section)) throw Error(`未知的示例数据类型：${section}`);
  const overlay = readOverlay() || {};
  overlay[section] = clone(records);
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(overlay));
  } catch {
    // 隐私模式或配额受限时退回内存态；当前页面仍可继续预览。
  }
}

export function hasDemoEdits() {
  const overlay = readOverlay();
  return Boolean(overlay && SECTIONS.some(section => Array.isArray(overlay[section]) && overlay[section].length));
}

export function resetDemoPreview() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // 存储不可用时无需清理。
  }
}
