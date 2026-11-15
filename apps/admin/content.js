import {el,money,shanghaiInput,fromShanghaiInput} from './ui.js';
const schemas={
 services:{title:'服务目录',singular:'服务',fields:[['title','服务名称','text',true],['game','游戏','text',true],['category','分类','text',true],['description','服务说明','textarea',true],['priceCents','价格 / 元','money',true],['durationMinutes','时长 / 分钟','number',true],['platform','终端','select',false,['PC','mobile']],['serviceType','服务类型','select',false,['hourly','escort','review']],['gameMode','模式','text'],['billingUnit','计价单位','select',false,['hour','session','target']],['teamSize','服务成员人数','count'],['maps','地图','array'],['tags','标签','array'],['inclusions','包含内容','lines'],['requirements','下单要求','lines'],['rules','服务规则','lines'],['coverUrl','服务封面 / HTTPS','url'],['gameIconUrl','游戏图标 / HTTPS','url'],['bannerUrl','游戏横幅 / HTTPS','url'],['variants','服务规格','variants']]},
 players:{title:'成员资料',singular:'成员',fields:[['name','成员名称','text',true],['role','定位','text',true],['bio','个人介绍','textarea',true],['games','游戏','array',true],['tags','标签','array'],['initials','头像简写','text',true],['color','头像颜色','color',true],['avatarUrl','头像地址 / HTTPS','url'],['coverUrl','封面地址 / HTTPS','url']]},
 banners:{title:'首页横幅',singular:'横幅',fields:[['title','标题','text',true],['imageUrl','横幅图片 / HTTPS','url',true],['serviceId','关联服务编号','text'],['game','关联游戏','text'],['sortOrder','显示顺序','sort']]},
 announcements:{title:'俱乐部公告',singular:'公告',fields:[['title','标题','text',true],['body','正文','textarea',true],['publishedAt','发布时间 / 上海','datetime-local',true]]}
};
const labels={PC:'电脑端',mobile:'手机端',hourly:'按时组队',escort:'护航',review:'复盘',hour:'小时',session:'次',target:'目标'};
export function contentManager({request,isConnected,getData,onChange}){
 const $=s=>document.querySelector(s);let section='services',editing=null;
 function show(next){section=next;$('#content-title').textContent=schemas[section].title;$('#create-content').textContent=`新增${schemas[section].singular}`;$('#create-content').hidden=!isConnected();render();}
 function render(){
  const list=$('#content-list');list.classList.toggle('banner-grid',section==='banners');list.replaceChildren();$('#content-message').textContent='';
  const records=getData()[section]||[];
  if(!records.length){list.append(el('div',{class:'empty-state'},`还没有${schemas[section].singular}`));return;}
  for(const item of records){
   const row=el('article',{class:`content-row${item.archived?' archived':''}`}),text=el('div',{class:'content-copy'},el('h3',{},item.title||item.name));
   if(section==='services'){
    text.append(el('p',{class:'content-facts'},[item.game,labels[item.platform],item.gameMode,(item.maps||[]).join(' / ')].filter(Boolean).join(' · ')),el('p',{class:'content-body'},item.description),el('strong',{class:'service-price'},`${money(item.priceCents)} / ${item.durationMinutes} 分钟`));
    if(item.variants?.length)text.append(el('span',{class:'badge neutral'},`${item.variants.length} 个规格`));
   }else if(section==='players')text.append(el('p',{},item.role),el('p',{class:'content-body'},item.bio));
   else if(section==='banners')text.append(el('img',{src:item.imageUrl,alt:item.title,class:'content-banner-preview'}),el('p',{class:'content-facts'},`顺序 ${item.sortOrder} · ${item.serviceId||item.game}`));
   else text.append(el('p',{class:'content-body'},item.body),el('time',{class:'muted'},shanghaiInput(item.publishedAt).replace('T',' ')));
   const actions=el('div',{class:'content-actions'});
   if(item.archived)actions.append(el('span',{class:'badge neutral'},'已归档'));
   actions.append(el('button',{class:'action soft',onclick:()=>open(item)},isConnected()?'编辑':'查看'));
   if(isConnected()&&!item.archived)actions.append(el('button',{class:'action plain',onclick:async()=>{
    if(!confirm(`归档「${item.title||item.name}」？`))return;
    try{await request(`/admin/${section}/${encodeURIComponent(item.id)}`,{method:'DELETE'});await onChange();render();}catch(e){$('#content-message').textContent=e.message;}
   }},'归档'));
   row.append(text,actions);list.append(row);
  }
 }
 function variantEditor(items){
  const wrapper=el('section',{id:'editor-variants',class:'variant-editor full-width'}),list=el('div',{class:'variant-list'}),readers=new Map();
  const add=item=>{
   const values={},card=el('div',{class:'variant-card'}),grid=el('div',{class:'editor-fields variant-fields'}),advanced=el('details',{},el('summary',{},'独立服务规则'));
   const definitions=[['title','规格名称','text'],['priceCents','价格 / 元','money'],['durationMinutes','时长 / 分钟','number'],['platform','终端','select',['PC','mobile']],['gameMode','模式','text'],['maps','地图','array'],['serviceType','服务类型','select',['hourly','escort','review']],['billingUnit','计价单位','select',['hour','session','target']],['teamSize','服务成员人数','count'],['rules','规则','lines']];
   for(const [key,title,type,choices]of definitions){
    const input=type==='select'?el('select',{},el('option',{value:''},'沿用服务设置'),...choices.map(v=>el('option',{value:v},labels[v]))):el(type==='lines'?'textarea':'input');
    if(input.tagName==='INPUT')input.type=['money','number','count','sort'].includes(type)?'number':'text';
    input.disabled=!isConnected();input.required=['title','priceCents','durationMinutes'].includes(key);
    if(type==='money'){input.value=item.priceCents===undefined?'':item.priceCents/100;input.min='.01';input.max='100000';input.step='.01';}
    else if(['number','count'].includes(type)){input.value=item[key]??(type==='number'?60:'');input.min=type==='count'?1:15;input.max=type==='count'?4:720;input.step=1;}
    else if(['array','lines'].includes(type))input.value=(item[key]||[]).join(type==='lines'?'\n':'，');
    else input.value=item[key]||'';
    if(type==='lines'){input.rows=3;input.placeholder='每行一条；留空沿用服务规则';}
    const label=el('label',{class:type==='lines'?'full-width':''},el('span',{},title),input);values[key]={input,type};
    if(['title','priceCents','durationMinutes','platform'].includes(key))grid.append(label);else advanced.append(label);
   }
   const remove=el('button',{type:'button',class:'action plain',hidden:!isConnected(),onclick:()=>{readers.delete(card);card.remove();}},'移除规格');
   card.append(grid,advanced,remove);list.append(card);
   readers.set(card,()=>{const result={id:item.id||`sku-${crypto.randomUUID().slice(0,8)}`};for(const[key,{input,type}]of Object.entries(values)){const value=input.value.trim();if(!value&&!['title','priceCents','durationMinutes'].includes(key))continue;result[key]=type==='money'?Math.round(Number(value)*100):['number','count','sort'].includes(type)?Number(value):type==='array'?value.split(/[,，]/).map(v=>v.trim()).filter(Boolean):type==='lines'?value.split('\n').map(v=>v.trim()).filter(Boolean):value;}return result;});
  };
  const addButton=el('button',{type:'button',class:'action soft',hidden:!isConnected(),onclick:()=>{if(readers.size>=20){$('#editor-error').textContent='最多添加 20 个规格。';return;}add({});}},'＋ 添加规格');
  wrapper.append(el('div',{class:'variant-heading'},el('h3',{},'服务规格'),addButton),list);items.forEach(add);wrapper.read=()=>[...readers.values()].map(read=>read());return wrapper;
 }
 function open(item=null,kind=section){
  section=kind;editing=item;const schema=schemas[kind];$('#editor-title').textContent=`${isConnected()?(item?'编辑':'新增'):'查看'}${schema.singular}`;
  const fields=$('#editor-fields');fields.replaceChildren();
  for(const [key,label,type,required,options]of schema.fields){
   if(type==='variants'){fields.append(variantEditor(item?.variants||[]));continue;}
   const wrapper=el('label',{class:['textarea','lines','json'].includes(type)?'full-width':''},el('span',{},label));
   const input=type==='select'?el('select',{},el('option',{value:''},'未设置'),...options.map(value=>el('option',{value},labels[value]||value))):el(['textarea','lines','json'].includes(type)?'textarea':'input');
   input.name=key;input.required=!!required;input.disabled=!isConnected();
   if(input.tagName==='INPUT')input.type=type==='array'?'text':['money','number','count','sort'].includes(type)?'number':type;
   if(input.tagName==='TEXTAREA')input.rows=type==='json'?7:3;
   if(type==='money'){input.value=item?item[key]/100:'';input.min='0.01';input.max='100000';input.step='0.01';}
   else if(type==='number'){input.value=item?.[key]??60;input.min='15';input.max='720';input.step='1';}
   else if(type==='sort'){input.value=item?.[key]??0;input.min='0';input.max='1000';input.step='1';}
   else if(type==='count'){input.value=item?.[key]??1;input.min='1';input.max='4';input.step='1';}
   else if(type==='array'){input.value=(item?.[key]||[]).join('，');input.placeholder='用逗号分隔';}
   else if(type==='lines'){input.value=(item?.[key]||[]).join('\n');input.placeholder='每行一项';}
   else if(type==='json'){input.value=JSON.stringify(item?.[key]||[],null,2);input.spellcheck=false;input.className='code-field';}
   else if(type==='datetime-local')input.value=shanghaiInput(item?.[key]||new Date().toISOString());
   else input.value=item?.[key]||(type==='color'?'#315B45':'');
   if(type==='text')input.maxLength=key==='initials'?2:200;
   if(type==='url')input.placeholder='https://';
   wrapper.append(input);fields.append(wrapper);
  }
  if(item?.archived&&isConnected())fields.append(el('label',{class:'check-field full-width'},el('input',{type:'checkbox',name:'restore'}),'恢复展示'));
  $('#editor-error').textContent='';$('#edit-form [type=submit]').hidden=!isConnected();$('#editor').showModal();
 }
 $('#edit-form').onsubmit=async event=>{
  event.preventDefault();if(!isConnected())return;const submit=event.target.querySelector('[type=submit]');submit.disabled=true;
  try{
   const data={};
   for(const [key,,type]of schemas[section].fields){
    if(type==='variants'){data.variants=$('#editor-variants').read();continue;}
    const value=event.target.elements.namedItem(key).value.trim();if(type==='select'&&!value)continue;data[key]=type==='array'?value.split(/[,，]/).map(v=>v.trim()).filter(Boolean):type==='lines'?value.split('\n').map(v=>v.trim()).filter(Boolean):type==='money'?Math.round(Number(value)*100):['number','count','sort'].includes(type)?Number(value):type==='datetime-local'?fromShanghaiInput(value):value;
   }
   if(data.variants&&!Array.isArray(data.variants))throw Error('规格必须是 JSON 数组。');
   if(event.target.elements.namedItem('restore')?.checked)data.archived=false;
   await request(`/admin/${section}${editing?`/${encodeURIComponent(editing.id)}`:''}`,{method:editing?'PATCH':'POST',body:JSON.stringify(data)});$('#editor').close();await onChange();render();
  }catch(e){$('#editor-error').textContent=e instanceof SyntaxError?'规格 JSON 格式有误。':e.message;}finally{submit.disabled=false;}
 };
 $('#create-content').onclick=()=>open();$('#close-editor').onclick=()=>$('#editor').close();
 return {show,render,editMember:item=>open(item,'players')};
}
