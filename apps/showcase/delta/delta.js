const modes = {
  operations: {title:'烽火地带',category:'探索 / 搜集 / 撤离',description:'进入战局，规划路线与装备，在信息沟通和战术配合中寻找撤离机会。',image:'operations-scene.jpg',alt:'烽火地带的城市战斗场景',index:'01 / 02'},
  warfare: {title:'全面战场',category:'进攻 / 防守 / 协同',description:'在大规模战场中配合队友推进目标。步兵与载具共同参与，让每个位置的行动形成合力。',image:'warfare-scene.jpg',alt:'全面战场的海岸、载具与战斗场景',index:'02 / 02'}
};
const maps = {
  spaceport:{name:'航天基地',subtitle:'SPACE CITY',description:'从开阔区域到建筑内部，和小队一起观察地形、沟通路线。',image:'spaceport-scene.jpg'},
  valley:{name:'长弓溪谷',subtitle:'LAYALI GROVE',description:'穿行山地与建筑之间，观察视野变化，和队友一起安排下一段路线。',image:'longbow-valley-scene.jpg'}
};
const $ = id => document.getElementById(id);
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
let motionPaused = reduced.matches;
let heroVisible = true;
let framePending = false;
const ambient = $('ambient-video');
const film = $('film-video');
const dialog = $('film-dialog');

function loadVideo(video) {
  const source = video.querySelector('source');
  if (!source.hasAttribute('src')) { source.src = source.dataset.src; video.load(); }
}
function syncMotion() {
  document.body.classList.toggle('motion-off', motionPaused);
  $('motion-toggle').hidden = reduced.matches;
  $('motion-toggle').setAttribute('aria-pressed', String(motionPaused));
  $('motion-toggle').innerHTML = motionPaused ? '播放动态 <span aria-hidden="true">▷</span>' : '暂停动态 <span aria-hidden="true">Ⅱ</span>';
  if (motionPaused || !heroVisible || document.hidden || dialog.open) { ambient.pause(); return; }
  loadVideo(ambient);
  ambient.play().catch(() => { ambient.classList.remove('ready'); });
}
ambient.addEventListener('playing', () => ambient.classList.add('ready'));
$('motion-toggle').addEventListener('click', () => { motionPaused = !motionPaused; syncMotion(); });
reduced.addEventListener('change', () => { motionPaused = reduced.matches; syncMotion(); });
document.addEventListener('visibilitychange', syncMotion);

function updateScroll() {
  framePending = false;
  const hero = $('overview');
  const progress = Math.max(0, Math.min(1, -hero.getBoundingClientRect().top / Math.max(1, hero.offsetHeight - innerHeight)));
  hero.style.setProperty('--hero-progress', String(progress));
  document.querySelector('.topbar').classList.toggle('scrolled', scrollY > 60);
  const current = ['overview','modes','maps'].filter(id => $(id).getBoundingClientRect().top <= innerHeight * .45).at(-1) || 'overview';
  document.querySelectorAll('.chapter-rail a').forEach(link => {
    if (link.hash === `#${current}`) link.setAttribute('aria-current','location');
    else link.removeAttribute('aria-current');
  });
}
window.addEventListener('scroll', () => { if (!framePending) { framePending = true; requestAnimationFrame(updateScroll); } }, {passive:true});
window.addEventListener('resize', updateScroll);
new IntersectionObserver(entries => {
  for (const entry of entries) {
    if (entry.target.id === 'overview') { heroVisible = entry.isIntersecting; syncMotion(); }
  }
}, {rootMargin:'-20% 0px -45% 0px',threshold:0}).observe($('overview'));

function animateImage(image) {
  if (!motionPaused) image.animate([{opacity:.45,transform:'scale(1.025)'},{opacity:1,transform:'scale(1)'}], {duration:550,easing:'cubic-bezier(.2,.7,.2,1)'});
}
function selectTab(buttons, button) {
  buttons.forEach(item => { item.setAttribute('aria-selected',String(item === button)); item.tabIndex = item === button ? 0 : -1; });
}
function wireTabs(selector, key, select) {
  const buttons = [...document.querySelectorAll(selector)];
  buttons.forEach((button,index) => {
    button.addEventListener('click', () => { selectTab(buttons,button); select(button.dataset[key],button); });
    button.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % buttons.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + buttons.length) % buttons.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = buttons.length - 1;
      if (next !== undefined) { event.preventDefault(); buttons[next].click(); buttons[next].focus(); }
    });
  });
}
wireTabs('[data-mode]','mode',(key,button) => {
  const mode = modes[key];
  $('mode-title').textContent = mode.title;
  $('mode-category').textContent = mode.category;
  $('mode-description').textContent = mode.description;
  $('mode-index').textContent = mode.index;
  $('mode-image').src = `./assets/${mode.image}`;
  $('mode-image').alt = mode.alt;
  $('mode-panel').setAttribute('aria-labelledby',button.id);
  animateImage($('mode-image'));
});
wireTabs('[data-map]','map',(key,button) => {
  const map = maps[key];
  $('map-name').textContent = map.name;
  $('map-subtitle').textContent = map.subtitle;
  $('map-description').textContent = map.description;
  $('map-image').src = `./assets/${map.image}`;
  $('map-image').alt = `三角洲行动${map.name}官方场景`;
  $('map-view').setAttribute('aria-labelledby',button.id);
  $('map-view').textContent = `${map.name}官方地图画面`;
  animateImage($('map-image'));
});
$('open-film').addEventListener('click', () => {
  loadVideo(film); film.currentTime = 0; dialog.showModal(); syncMotion();
  film.play().catch(() => {});
});
$('close-film').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => { if (event.target === dialog && (event.clientX < dialog.getBoundingClientRect().left || event.clientX > dialog.getBoundingClientRect().right || event.clientY < dialog.getBoundingClientRect().top || event.clientY > dialog.getBoundingClientRect().bottom)) dialog.close(); });
dialog.addEventListener('close', () => { film.pause(); $('open-film').focus(); syncMotion(); });
updateScroll();
syncMotion();
