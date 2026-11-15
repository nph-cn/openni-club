import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {createAvailability} from './availability.mjs';
import {createLedger} from './ledger.mjs';

export function createOperations({db,config,fail,clubData,catalog,entry}) {
  const now=config.now||Date.now,iso=()=>new Date(now()).toISOString();
  function column(table,name,type){if(!db.prepare(`PRAGMA table_info(${table})`).all().some(item=>item.name===name))db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`);}
  column('users','role',"TEXT NOT NULL DEFAULT 'customer'");column('users','player_id','TEXT');
  column('orders','service_snapshot','TEXT');
  for(const [name,type]of Object.entries({fulfillment_status:'TEXT',assigned_player_id:'TEXT',commission_bps:'INTEGER NOT NULL DEFAULT 2000',member_cents:'INTEGER NOT NULL DEFAULT 0',club_cents:'INTEGER NOT NULL DEFAULT 0',duration_minutes:'INTEGER NOT NULL DEFAULT 60',service_game:'TEXT',accept_by:'TEXT',payment_expires_at:'TEXT'}))column('orders',name,type);
  db.exec(`CREATE TABLE IF NOT EXISTS order_events(id TEXT PRIMARY KEY,order_id TEXT NOT NULL,type TEXT NOT NULL,at TEXT NOT NULL,actor_role TEXT NOT NULL,actor_name TEXT NOT NULL,message TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS deliveries(order_id TEXT PRIMARY KEY,summary TEXT NOT NULL,evidence_url TEXT,submitted_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS reviews(order_id TEXT PRIMARY KEY,rating INTEGER NOT NULL,comment TEXT NOT NULL,at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS disputes(id TEXT PRIMARY KEY,order_id TEXT NOT NULL UNIQUE,reason TEXT NOT NULL,details TEXT NOT NULL,status TEXT NOT NULL,prior_state TEXT NOT NULL,outcome TEXT,created_at TEXT NOT NULL,resolved_at TEXT,resolution TEXT);
    CREATE TABLE IF NOT EXISTS notifications(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,role TEXT NOT NULL,type TEXT NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,order_id TEXT,created_at TEXT NOT NULL,read_at TEXT);
    CREATE TABLE IF NOT EXISTS member_invitations(code_hash TEXT PRIMARY KEY,player_id TEXT NOT NULL,expires_at INTEGER NOT NULL,used_at TEXT,used_by TEXT);
    CREATE INDEX IF NOT EXISTS event_order ON order_events(order_id,at);
    CREATE INDEX IF NOT EXISTS notifications_user ON notifications(user_id,created_at);
    CREATE INDEX IF NOT EXISTS assigned_orders ON orders(assigned_player_id,fulfillment_status);
    CREATE UNIQUE INDEX IF NOT EXISTS production_member ON users(player_id) WHERE wechat_openid IS NOT NULL AND player_id IS NOT NULL;
    UPDATE orders SET fulfillment_status=CASE WHEN status='cancelled' THEN 'cancelled' WHEN status='completed' THEN 'completed' WHEN demo=0 AND payment_status!='paid' THEN 'awaiting_payment' ELSE 'awaiting_assignment' END WHERE fulfillment_status IS NULL;`);
  const transaction=fn=>{db.exec('BEGIN IMMEDIATE');try{const result=fn();db.exec('COMMIT');return result;}catch(error){db.exec('ROLLBACK');throw error;}};
  const availability=createAvailability({db,fail,findPlayer:id=>entry('players',id),mode:config.mode});
  transaction(()=>availability.seed(catalog('players')));
  const ledger=createLedger({db,fail,now});
  const system={role:'system',name:'俱乐部系统'},owner={role:'owner',name:'俱乐部运营'};
  const clean=(value,label,max,required=true)=>{if(!required&&(value===undefined||value===null))return '';if(typeof value!=='string'||value.length>max||(required&&!value.trim()))throw fail(400,'VALIDATION',`${label}须填写且不超过 ${max} 字符。`);return value.trim();};
  const user=id=>{const result=db.prepare('SELECT * FROM users WHERE id=?').get(id);if(!result)throw fail(401,'UNAUTHORIZED','账号不存在。');return result;};
  const member=id=>{const result=user(id);if(result.role!=='member'||!result.player_id||!entry('players',result.player_id))throw fail(403,'MEMBER_REQUIRED','仅已绑定的俱乐部成员可操作。');return result;};
  const actor=(userId,role)=>{const account=user(userId);return {role:role||account.role,name:account.role==='member'?(entry('players',account.player_id)?.name||account.name):account.name};};
  const order=id=>{const row=db.prepare('SELECT * FROM orders WHERE id=?').get(id);if(!row)throw fail(404,'NOT_FOUND','订单不存在。');return row;};
  const ownOrder=(id,userId)=>{const row=order(id);if(row.user_id!==userId)throw fail(404,'NOT_FOUND','订单不存在。');return row;};
  const memberOrder=(id,userId)=>{const account=member(userId),row=order(id);if(row.assigned_player_id!==account.player_id)throw fail(404,'NOT_FOUND','订单未分配给你。');return row;};
  const event=(orderId,type,by,message)=>db.prepare('INSERT INTO order_events VALUES(?,?,?,?,?,?,?)').run(randomUUID(),orderId,type,iso(),by.role,by.name,message);
  function notify(userId,role,type,title,body,orderId){db.prepare('INSERT INTO notifications VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(),userId,role,type,title,body,orderId||null,iso(),null);}
  function notifyMember(playerId,type,title,message,orderId){for(const account of db.prepare("SELECT id FROM users WHERE role='member' AND player_id=?").all(playerId))notify(account.id,'member',type,title,message,orderId);}
  const state=(row,next)=>db.prepare('UPDATE orders SET fulfillment_status=?,status=? WHERE id=?').run(next,next==='completed'?'completed':next==='cancelled'?'cancelled':['scheduled','in_progress','awaiting_confirmation','disputed'].includes(next)?'confirmed':'pending',row.id);
  function requireState(row,states){if(!states.includes(row.fulfillment_status))throw fail(409,'INVALID_FULFILLMENT_STATE','订单状态已变化，请刷新后重试。');}
  function requirePaid(row){if(!row.demo&&row.payment_status!=='paid')throw fail(409,'PAYMENT_REQUIRED','真实付款确认后才能安排或完成服务。');}
  function view(row){
    const delivery=db.prepare('SELECT * FROM deliveries WHERE order_id=?').get(row.id),review=db.prepare('SELECT * FROM reviews WHERE order_id=?').get(row.id),dispute=db.prepare('SELECT * FROM disputes WHERE order_id=?').get(row.id);
    return {fulfillmentStatus:row.fulfillment_status,assignedPlayerId:row.assigned_player_id,commissionBps:row.commission_bps,memberCents:row.member_cents,clubCents:row.club_cents,durationMinutes:row.duration_minutes,acceptBy:row.accept_by,paymentExpiresAt:row.payment_expires_at,serviceSnapshot:row.service_snapshot?JSON.parse(row.service_snapshot):null,
      events:db.prepare('SELECT * FROM order_events WHERE order_id=? ORDER BY rowid').all(row.id).map(item=>({id:item.id,type:item.type,at:item.at,actor:{role:item.actor_role,name:item.actor_name},message:item.message})),
      delivery:delivery?{summary:delivery.summary,evidenceUrl:delivery.evidence_url||null,submittedAt:delivery.submitted_at}:null,
      review:review?{rating:review.rating,comment:review.comment,at:review.at}:null,
      dispute:dispute?{id:dispute.id,reason:dispute.reason,details:dispute.details,status:dispute.status,outcome:dispute.outcome,createdAt:dispute.created_at,resolvedAt:dispute.resolved_at,resolution:dispute.resolution}:null};
  }
  function created(row,service){
    const next=row.demo?'awaiting_assignment':'awaiting_payment';
    db.prepare('UPDATE orders SET fulfillment_status=?,duration_minutes=?,service_game=?,payment_expires_at=?,service_snapshot=? WHERE id=?').run(next,service.durationMinutes,service.game,new Date(now()+30*60000).toISOString(),JSON.stringify(service),row.id);
    event(row.id,'created',actor(row.user_id,'customer'),row.demo?'已提交演示预约，不产生真实付款。':'已创建预约，请在 30 分钟内付款。');
    notify(row.user_id,'customer','order_created','预约已提交',row.demo?'俱乐部将安排服务成员。':'请完成付款，付款后安排服务成员。',row.id);
  }
  function paid(row){if(row.fulfillment_status==='awaiting_payment'){state(row,'awaiting_assignment');event(row.id,'paid',system,'微信已确认付款，等待俱乐部派单。');notify(row.user_id,'customer','payment_confirmed','付款已确认','俱乐部将安排服务成员。',row.id);}}
  function cancelled(row,by=system,message='预约已取消。'){requireState(row,['awaiting_payment','awaiting_assignment','awaiting_acceptance','scheduled']);state(row,'cancelled');db.prepare('UPDATE orders SET accept_by=NULL WHERE id=?').run(row.id);event(row.id,'cancelled',by,message);notify(row.user_id,'customer','order_cancelled','预约已取消',message,row.id);if(row.assigned_player_id)notifyMember(row.assigned_player_id,'order_cancelled','预约已取消',message,row.id);}
  function refundStarted(row){ledger.hold(row.id);event(row.id,'refund_requested',owner,'已提交全额退款申请，款项与成员收入暂时冻结。');}
  function refunded(row){ledger.reverse(row.id);state(row,'cancelled');db.prepare("UPDATE disputes SET status='resolved',outcome='refund',resolved_at=? WHERE order_id=? AND status='open'").run(iso(),row.id);event(row.id,'refunded',system,'微信已确认全额退款，服务取消，成员可结算收入已撤销。');notify(row.user_id,'customer','refund_completed','退款已完成','全额退款已由微信确认。',row.id);if(row.assigned_player_id)notifyMember(row.assigned_player_id,'refund_completed','订单已退款','该订单收入已撤销，请查看收入明细。',row.id);}
  function refundClosed(row){if(row.fulfillment_status==='completed'&&!db.prepare("SELECT id FROM disputes WHERE order_id=? AND status='open'").get(row.id))ledger.available(row);event(row.id,'refund_closed',system,'退款申请已关闭，请运营核实后处理。');}
  function tick(){
    const expired=db.prepare("SELECT * FROM orders WHERE fulfillment_status='awaiting_acceptance' AND accept_by IS NOT NULL AND accept_by<=?").all(iso());
    if(!expired.length)return;
    transaction(()=>{for(const row of expired){state(row,'awaiting_assignment');db.prepare('UPDATE orders SET assigned_player_id=NULL,accept_by=NULL WHERE id=?').run(row.id);event(row.id,'acceptance_expired',system,'成员未在规定时间接单，已释放时段并返回待派队列。');notifyMember(row.assigned_player_id,'acceptance_expired','接单时限已过','预约已返回运营待派队列。',row.id);notify(row.user_id,'customer','reassignment_needed','正在重新安排成员','原成员未及时接单，俱乐部将重新安排。',row.id);}});
  }
  function me(userId){const account=user(userId);return {user:{id:account.id,name:account.name},role:account.role,playerId:account.player_id||null,demo:config.mode==='demo'};}
  function rename(userId,name){db.prepare('UPDATE users SET name=? WHERE id=?').run(clean(name,'昵称',40),userId);return me(userId);}
  function demoRole(userId,role,playerId){
    if(config.mode!=='demo')throw fail(403,'DEMO_DISABLED','生产环境禁止演示角色切换。');
    if(!['customer','member'].includes(role))throw fail(400,'VALIDATION','角色须为 customer 或 member。');
    if(role==='member'&&!entry('players',playerId))throw fail(400,'INVALID_PLAYER','请选择有效的演示成员。');
    db.prepare('UPDATE users SET role=?,player_id=? WHERE id=?').run(role,role==='member'?playerId:null,userId);return me(userId);
  }
  function invite(playerId){
    if(!entry('players',playerId))throw fail(404,'NOT_FOUND','成员不存在。');
    if(db.prepare("SELECT id FROM users WHERE player_id=? AND (wechat_openid IS NOT NULL OR EXISTS(SELECT 1 FROM phone_identities p WHERE p.user_id=users.id AND p.verification_source='tencent'))").get(playerId))throw fail(409,'MEMBER_ALREADY_BOUND','该成员已有绑定账号。');
    const code=randomBytes(24).toString('base64url'),expiresAt=now()+60*60000;
    db.prepare('DELETE FROM member_invitations WHERE player_id=? AND used_at IS NULL').run(playerId);
    db.prepare('INSERT INTO member_invitations VALUES(?,?,?,?,?)').run(createHash('sha256').update(code).digest('hex'),playerId,expiresAt,null,null);
    return {code,playerId,expiresAt:new Date(expiresAt).toISOString(),singleUse:true};
  }
  function acceptInvitation(userId,code){return transaction(()=>{
    const digest=createHash('sha256').update(clean(code,'邀请码',128)).digest('hex'),invitation=db.prepare('SELECT * FROM member_invitations WHERE code_hash=?').get(digest);
    if(!invitation||invitation.used_at||invitation.expires_at<=now())throw fail(400,'INVITATION_INVALID','邀请码无效、已使用或已过期。');
    if(!entry('players',invitation.player_id))throw fail(409,'MEMBER_UNAVAILABLE','该成员已归档。');
    const account=user(userId);if(account.role==='member'&&account.player_id!==invitation.player_id)throw fail(409,'ALREADY_A_MEMBER','账号已绑定另一位成员。');
    if(db.prepare("SELECT id FROM users WHERE player_id=? AND (wechat_openid IS NOT NULL OR EXISTS(SELECT 1 FROM phone_identities p WHERE p.user_id=users.id AND p.verification_source='tencent')) AND id!=?").get(invitation.player_id,userId))throw fail(409,'MEMBER_ALREADY_BOUND','该成员已有绑定账号。');
    db.prepare("UPDATE users SET role='member',player_id=? WHERE id=?").run(invitation.player_id,userId);
    db.prepare('UPDATE member_invitations SET used_at=?,used_by=? WHERE code_hash=? AND used_at IS NULL').run(iso(),userId,digest);
    notify(userId,'member','membership_bound','欢迎加入俱乐部','你的成员身份已绑定，可以设置可接时段。');return me(userId);
  });}
  function assign(id,data){return transaction(()=>{
    const row=order(id);requireState(row,['awaiting_assignment','awaiting_acceptance','scheduled']);requirePaid(row);
    const playerId=clean(data.playerId,'成员',64),player=entry('players',playerId),game=row.service_game||entry('services',row.service_id,true)?.game;
    if(!player||!player.games.includes(game))throw fail(400,'INVALID_PLAYER','该成员不提供此游戏的服务。');
    const rate=data.commissionBps===undefined?(clubData().commissionBps??2000):data.commissionBps;
    if(!Number.isInteger(rate)||rate<0||rate>10000)throw fail(400,'VALIDATION','抽成比例须为 0 至 10000 基点的整数。');
    const reason=clean(data.reason,'派单说明',500,false);
    if(row.assigned_player_id&&!reason)throw fail(400,'REASSIGN_REASON_REQUIRED','更换已指派成员时请填写原因。');
    if(Date.parse(row.scheduled_at)<now())throw fail(409,'SCHEDULE_PASSED','预约时段已开始，请联系客户重新预约。');
    availability.assertBookable(playerId,row.scheduled_at,row.duration_minutes,row.id);
    const clubCents=Math.floor(row.price_cents*rate/10000),memberCents=row.price_cents-clubCents,acceptBy=new Date(Math.min(now()+15*60000,Date.parse(row.scheduled_at))).toISOString();
    state(row,'awaiting_acceptance');db.prepare('UPDATE orders SET assigned_player_id=?,commission_bps=?,club_cents=?,member_cents=?,accept_by=? WHERE id=?').run(playerId,rate,clubCents,memberCents,acceptBy,row.id);
    event(row.id,row.assigned_player_id?'reassigned':'assigned',owner,`已指派 ${player.name}，等待接单。${reason}`);
    notifyMember(playerId,'order_assigned','有一条预约等待接单',`${row.service_title}，预计成员收入 ¥${(memberCents/100).toFixed(2)}。`,row.id);
    if(row.assigned_player_id&&row.assigned_player_id!==playerId)notifyMember(row.assigned_player_id,'order_reassigned','预约已改派',reason,row.id);
    notify(row.user_id,'customer','member_assigned','已安排服务成员',`${player.name} 正在确认你的预约。`,row.id);return order(row.id);
  });}
  function memberAction(id,userId,action,data={}){return transaction(()=>{
    const row=memberOrder(id,userId),by=actor(userId,'member');requirePaid(row);
    if(action==='accept'){
      if(row.fulfillment_status==='scheduled')return row;requireState(row,['awaiting_acceptance']);
      if(Date.parse(row.accept_by)<=now())throw fail(409,'ACCEPTANCE_EXPIRED','接单时限已过。');
      availability.assertBookable(row.assigned_player_id,row.scheduled_at,row.duration_minutes,row.id);state(row,'scheduled');db.prepare('UPDATE orders SET accept_by=NULL WHERE id=?').run(row.id);event(row.id,'accepted',by,'成员已接单，预约时间已锁定。');notify(row.user_id,'customer','member_accepted','成员已接单','请按预约时间集合。',row.id);
    }else if(action==='decline'){
      requireState(row,['awaiting_acceptance']);const reason=clean(data.reason,'拒单原因',500);state(row,'awaiting_assignment');db.prepare('UPDATE orders SET assigned_player_id=NULL,accept_by=NULL WHERE id=?').run(row.id);event(row.id,'declined',by,`成员无法接单：${reason}`);notify(row.user_id,'customer','member_declined','正在重新安排成员','俱乐部将为你重新安排。',row.id);
    }else if(action==='start'){
      if(row.fulfillment_status==='in_progress')return row;requireState(row,['scheduled']);
      if(now()<Date.parse(row.scheduled_at)-15*60000)throw fail(409,'TOO_EARLY','开始前 15 分钟内才可开始服务。');
      state(row,'in_progress');event(row.id,'started',by,'成员已开始服务。');notify(row.user_id,'customer','service_started','服务已开始','服务结束后请确认交付或提出问题。',row.id);
    }else if(action==='submit'){
      if(row.fulfillment_status==='awaiting_confirmation')return row;requireState(row,['in_progress']);const summary=clean(data.summary,'交付说明',3000),evidence=clean(data.evidenceUrl,'凭据地址',2048,false);
      if(evidence){let url;try{url=new URL(evidence);}catch{throw fail(400,'VALIDATION','凭据须为 HTTPS 地址。');}if(url.protocol!=='https:'||url.username||url.password)throw fail(400,'VALIDATION','凭据须为 HTTPS 地址，不含登录凭证。');}
      db.prepare('INSERT INTO deliveries VALUES(?,?,?,?)').run(row.id,summary,evidence||null,iso());ledger.ensure(row);state(row,'awaiting_confirmation');event(row.id,'delivery_submitted',by,summary);notify(row.user_id,'customer','delivery_submitted','服务记录已提交','请查看交付说明，确认完成或发起争议。',row.id);
    }else throw fail(404,'NOT_FOUND','成员操作不存在。');
    return order(row.id);
  });}
  function confirm(id,userId,data){return transaction(()=>{
    const row=ownOrder(id,userId);if(row.fulfillment_status==='completed')return row;requireState(row,['awaiting_confirmation']);requirePaid(row);
    if(!Number.isInteger(data.rating)||data.rating<1||data.rating>5)throw fail(400,'VALIDATION','评分须为 1 至 5。');
    const comment=clean(data.comment,'评价',1000,false);db.prepare('INSERT INTO reviews VALUES(?,?,?,?)').run(row.id,data.rating,comment,iso());state(row,'completed');ledger.available(row);event(row.id,'confirmed',actor(userId,'customer'),'客户已确认交付，成员收入转为可结算。');notifyMember(row.assigned_player_id,'order_completed','客户已确认完成','本单收入已转为可结算，请查看收入明细。',row.id);return order(row.id);
  });}
  function dispute(id,userId,data){return transaction(()=>{
    const row=ownOrder(id,userId),existing=db.prepare('SELECT * FROM disputes WHERE order_id=?').get(id);
    if(existing?.status==='open')return row;requireState(row,['scheduled','in_progress','awaiting_confirmation','completed']);
    if(existing)throw fail(409,'DISPUTE_ALREADY_RESOLVED','该订单的争议已处理，请联系俱乐部客服。');
    const reason=clean(data.reason,'争议原因',120),details=clean(data.details,'问题详情',3000,false);ledger.hold(row.id);
    db.prepare('INSERT INTO disputes VALUES(?,?,?,?,?,?,?,?,?,?)').run(randomUUID(),row.id,reason,details,'open',row.fulfillment_status,null,iso(),null,null);
    state(row,'disputed');event(row.id,'disputed',actor(userId,'customer'),reason);notifyMember(row.assigned_player_id,'dispute_opened','订单进入售后处理','相关收入已冻结，等待运营核实。',row.id);return order(row.id);
  });}
  function resume(id,reason){return transaction(()=>{
    const row=order(id),dispute=db.prepare("SELECT * FROM disputes WHERE order_id=? AND status='open'").get(id);if(!dispute)throw fail(409,'NO_OPEN_DISPUTE','没有待处理争议。');
    if(['refund_pending','refunded'].includes(row.payment_status))throw fail(409,'REFUND_IN_PROGRESS','退款已开始，不能恢复服务。');
    const message=clean(reason,'处理说明',1000);state(row,dispute.prior_state);db.prepare("UPDATE disputes SET status='resolved',outcome='resume',resolved_at=?,resolution=? WHERE order_id=?").run(iso(),message,id);
    if(dispute.prior_state==='completed')ledger.available(row);event(id,'dispute_resolved',owner,`争议处理：恢复原流程。${message}`);notify(row.user_id,'customer','dispute_resolved','售后处理结果已更新',message,id);notifyMember(row.assigned_player_id,'dispute_resolved','售后处理结果已更新',message,id);return order(id);
  });}
  function demoRefund(id,reason){return transaction(()=>{const row=order(id);if(config.mode!=='demo'||!row.demo)throw fail(403,'DEMO_DISABLED','仅可处理演示订单。');ledger.reverse(id);state(row,'cancelled');db.prepare("UPDATE disputes SET status='resolved',outcome='refund',resolved_at=?,resolution=? WHERE order_id=?").run(iso(),reason,id);event(id,'demo_refund',owner,'演示售后已撤销预约与收入；没有发生真实退款。'+reason);notify(row.user_id,'customer','demo_refund','演示售后已处理','预约已撤销，没有发生真实付款或退款。',id);return order(id);});}
  function overview(){const rows=db.prepare('SELECT * FROM orders').all(),counts={awaitingAssignment:0,awaitingAcceptance:0,inProgress:0,awaitingConfirmation:0,disputed:0,paymentOverdue:0,unsettled:ledger.list().filter(row=>row.state==='available').length};const mapping={awaiting_assignment:'awaitingAssignment',awaiting_acceptance:'awaitingAcceptance',in_progress:'inProgress',awaiting_confirmation:'awaitingConfirmation',disputed:'disputed'};for(const row of rows){if(mapping[row.fulfillment_status])counts[mapping[row.fulfillment_status]]++;if(row.fulfillment_status==='awaiting_payment'&&Date.parse(row.payment_expires_at)<=now())counts.paymentOverdue++;}return {counts,totals:{orderCount:rows.length,grossCents:rows.reduce((n,row)=>n+row.price_cents,0),paidCents:rows.filter(row=>row.payment_status==='paid').reduce((n,row)=>n+row.price_cents,0),refundedCents:rows.filter(row=>row.payment_status==='refunded').reduce((n,row)=>n+row.price_cents,0),memberAvailableCents:ledger.summary().totals.availableCents},demo:config.mode==='demo'};}
  return {db,now,iso,transaction,availability,ledger,owner,actor,user,member,order,ownOrder,memberOrder,event,notify,notifyMember,view,created,paid,cancelled,refundStarted,refunded,refundClosed,tick,me,rename,demoRole,invite,acceptInvitation,assign,memberAction,confirm,dispute,resume,demoRefund,overview,clean,
    notifications:userId=>db.prepare('SELECT * FROM notifications WHERE user_id=? ORDER BY rowid DESC LIMIT 100').all(userId).map(row=>({id:row.id,role:row.role,type:row.type,title:row.title,body:row.body,orderId:row.order_id,createdAt:row.created_at,readAt:row.read_at})),
    readNotification:(id,userId)=>{const result=db.prepare('UPDATE notifications SET read_at=COALESCE(read_at,?) WHERE id=? AND user_id=?').run(iso(),id,userId);if(!result.changes)throw fail(404,'NOT_FOUND','通知不存在。');return {id,read:true};},
    memberOrders:userId=>{const account=member(userId);return db.prepare('SELECT * FROM orders WHERE assigned_player_id=? ORDER BY scheduled_at').all(account.player_id);},
    memberMe:userId=>{const account=member(userId);return {...me(userId),player:entry('players',account.player_id)};},
    disputes:()=>db.prepare("SELECT orders.* FROM orders JOIN disputes ON disputes.order_id=orders.id WHERE disputes.status='open' ORDER BY disputes.created_at").all(),
    expiredPayments:()=>db.prepare("SELECT * FROM orders WHERE fulfillment_status='awaiting_payment' AND payment_expires_at<=? LIMIT 50").all(iso())};
}
