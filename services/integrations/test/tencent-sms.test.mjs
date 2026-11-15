import test from 'node:test';
import assert from 'node:assert/strict';
import {sendTencentLoginCode} from '../src/tencent-sms.mjs';
const config={secretId:'fixture-id',secretKey:'fixture-secret',sdkAppId:'1400000000',signName:'俱乐部',templateId:'123456',region:'ap-guangzhou'};
const input={config,phone:'+8613800138000',code:'042701',challengeId:'challenge_fixture',now:1794704400000};
const status={Code:'Ok',PhoneNumber:input.phone,SessionContext:input.challengeId,SerialNo:'accepted_fixture'};
const response=data=>new Response(JSON.stringify({Response:{SendStatusSet:[status],RequestId:'request_fixture',...data}}));
test('Tencent SendSms uses official HTTPS wire format and a fixed independently calculated TC3 vector',async()=>{
  const result=await sendTencentLoginCode({...input,fetchImpl:async(url,options)=>{
    assert.equal(url,'https://sms.tencentcloudapi.com/');assert.equal(options.method,'POST');assert.equal(options.redirect,'error');assert.ok(options.signal instanceof AbortSignal);
    assert.equal(options.headers['X-TC-Version'],'2021-01-11');assert.equal(options.headers['X-TC-Action'],'SendSms');assert.equal(options.headers['X-TC-Region'],'ap-guangzhou');
    // Frozen vector calculated with Python hashlib/hmac from the official TC3 algorithm.
    assert.equal(options.headers.Authorization,'TC3-HMAC-SHA256 Credential=fixture-id/2026-11-15/sms/tc3_request, SignedHeaders=content-type;host;x-tc-action, Signature=a1195444f024ec1df340f46c3685aba39dff8ecc4979e25d3bc1708f5df82ccf');
    assert.deepEqual(JSON.parse(options.body),{PhoneNumberSet:[input.phone],SmsSdkAppId:config.sdkAppId,SignName:'俱乐部',TemplateId:config.templateId,TemplateParamSet:['042701'],SessionContext:input.challengeId});return response();
  }});assert.deepEqual(result,{accepted:true,requestId:'request_fixture',serialNo:'accepted_fixture'});
});
test('optional template minutes follow the configured two-placeholder template',async()=>{
  await sendTencentLoginCode({...input,config:{...config,templateHasMinutes:true},fetchImpl:async(_,options)=>{assert.deepEqual(JSON.parse(options.body).TemplateParamSet,['042701','5']);return response();}});
});
test('rejected, misdirected, mismatched and malformed responses never become accepted delivery',async()=>{
  const cases=[()=>response({Error:{Code:'AuthFailure',Message:'fixture-secret'}}),()=>response({SendStatusSet:[{...status,Code:'FailedOperation'}]}),()=>response({SendStatusSet:[{...status,PhoneNumber:'+8613900139000'}]}),()=>response({SendStatusSet:[{...status,SessionContext:'another-challenge'}]}),()=>response({SendStatusSet:[status,status]}),()=>new Response('not-json'),()=>new Response('x'.repeat(32769)),()=>new Response(JSON.stringify({Response:{SendStatusSet:[status]}}),{status:503})];
  for(const fetchImpl of cases)await assert.rejects(sendTencentLoginCode({...input,fetchImpl}),error=>error.code.startsWith('SMS_PROVIDER_')&&!error.message.includes('fixture-secret'));
});
test('network failures are sanitized without a retry and invalid configuration does not make a request',async()=>{
  let count=0;await assert.rejects(sendTencentLoginCode({...input,fetchImpl:async()=>{count++;throw Error('fixture-secret +8613800138000');}}),error=>error.code==='SMS_PROVIDER_UNAVAILABLE'&&!error.message.includes(input.phone)&&!error.message.includes(config.secretKey));assert.equal(count,1);
  await assert.rejects(sendTencentLoginCode({...input,config:{...config,secretKey:''},fetchImpl:async()=>{count++;}}),{code:'INVALID_CONFIGURATION'});assert.equal(count,1);
  await assert.rejects(sendTencentLoginCode({...input,phone:'13800138000',fetchImpl:async()=>{count++;}}),{code:'INVALID_SMS_INPUT'});assert.equal(count,1);
});
