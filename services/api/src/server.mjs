import {createApp,readConfig} from './app.mjs';
try {
  const config=readConfig(); const server=createApp(config);
  server.listen(config.port,config.host,()=>console.log(`OpenNI API http://${config.host}:${config.port} (${config.mode}; JSAPI payments ${config.wechatPay?'configured':'disabled'}; APP payments ${config.wechatAppPay?'configured':'disabled'})`));
  const stop=()=>server.close(()=>process.exit(0));
  process.on('SIGINT',stop);process.on('SIGTERM',stop);
}catch(error){console.error(error.message);process.exitCode=1;}
