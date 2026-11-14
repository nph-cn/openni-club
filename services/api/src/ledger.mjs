import {randomUUID} from 'node:crypto';

export function createLedger({db,fail,now=Date.now}) {
  db.exec(`CREATE TABLE IF NOT EXISTS earnings(id TEXT PRIMARY KEY,order_id TEXT NOT NULL UNIQUE,player_id TEXT NOT NULL,gross_cents INTEGER NOT NULL,club_cents INTEGER NOT NULL,member_cents INTEGER NOT NULL,state TEXT NOT NULL,created_at TEXT NOT NULL,available_at TEXT,settled_at TEXT,settlement_id TEXT,demo INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS settlements(id TEXT PRIMARY KEY,payment_reference TEXT NOT NULL,note TEXT NOT NULL,created_at TEXT NOT NULL,member_cents INTEGER NOT NULL,demo INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS earnings_player ON earnings(player_id,state);`);
  const view=row=>({id:row.id,orderId:row.order_id,playerId:row.player_id,grossCents:row.gross_cents,clubCents:row.club_cents,memberCents:row.member_cents,state:row.state,createdAt:row.created_at,availableAt:row.available_at,settledAt:row.settled_at,settlementId:row.settlement_id,demo:Boolean(row.demo)});
  function ensure(order){
    if(!order.assigned_player_id)throw fail(409,'NO_ASSIGNEE','订单尚未分配成员。');
    db.prepare("INSERT OR IGNORE INTO earnings(id,order_id,player_id,gross_cents,club_cents,member_cents,state,created_at,demo) VALUES(?,?,?,?,?,?,'held',?,?)").run(randomUUID(),order.id,order.assigned_player_id,order.price_cents,order.club_cents,order.member_cents,new Date(now()).toISOString(),order.demo);
  }
  function hold(orderId){
    if(db.prepare("SELECT id FROM earnings WHERE order_id=? AND state='settled'").get(orderId))throw fail(409,'ALREADY_SETTLED','成员款项已记录结算，须先人工核实追回，不可直接发起退款或争议冻结。');
    db.prepare("UPDATE earnings SET state='held',available_at=NULL WHERE order_id=? AND state='available'").run(orderId);
  }
  function available(order){ensure(order);db.prepare("UPDATE earnings SET state='available',available_at=? WHERE order_id=? AND state='held'").run(new Date(now()).toISOString(),order.id);}
  function reverse(orderId){hold(orderId);db.prepare("UPDATE earnings SET state='reversed',available_at=NULL WHERE order_id=? AND state!='settled'").run(orderId);}
  function list(playerId){return db.prepare(`SELECT * FROM earnings ${playerId?'WHERE player_id=?':''} ORDER BY created_at DESC`).all(...(playerId?[playerId]:[])).map(view);}
  function summary(playerId){const entries=list(playerId),totals={heldCents:0,availableCents:0,settledCents:0,reversedCents:0};for(const entry of entries)totals[entry.state+'Cents']+=entry.memberCents;return {entries,totals,currency:'CNY'};}
  function settlementView(row){return {id:row.id,paymentReference:row.payment_reference,note:row.note,createdAt:row.created_at,memberCents:row.member_cents,entryIds:db.prepare('SELECT id FROM earnings WHERE settlement_id=? ORDER BY id').all(row.id).map(item=>item.id),demo:Boolean(row.demo),moneyTransferred:false,recordType:'manual_payment_record'};}
  function settle(data){
    if(!Array.isArray(data.entryIds)||data.entryIds.length<1||data.entryIds.length>100||new Set(data.entryIds).size!==data.entryIds.length||data.entryIds.some(id=>typeof id!=='string'))throw fail(400,'VALIDATION','请选择 1 至 100 条不同账目。');
    if(typeof data.paymentReference!=='string'||data.paymentReference.trim().length<3||data.paymentReference.length>200)throw fail(400,'VALIDATION','填写实际付款凭据编号，3 至 200 字符。');
    if(data.note!==undefined&&(typeof data.note!=='string'||data.note.length>500))throw fail(400,'VALIDATION','备注不得超过 500 字符。');
    const rows=data.entryIds.map(id=>db.prepare('SELECT * FROM earnings WHERE id=?').get(id));
    if(rows.some(row=>!row))throw fail(404,'NOT_FOUND','账目不存在。');
    const previous=rows[0].settlement_id;
    if(previous&&rows.every(row=>row.settlement_id===previous)){
      const existing=settlementView(db.prepare('SELECT * FROM settlements WHERE id=?').get(previous));
      if(existing.paymentReference===data.paymentReference.trim()&&existing.entryIds.length===rows.length)return existing;
      throw fail(409,'SETTLEMENT_CONFLICT','这些账目已有结算记录，不可重复记录。');
    }
    for(const row of rows){
      const order=db.prepare('SELECT * FROM orders WHERE id=?').get(row.order_id);
      const dispute=db.prepare("SELECT id FROM disputes WHERE order_id=? AND status='open'").get(row.order_id);
      if(row.state!=='available'||order.fulfillment_status!=='completed'||dispute||(!order.demo&&order.payment_status!=='paid'))throw fail(409,'NOT_SETTLEABLE','存在冻结、未完成、已结算或退款中的账目。');
    }
    if(rows.some(row=>row.demo!==rows[0].demo))throw fail(409,'MIXED_ENVIRONMENT','演示和真实账目不能混合结算。');
    const row={id:randomUUID(),payment_reference:data.paymentReference.trim(),note:(data.note||'').trim(),created_at:new Date(now()).toISOString(),member_cents:rows.reduce((sum,item)=>sum+item.member_cents,0),demo:rows[0].demo};
    db.prepare('INSERT INTO settlements VALUES(?,?,?,?,?,?)').run(row.id,row.payment_reference,row.note,row.created_at,row.member_cents,row.demo);
    for(const entry of rows)db.prepare("UPDATE earnings SET state='settled',settled_at=?,settlement_id=? WHERE id=? AND state='available'").run(row.created_at,row.id,entry.id);
    return settlementView(row);
  }
  function csv(){const escape=value=>{let text=String(value??'');if(/^[=+@\-\t\r]/.test(text))text="'"+text;return '"'+text.replaceAll('"','""')+'"';};return '\uFEFF'+[['entry_id','order_id','player_id','gross_cents','club_cents','member_cents','state','settlement_id'],...list().map(row=>[row.id,row.orderId,row.playerId,row.grossCents,row.clubCents,row.memberCents,row.state,row.settlementId])].map(row=>row.map(escape).join(',')).join('\r\n');}
  return {ensure,hold,available,reverse,list,summary,settle,csv,settlements:()=>db.prepare('SELECT * FROM settlements ORDER BY created_at DESC').all().map(settlementView)};
}
