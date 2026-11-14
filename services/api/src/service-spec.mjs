const choices={platform:['PC','mobile'],serviceType:['hourly','escort','review'],billingUnit:['hour','session','target']};
export function validateServiceSpec(input,fail){
  const result={};
  for(const [key,allowed]of Object.entries(choices))if(input[key]!==undefined){if(!allowed.includes(input[key]))throw fail(400,'VALIDATION',`${key} 必须为 ${allowed.join(' / ')}。`);result[key]=input[key];}
  if(input.teamSize!==undefined){if(!Number.isInteger(input.teamSize)||input.teamSize<1||input.teamSize>4)throw fail(400,'VALIDATION','服务成员人数须为 1 至 4。');result.teamSize=input.teamSize;}
  if(input.gameMode!==undefined){if(typeof input.gameMode!=='string'||input.gameMode.length>100)throw fail(400,'VALIDATION','玩法不得超过 100 字符。');result.gameMode=input.gameMode.trim();}
  for(const key of ['maps','rules'])if(input[key]!==undefined){if(!Array.isArray(input[key])||input[key].length>20||input[key].some(v=>typeof v!=='string'||!v.trim()||v.length>(key==='maps'?80:1000)))throw fail(400,'VALIDATION',`${key} 须为有效的文本列表，最多 20 项。`);result[key]=input[key].map(v=>v.trim());}
  return result;
}
export function validateVariants(input,fail){
  if(input===undefined)return [];
  if(!Array.isArray(input)||input.length>20)throw fail(400,'VALIDATION','服务规格最多 20 项。');
  const seen=new Set();
  return input.map(v=>{
    if(!v||typeof v!=='object'||typeof v.id!=='string'||!/^[-A-Za-z0-9_]{1,64}$/.test(v.id)||seen.has(v.id)||typeof v.title!=='string'||!v.title.trim()||v.title.length>100)throw fail(400,'VALIDATION','规格须有唯一编号和名称。');
    seen.add(v.id);
    if(!Number.isSafeInteger(v.priceCents)||v.priceCents<1||v.priceCents>10000000||!Number.isInteger(v.durationMinutes)||v.durationMinutes<15||v.durationMinutes>720)throw fail(400,'VALIDATION','规格价格或服务时长无效。');
    return {id:v.id,title:v.title.trim(),priceCents:v.priceCents,durationMinutes:v.durationMinutes,...validateServiceSpec(v,fail)};
  });
}
export function quoteService(service,variantId,fail){
  let variant;
  if(service.variants?.length){variant=service.variants.find(item=>item.id===variantId);if(!variant)throw fail(400,'VARIANT_REQUIRED','请选择有效的服务规格。');}
  else if(variantId!==undefined&&variantId!==null&&variantId!=='')throw fail(400,'INVALID_VARIANT','此服务不存在该规格。');
  const selected={...service,...variant,id:service.id,title:service.title,variantId:variant?.id||null,variantTitle:variant?.title||null};
  if((selected.teamSize||1)>1)throw fail(409,'MULTI_MEMBER_NOT_SUPPORTED','当前版本仅支持一位服务成员的预约，请联系俱乐部安排多人服务。');
  delete selected.variants;delete selected.archived;
  return selected;
}
