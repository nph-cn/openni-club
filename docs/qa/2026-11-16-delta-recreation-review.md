# 三角洲专题二创验收记录（2026-11-16）

用户反馈上一版「学 KPR 做得差、没有二创感」。本轮按用户指定仓库 <https://github.com/lixiaolin94/skills> 中的 `web-shader-extractor` 流程先做 KPR 取证与目标锁定，再以三角洲素材和 OpenNI 业务重做 `/delta/`。**这不是 KPR 的像素复刻**，也不复制 KPR 的品牌、角色、文案、音频或源码。

## 一、方法与证据

> 本节提到的 `work/...`、`wo/outputs/...` 是本次交付工作区路径，不属于仓库内容；仓库内只保留产品代码与文档。

- 技能版本：`lixiaolin94/skills` 的 `web-shader-extractor`，下载 commit `665b5856fcad1e03f16ccede364ad86874fac982`（与当日 main HEAD 一致）。文件哈希与来源记录在 `work/kpr-shader-study/skill-source.json`。
- 目标锁定：KPR 首页由 `#canvas-container > canvas[data-engine="three.js r150"]`（WebGL2，18 个 shader / 9 个 program）+ `#ui-container` 固定 DOM 文字层 + GSAP ScrollSmoother 滚动驱动组成。
- 归因实验：消隐 canvas 后整页只剩白底（截图差异 78.834）；消隐 `#ui-container` 后文字与导航消失（差异 108.687）。移动端 390px 直接显示不支持提示。
- 事实分级：滚动平滑、相机 `fov 24 / damp 3 / 指针 orbit ±0.06π`、遮罩渐变与 20 采样高斯模糊材质为 `SOURCE`；逐章节相机关键帧与过渡曲线为 `PARTIAL/GUESS`。
- 结论：采用 `BEHAVIOR_REBUILD` + `visual-language-adaptation`，只继承「全屏画布 + DOM 文字层 + 平滑滚动 + 图像平面过渡」这套语言，其余全部自研。门禁产物在 `work/kpr-shader-study/evidence/{scout-card.json,replay-manifest.json,extraction-report.md,known-gaps.md}`，状态在 `.web-shader-extractor/run-state.json`。

## 二、本轮改动

| 文件 | 内容 |
| --- | --- |
| `apps/showcase/delta/index.html` | 五章结构：入局 / 行动方式 / 地形情报 / 小队集结 / 部署；固定框架、章节导航、左侧进度轨、等宽 HUD、影像弹层 |
| `apps/showcase/delta/delta-stage.js` | 新增。自研 WebGL2 单 pass：封面映射、双纹理调色、噪声擦场、尘粒/余烬、地图扫描、操作员遮罩显影、暗角/颗粒/色差；纹理上限 1920、DPR 上限、可见性暂停 |
| `apps/showcase/delta/delta.js` | 新增滚动编排：章节判定、进度阻尼、模式/地图切换、键盘 tabs、重新扫描、影像弹层、暂停动态、减少动态、无 WebGL 降级 |
| `apps/showcase/delta/delta.css` | 重写：石墨/纸白双主题、纸面「窗口」露出画布、章节 ghost 数字、HUD、成员卡、响应式与无障碍 |
| `apps/showcase/delta/sources.html` | 更新素材、成员头像、字体与设计参考说明 |
| `apps/showcase/delta/assets/squad-*.webp` | 4 张 App 虚构演示成员头像的 512×512 派生图（源图与生成记录仍在 `apps/mobile/assets/demo/`） |
| `apps/showcase/fonts/IBMPlexMono-*.woff2` | HUD 等宽字体（SIL OFL 1.1，许可文本同目录） |
| `scripts/prepare-delta-assets.mjs` | 新增：成员头像派生图生成脚本 |
| `DESIGN.md` / `AGENTS.md` / `README.md` / `docs/00-status.md` | 更新三角洲专题说明与验收状态 |

二创落点：把 KPR 的「You are a keeper」转译为 OpenNI 的「一个人的枪法，四个人的战局」，小队章直接连到 App 成员页；HUD 只展示真实章节、滚动百分比、视口、本地时间与渲染状态，不编造运营指标。

## 三、自动化验收

验收脚本 `work/delta-check/verify-delta.mjs`（Playwright + Edge headless，1440×900 / 390×844），结果 `work/delta-check/final/verify-report.json`。

| 项目 | 结果 |
| --- | --- |
| 页面与控制台 | 无 pageerror、无 console error、无失败响应 |
| 桌面 1440×900 | WebGL2 画布 1440×900 backing；五章 `activeNav` 与 HUD 章节正确；横向溢出 0 |
| 手机 390×844 | 画布 390×844；章节导航与 HUD 正确；横向溢出 0 |
| 模式切换 | 烽火地带 ↔ 全面战场：文案、窗口标签、画面底图同步切换 |
| 地图切换 | 航天基地 ↔ 长弓溪谷：读数、CODE、画面同步切换；重新扫描按钮进入 `is-active` |
| 键盘 tabs | ArrowLeft/End/Home 正常切换并维持 roving tabindex |
| 影像弹层 | 打开后 `videoWidth=1280`、自动播放 `global-hero.mp4`；关闭后停止 |
| 暂停动态 | `body.reduce-motion` + HUD `STAGE STATIC` |
| 减少动态（OS） | `prefers-reduced-motion` 命中、`document.getAnimations()` 为 0、stage time 连续采样冻结、画布裁剪连续帧一致 |
| 无 WebGL | `body.no-stage` + HUD `STAGE FALLBACK`，静态底图与人物层正常显示（截图 `桌面-12-无WebGL降级.jpg`） |
| 资源 | 所有 `data-plate` / 图片 / App 入口 / `/guide/` / `assets-manifest.json` 均 200 |
| 主循环 | headless 环境 rAF 未节流（约 240fps），仅证明循环正常，不代表真机帧率 |

## 四、交付截图

`work/delta-check/final/` 为 PNG 原图；交付目录 `wo/outputs/OpenNI_三角洲战地档案改版/` 内为 19 张 JPG：桌面 13 张、手机 6 张。演示视频 `三角洲战地档案_演示.mp4` 为 1440×900 滚动实拍。

## 五、边界与未完成

- 官方游戏美术、角色与视频不属于 MIT 授权；商业发布前需核实权利或替换。页面明确标注非游戏官方网站。
- 本轮只在 Chromium/Edge headless + SwiftShader WebGL 环境验收，未做 Safari/Firefox、iOS/Android 真机、低端 GPU 与网络限速测试；真机帧率待验证。
- 未建立 KPR 像素级基线（本轮产品目标是二创而非复刻，见 known-gaps）。
- 小程序截图与 App 业务逻辑不在本轮范围；App 与图库仍沿用上一版验收记录。
- GitHub CI 以新提交的 Actions 结果为准，不用上一提交的构建结果代替。


## 追加：Three.js 3D 重构（2026-11-16 第二轮）

用户要求「看 KPR 做得多好，为什么不能做成他的那个样子」，因此本轮不再用 CSS/2D shader，而是：

- 引入 Three.js r160（vendored，MIT）与 `delta-scene.js`：透视相机 + 分层图像平面 + 视频纹理 + 自定义 post-processing（调色、颗粒、暗角、色差、扫描线）。
- 预加载仪式：装载进度 → 「开启声音进入 / 静音进入」；进入后相机推近、逐字标题出现、环境声（WebAudio 程序生成）可开关。
- 交互：章节菜单、自定义光标、HOLD「战地呼吸」、3D 拾取（干员立绘→成员页、3D 手机→服务页）、地形章拖拽旋转、模式/地图切换、减少动态/无 WebGL 降级。
- 素材：从三角洲官方公开页面采集 393 项候选（46 张透明干员、6 段官方视频）；专题选用 12 项 4K 图与 2 段转码视频，来源与 SHA 写入 `apps/showcase/delta/assets-manifest.json`，原始库在 `work/delta-assets/`。
- 查明的关键 bug：地形章 scan 着色器平面未加入 planes 数组，导致 fade 恒为 1 覆盖全屏；已改为按章节显隐。

当前状态：首屏、行动方式、小队（4 卡 2×2）、部署已达到较完整效果；地形章地图亮度/构图、小队卡片与移动端逐章布局仍在精修。演示与截图见 `work/delta-check/`。
