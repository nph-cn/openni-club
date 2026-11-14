export const club = {
  id: 'northshore', name: '北岸电竞', tagline: '找到同频队友，一起打好每一局。',
  description: '北岸电竞是 OpenNI Club 的虚构演示俱乐部。这里展示俱乐部、队友与预约的完整体验。所有人物、服务和价格均为演示数据，与游戏发行商无关联。',
  city: '线上俱乐部', notice: '演示环境 · 预约不会扣款，不提供真实游戏服务。',
  legalEntity:'示例运营主体（上线前替换）',supportContact:'示例客服（上线前替换）',
  privacyText:'演示隐私说明，不可作为正式政策发布。匿名演示会话用于关联模拟预约；请勿填写真实个人信息。运营方上线前须完整填写收集目的、数据类型、保存期限、共享对象、用户访问与删除方式、经营主体及联系渠道。',
  termsText:'演示服务协议，不提供真实服务、不产生付款。上线前由运营方明确服务内容、履约时段、取消退款规则、双方责任与争议处理渠道。'
};
export const services = [
  {id:'s1',title:'三角洲 · PC 小时陪',game:'三角洲行动',category:'小时陪',description:'一位成员与你组队，提供地图路线沟通、报点与协作。按预约时段履约，不承诺游戏收益。',priceCents:3900,durationMinutes:60,tags:['单陪','语音沟通'],platform:'PC',serviceType:'hourly',teamSize:1,billingUnit:'hour',gameMode:'烽火地带',maps:['零号大坝','长弓溪谷'],rules:['一位服务成员，预约 60 分钟。','地图在当前可选范围内协商；无额外地图加价。','不承诺撤离、击杀或游戏资产收益。','服务结束后提交记录，由客户确认或申请售后。']},
  {id:'s2',title:'三角洲 · 对局复盘',game:'三角洲行动',category:'复盘',description:'与一位教练共同查看你提供的对局记录，梳理路线、报点和决策，交付文字复盘。',priceCents:6900,durationMinutes:60,tags:['一对一','文字复盘'],platform:'PC',serviceType:'review',teamSize:1,billingUnit:'session',gameMode:'烽火地带',maps:['零号大坝','长弓溪谷'],rules:['每次 60 分钟，一位教练。','预约前准备本人对局记录，不提供账号密码。','交付内容为复盘摘要与改进建议，不承诺段位提升。']},
  {id:'s3',title:'无畏契约 · 组队小时陪',game:'无畏契约',category:'小时陪',description:'一位成员提供团队语音、角色协作和组队对局，按约定时间结束。',priceCents:2900,durationMinutes:60,tags:['单陪','角色协作'],platform:'PC',serviceType:'hourly',teamSize:1,billingUnit:'hour',gameMode:'普通对局',maps:[],rules:['一位成员，60 分钟，不保证胜率。','不共享账号，不使用外挂。']},
  {id:'s4',title:'英雄联盟 · 双排小时陪',game:'英雄联盟',category:'小时陪',description:'一位成员与你双排，预约前沟通位置与时段。双排指两位玩家，不是两位服务成员。',priceCents:3500,durationMinutes:60,tags:['一位服务成员','位置协作'],platform:'PC',serviceType:'hourly',teamSize:1,billingUnit:'hour',gameMode:'召唤师峡谷',maps:['召唤师峡谷'],rules:['一位服务成员，60 分钟，不承诺上分。','双方各自使用自己的游戏账号。']}
];
export const players = [
  {id:'p1',name:'阿屿',role:'小队指挥',bio:'喜欢清晰的报点，也喜欢轻松的队内气氛。地图和打法都可以提前聊。虚构演示成员。',games:['三角洲行动'],tags:['耐心沟通','战术协作'],initials:'屿',color:'#2455E7'},
  {id:'p2',name:'Echo',role:'战术教练',bio:'把每一场对局里的小细节讲清楚。一起复盘，也一起进步。虚构演示成员。',games:['三角洲行动','无畏契约'],tags:['对局复盘','思路教学'],initials:'E',color:'#137B57'},
  {id:'p3',name:'小满',role:'开黑搭子',bio:'开心对局，认真沟通。偏爱团队配合，不催促、不责备。虚构演示成员。',games:['无畏契约','英雄联盟'],tags:['友好交流','团队协作'],initials:'满',color:'#AC4B38'},
  {id:'p4',name:'North',role:'全能队友',bio:'喜欢与新朋友一起找到合适的节奏。上线时间请在预约里备注。虚构演示成员。',games:['三角洲行动','英雄联盟'],tags:['节奏稳定','灵活补位'],initials:'N',color:'#7356AA'}
];
export const announcements = [
  {id:'a1',title:'欢迎来到北岸，一起找到同频队友',body:'这是 OpenNI Club 的演示公告。你可以浏览服务、了解成员并体验预约。所有订单均为模拟预约，不扣款、不提供真实游戏服务。',publishedAt:'2026-11-15T09:00:00+08:00'},
  {id:'a2',title:'预约前，先把这些小事说清楚',body:'预约时填写你希望的上线时间、联系方式和偏好。不要提交游戏密码、身份证或支付凭证。真实俱乐部上线前需要配置客服、隐私政策和订单规则。',publishedAt:'2026-11-14T10:00:00+08:00'},
  {id:'a3',title:'友好交流，从每一次报点开始',body:'尊重队友，文明交流。不要分享账号，不使用外挂或任何破坏公平竞技的工具。出现争议时通过俱乐部客服处理。',publishedAt:'2026-11-13T12:00:00+08:00'}
];
