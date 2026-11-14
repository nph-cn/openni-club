import {randomUUID} from 'node:crypto';

const DAY=86400000;
export function createAvailability({db,fail,findPlayer,mode}) {
  db.exec(`CREATE TABLE IF NOT EXISTS availability(id TEXT PRIMARY KEY,player_id TEXT NOT NULL,start_at INTEGER NOT NULL,end_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS availability_player ON availability(player_id,start_at,end_at);`);
  const list=playerId=>db.prepare('SELECT start_at,end_at FROM availability WHERE player_id=? AND end_at>? ORDER BY start_at').all(playerId,Date.now()).map(row=>({startAt:new Date(row.start_at).toISOString(),endAt:new Date(row.end_at).toISOString()}));
  const reserved=playerId=>db.prepare("SELECT id,scheduled_at,duration_minutes FROM orders WHERE assigned_player_id=? AND fulfillment_status IN ('awaiting_acceptance','scheduled','in_progress','awaiting_confirmation','disputed')").all(playerId);
  function covered(playerId,start,end,slots){
    const ranges=slots||list(playerId);
    return ranges.some(slot=>Date.parse(slot.startAt)<=start&&Date.parse(slot.endAt)>=end);
  }
  function assertBookable(playerId,startAt,durationMinutes,excludeOrderId){
    if(!findPlayer(playerId))throw fail(400,'INVALID_PLAYER','成员不存在或已归档。');
    const start=Date.parse(startAt),end=start+durationMinutes*60000;
    if(!covered(playerId,start,end))throw fail(409,'OUTSIDE_AVAILABILITY','该成员未开放此时段，请选择已开放时段。');
    if(reserved(playerId).some(order=>order.id!==excludeOrderId&&Date.parse(order.scheduled_at)<end&&Date.parse(order.scheduled_at)+order.duration_minutes*60000>start))throw fail(409,'SCHEDULE_CONFLICT','该成员在此时段已有预约，请选择其他成员或时间。');
  }
  function update(playerId,input){
    if(!findPlayer(playerId))throw fail(404,'NOT_FOUND','成员不存在。');
    if(!Array.isArray(input)||input.length>200)throw fail(400,'VALIDATION','最多设置 200 个可接时段。');
    const existing=new Set(list(playerId).map(slot=>Date.parse(slot.startAt)+':'+Date.parse(slot.endAt)));
    const slots=input.map(slot=>{
      if(!slot||typeof slot!=='object')throw fail(400,'INVALID_AVAILABILITY','时段须包含开始和结束时间。');
      const start=Date.parse(slot.startAt),end=Date.parse(slot.endAt);
      const retained=existing.has(start+':'+end)&&end>Date.now();
      if(!Number.isFinite(start)||!Number.isFinite(end)||(!retained&&start<Date.now()-60000)||end<=start||end-start<15*60000||end-start>24*3600000||end>Date.now()+90*DAY)throw fail(400,'INVALID_AVAILABILITY','新增时段须从现在起，持续 15 分钟至 24 小时，并在未来 90 天内；已开始的原时段可保留。');
      return {startAt:new Date(start).toISOString(),endAt:new Date(end).toISOString()};
    }).sort((a,b)=>Date.parse(a.startAt)-Date.parse(b.startAt));
    for(let i=1;i<slots.length;i++)if(Date.parse(slots[i].startAt)<Date.parse(slots[i-1].endAt))throw fail(400,'OVERLAPPING_AVAILABILITY','开放时段不能重叠。');
    for(const order of reserved(playerId)){
      const start=Date.parse(order.scheduled_at),end=start+order.duration_minutes*60000;
      if(end>Date.now()&&!covered(playerId,start,end,slots))throw fail(409,'RESERVED_AVAILABILITY','该时段已有待接或进行中的订单，不能直接移除。');
    }
    db.prepare('DELETE FROM availability WHERE player_id=?').run(playerId);
    for(const slot of slots)db.prepare('INSERT INTO availability VALUES(?,?,?,?)').run(randomUUID(),playerId,Date.parse(slot.startAt),Date.parse(slot.endAt));
    return {playerId,timezone:'Asia/Shanghai',slots};
  }
  function publicSlots(playerId,date,durationMinutes=60){
    if(!findPlayer(playerId))throw fail(404,'NOT_FOUND','成员不存在。');
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isInteger(durationMinutes)||durationMinutes<15||durationMinutes>720)throw fail(400,'VALIDATION','请提供有效日期与服务时长。');
    const day=Date.parse(date+'T00:00:00+08:00');
    if(!Number.isFinite(day)||new Date(day+8*3600000).toISOString().slice(0,10)!==date)throw fail(400,'VALIDATION','日期无效。');
    const booked=reserved(playerId),slots=[],step=30*60000;
    for(const range of list(playerId)){
      const start=Math.max(day,Date.parse(range.startAt)),end=Math.min(day+DAY,Date.parse(range.endAt));
      for(let at=Math.ceil(start/step)*step;at+durationMinutes*60000<=end;at+=step){
        if(at<Date.now()+60000)continue;
        const until=at+durationMinutes*60000;
        const busy=booked.some(order=>Date.parse(order.scheduled_at)<until&&Date.parse(order.scheduled_at)+order.duration_minutes*60000>at);
        slots.push({startAt:new Date(at).toISOString(),endAt:new Date(until).toISOString(),available:!busy,busy});
      }
    }
    return {playerId,date,timezone:'Asia/Shanghai',durationMinutes,slots};
  }
  function seed(players){
    if(mode!=='demo'||db.prepare("SELECT value FROM metadata WHERE key='availability_initialized'").get())return;
    const localDate=new Date(Date.now()+8*3600000).toISOString().slice(0,10),midnight=Date.parse(localDate+'T00:00:00+08:00');
    for(const player of players)for(let day=0;day<14;day++)db.prepare('INSERT INTO availability VALUES(?,?,?,?)').run(randomUUID(),player.id,midnight+day*DAY,midnight+(day+1)*DAY);
    db.prepare('INSERT INTO metadata VALUES(?,?)').run('availability_initialized','true');
  }
  return {list,update,publicSlots,assertBookable,seed};
}
