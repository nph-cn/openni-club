export function createOperationsRoutes({ops,config,authenticate,body,send,orderView,fail,requestRefund,cancelOrder,catalog}) {
  return async function handle(req,res,route,url){
    const respond=(value,status=200)=>{send(res,status,value);return true;};
    const method=req.method;
    if(route==='/me'){
      const userId=authenticate(req);
      if(method==='GET')return respond(ops.me(userId));
      if(method==='PATCH')return respond(ops.rename(userId,(await body(req)).name));
    }
    if(route==='/auth/demo/role'&&method==='POST'){
      const userId=authenticate(req),data=await body(req);return respond(ops.demoRole(userId,data.role,data.playerId));
    }
    if(route==='/member/invitation/accept'&&method==='POST')return respond(ops.acceptInvitation(authenticate(req),(await body(req)).code));
    if(route==='/notifications'&&method==='GET')return respond(ops.notifications(authenticate(req)));
    const notification=/^\/notifications\/([^/]+)\/read$/.exec(route);
    if(notification&&method==='PATCH')return respond(ops.readNotification(notification[1],authenticate(req)));
    const publicAvailability=/^\/players\/([^/]+)\/availability$/.exec(route);
    if(publicAvailability&&method==='GET')return respond(ops.availability.publicSlots(publicAvailability[1],url.searchParams.get('date')||new Date(Date.now()+8*3600000).toISOString().slice(0,10),Number(url.searchParams.get('durationMinutes')||60)));
    const customerAction=/^\/orders\/([^/]+)\/(confirm|dispute)$/.exec(route);
    if(customerAction&&method==='POST'){
      const userId=authenticate(req),data=await body(req);
      return respond(orderView(customerAction[2]==='confirm'?ops.confirm(customerAction[1],userId,data):ops.dispute(customerAction[1],userId,data)));
    }
    if(route.startsWith('/member/')){
      const userId=authenticate(req),member=ops.member(userId);
      if(route==='/member/me'&&method==='GET')return respond(ops.memberMe(userId));
      if(route==='/member/orders'&&method==='GET')return respond(ops.memberOrders(userId).map(orderView));
      const memberDetail=/^\/member\/orders\/([^/]+)$/.exec(route);
      if(memberDetail&&method==='GET')return respond(orderView(ops.memberOrder(memberDetail[1],userId)));
      if(route==='/member/availability'){
        if(method==='GET')return respond({playerId:member.player_id,timezone:'Asia/Shanghai',slots:ops.availability.list(member.player_id)});
        if(method==='PUT'){const data=await body(req);return respond(ops.transaction(()=>ops.availability.update(member.player_id,data.slots)));}
      }
      if(route==='/member/earnings'&&method==='GET'){
        const result=ops.ledger.summary(member.player_id),ids=new Set(result.entries.map(row=>row.settlementId).filter(Boolean));
        const records=ops.ledger.settlements().filter(row=>ids.has(row.id)).map(record=>{const own=result.entries.filter(entry=>entry.settlementId===record.id);return {...record,entryIds:own.map(entry=>entry.id),memberCents:own.reduce((sum,entry)=>sum+entry.memberCents,0)};});
        return respond({...result,settlements:records,demo:config.mode==='demo'});
      }
      const action=/^\/member\/orders\/([^/]+)\/(accept|decline|start|submit)$/.exec(route);
      if(action&&method==='POST')return respond(orderView(ops.memberAction(action[1],userId,action[2],await body(req))));
    }
    if(route.startsWith('/admin/')){
      authenticate(req,true);
      if(route==='/admin/overview'&&method==='GET')return respond(ops.overview());
      if(route==='/admin/disputes'&&method==='GET')return respond(ops.disputes().map(orderView));
      if(route==='/admin/players'&&method==='GET')return respond(catalog('players',true).map(player=>{const member=ops.db.prepare('SELECT id,name FROM users WHERE player_id=? AND wechat_openid IS NOT NULL').get(player.id);return {...player,boundUserId:member?.id||null,memberName:member?.name||null};}));
      const invitation=/^\/admin\/players\/([^/]+)\/invitation$/.exec(route);
      if(invitation&&method==='POST')return respond(ops.transaction(()=>ops.invite(invitation[1])),201);
      const availability=/^\/admin\/players\/([^/]+)\/availability$/.exec(route);
      if(availability){
        if(method==='GET')return respond({playerId:availability[1],timezone:'Asia/Shanghai',slots:ops.availability.list(availability[1])});
        if(method==='PUT'){const data=await body(req);return respond(ops.transaction(()=>ops.availability.update(availability[1],data.slots)));}
      }
      const assign=/^\/admin\/orders\/([^/]+)\/assign$/.exec(route);
      if(assign&&method==='POST')return respond(orderView(ops.assign(assign[1],await body(req))));
      const resolve=/^\/admin\/orders\/([^/]+)\/resolve$/.exec(route);
      if(resolve&&method==='POST'){
        const data=await body(req),row=ops.order(resolve[1]),reason=ops.clean(data.reason,'处理说明',1000);
        if(ops.view(row).dispute?.status!=='open')throw fail(409,'NO_OPEN_DISPUTE','没有待处理争议。');
        if(data.outcome==='resume')return respond(orderView(ops.resume(row.id,reason)));
        if(data.outcome!=='refund')throw fail(400,'VALIDATION','处理结果须为 resume 或 refund。');
        if(row.demo)return respond(orderView(ops.demoRefund(row.id,reason)));
        await requestRefund(row,reason.slice(0,80));
        ops.transaction(()=>{ops.db.prepare("UPDATE disputes SET outcome='refund',resolution=? WHERE order_id=?").run(reason,row.id);ops.event(row.id,'dispute_refund_decision',ops.owner,reason);});
        return respond(orderView(ops.order(row.id)));
      }
      if(route==='/admin/settlements'&&method==='GET')return respond({...ops.ledger.summary(),settlements:ops.ledger.settlements(),demo:config.mode==='demo'});
      if(route==='/admin/settlements'&&method==='POST'){
        const data=await body(req),result=ops.transaction(()=>{
          const previous=new Set(ops.ledger.settlements().map(row=>row.id)),record=ops.ledger.settle(data);
          if(!previous.has(record.id))for(const id of record.entryIds){const entry=ops.db.prepare('SELECT order_id,player_id FROM earnings WHERE id=?').get(id);ops.event(entry.order_id,'settlement_recorded',ops.owner,'运营已记录成员结算凭据，系统没有自动转账。');ops.notifyMember(entry.player_id,'settlement_recorded','结算凭据已记录','请核对实际收款；这不是系统自动转账。',entry.order_id);}
          return record;
        });return respond(result,201);
      }
      if(route==='/admin/settlements/export.csv'&&method==='GET'){res.writeHead(200,{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="openni-settlements.csv"','Cache-Control':'no-store'});res.end(ops.ledger.csv());return true;}
      if(route==='/admin/orders/expire-unpaid'&&method==='POST'){
        const results=[];for(const row of ops.expiredPayments()){try{results.push({id:row.id,order:orderView(await cancelOrder(row,ops.owner,'预约付款超时，已关闭未付款订单。'))});}catch(error){results.push({id:row.id,error:{code:error.code||'INTERNAL',message:error.status?error.message:'暂时无法处理。'}});}}
        return respond({results});
      }
    }
    return false;
  };
}
