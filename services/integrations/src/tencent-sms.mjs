import {createHash,createHmac} from 'node:crypto';
import {IntegrationError} from './wechat.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex');
const hmac=(key,value)=>createHmac('sha256',key).update(value).digest();
const fail=(code,message)=>{throw new IntegrationError(code,message);};
const valid=value=>typeof value==='string'&&value.trim()&&value.length<=512&&!/[\r\n\0]/.test(value);

// Tencent Cloud SendSms 2021-01-11; TC3 Signature V3. No automatic retry: an ambiguous
// upstream failure can already have sent a chargeable SMS. The API reserves its limits first.
export async function sendTencentLoginCode({config,phone,code,challengeId,now=Date.now(),fetchImpl=fetch}){
  for(const key of ['secretId','secretKey','sdkAppId','signName','templateId','region'])if(!valid(config?.[key]))fail('INVALID_CONFIGURATION','SMS provider configuration is incomplete');
  if(!/^\+861[3-9]\d{9}$/.test(phone)||!/^\d{6}$/.test(code)||!valid(challengeId))fail('INVALID_SMS_INPUT','SMS destination or code is invalid');
  const host='sms.tencentcloudapi.com',action='SendSms',timestamp=Math.floor(now/1000),date=new Date(timestamp*1000).toISOString().slice(0,10);
  const body=JSON.stringify({PhoneNumberSet:[phone],SmsSdkAppId:config.sdkAppId,SignName:config.signName,TemplateId:config.templateId,TemplateParamSet:config.templateHasMinutes?[code,'5']:[code],SessionContext:challengeId});
  const signedHeaders='content-type;host;x-tc-action',canonicalHeaders=`content-type:application/json; charset=utf-8\nhost:${host}\nx-tc-action:${action.toLowerCase()}\n`;
  const canonical=`POST\n/\n\n${canonicalHeaders}\n${signedHeaders}\n${sha(body)}`,scope=`${date}/sms/tc3_request`;
  const stringToSign=`TC3-HMAC-SHA256\n${timestamp}\n${scope}\n${sha(canonical)}`;
  const key=hmac(hmac(hmac('TC3'+config.secretKey,date),'sms'),'tc3_request');
  const authorization=`TC3-HMAC-SHA256 Credential=${config.secretId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${hmac(key,stringToSign).toString('hex')}`;
  let response;
  try{response=await fetchImpl(`https://${host}/`,{method:'POST',headers:{'Content-Type':'application/json; charset=utf-8',Host:host,Authorization:authorization,'X-TC-Action':action,'X-TC-Version':'2021-01-11','X-TC-Timestamp':String(timestamp),'X-TC-Region':config.region},body,redirect:'error',signal:AbortSignal.timeout(10000)});}catch{fail('SMS_PROVIDER_UNAVAILABLE','SMS provider request failed');}
  let data;
  try{const text=await response.text();if(text.length>32768)throw Error();data=JSON.parse(text)?.Response;}catch{fail('SMS_PROVIDER_INVALID_RESPONSE','SMS provider response was invalid');}
  if(!response.ok||!data||data.Error)fail('SMS_PROVIDER_REJECTED','SMS provider rejected the request');
  const statuses=data.SendStatusSet;
  if(!Array.isArray(statuses)||statuses.length!==1||statuses[0].Code!=='Ok'||statuses[0].PhoneNumber!==phone||statuses[0].SessionContext!==challengeId||!valid(statuses[0].SerialNo))fail('SMS_PROVIDER_REJECTED','SMS provider did not accept this destination');
  return {accepted:true,requestId:typeof data.RequestId==='string'?data.RequestId:null,serialNo:statuses[0].SerialNo};
}
