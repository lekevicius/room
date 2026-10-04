// Diagnostic comparison only: installed Chrome, fresh isolated profiles.
// Usage: node ...mjs NEW_OUTPUT_DIRECTORY [concurrent browsers, default 3]
// Does not substitute for Room's strict ten-page quit baseline.
import {spawn, execFileSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync, openSync, closeSync, readdirSync} from 'node:fs';
import {resolve, join} from 'node:path';
import {homedir} from 'node:os';
import {setTimeout as delay} from 'node:timers/promises';
const output = resolve(process.argv[2]);
const count = Number(process.argv[3] ?? 3);
if (!Number.isInteger(count) || count < 1 || count > 3) throw Error('1–3 browsers required');
mkdirSync(output);
const app = process.env.ROOM_COMPARE_APP ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const info = resolve(app, '../../Info.plist');
const fixture = process.env.ROOM_COMPARE_URLS_JSON;
const urls = fixture ? JSON.parse(readFileSync(fixture, 'utf8')) : [...readFileSync('App/RoomCore/HostSpike.swift', 'utf8')
  .split('static let typicalSites = [')[1].split(']')[0].matchAll(/"(https:[^"]+)"/g)]
  .map(match => match[1]);
if (fixture && urls.some(value => {const url=new URL(value); return url.protocol!=='http:' || !url.hostname.endsWith('.localhost') || !url.port;})) throw Error('loopback URLs required');
if (urls.length !== 10) throw Error('expected ten baseline URLs');
function snapshot(pid) {
  const rows = execFileSync('ps', ['-axo', 'pid=,ppid=,command='], {encoding:'utf8'})
    .trim().split('\n').map(row => row.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/)).filter(Boolean);
  const pids = new Set([pid]);
  for (let i=0;i<4;i++) for (const row of rows) if (pids.has(Number(row[2]))) pids.add(Number(row[1]));
  return rows.filter(row=>pids.has(Number(row[1]))).map(row=>({pid:Number(row[1]),ppid:Number(row[2]),command:row[3]}));
}
function crashReports() { return new Set(readdirSync(join(homedir(),'Library/Logs/DiagnosticReports')).filter(name=>name.startsWith('Room')||name.startsWith('Google Chrome'))); }
async function run(index) {
  const before=crashReports();
  const dir=join(output, `group-${index}`); mkdirSync(dir);
  const profile=join(dir,'profile'); const log=openSync(join(dir,'host.log'),'w');
  const child=spawn(app,[`--user-data-dir=${profile}`,'--remote-debugging-port=0',
    '--no-first-run','--no-default-browser-check','--disable-background-networking',
    '--use-mock-keychain','about:blank'],{stdio:['ignore',log,log]});
  let exit=null, socket, stopTime, id=0; const pending=new Map(), loaded=new Set(), samples=[];
  child.once('exit',(code,signal)=>{exit={code,signal,time:Date.now()};});
  const deadline=setTimeout(()=>child.kill('SIGKILL'),180000);
  const command=(method,params={},sessionId)=>new Promise((resolve,reject)=>{
    const number=++id; const timer=setTimeout(()=>{pending.delete(number);reject(Error(`${method} timeout`));},20000);
    pending.set(number,{resolve,reject,timer}); socket.send(JSON.stringify({id:number,method,params,sessionId}));
  });
  const result={corpus:fixture?'loopback-storage-canvas-v1':'external-typical-sites',diagnostic_sampling:process.env.ROOM_COMPARE_SAMPLE==='1',app,library_path:process.env.DYLD_LIBRARY_PATH??null,version:execFileSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleShortVersionString',info],{encoding:'utf8'}).trim(),pid:child.pid};
  try {
    let port;
    for(let i=0;i<600;i++) { if(exit) throw Error(`early exit ${JSON.stringify(exit)}`); try {port=readFileSync(join(profile,'DevToolsActivePort'),'utf8').split('\n');break;}catch{} await delay(100); }
    if(!port) throw Error('no debugging port');
    socket=new WebSocket(`ws://127.0.0.1:${port[0]}${port[1]}`);
    await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
    socket.onmessage=event=>{const message=JSON.parse(event.data);if(message.method==='Page.loadEventFired')loaded.add(message.sessionId);
      if(message.id){const item=pending.get(message.id);if(item){clearTimeout(item.timer);pending.delete(message.id);message.error?item.reject(Error(JSON.stringify(message.error))):item.resolve(message.result);}}};
    const initial=(await command('Target.getTargets')).targetInfos.filter(x=>x.type==='page');
    const sessions=[]; const start=Date.now();
    for(const url of urls){const {targetId}=await command('Target.createTarget',{url:'about:blank',background:sessions.length>0});
      const {sessionId}=await command('Target.attachToTarget',{targetId,flatten:true});
      await command('Page.enable',{},sessionId); loaded.delete(sessionId);
      sessions.push({sessionId,url}); await command('Page.navigate',{url},sessionId);}
    for(const item of initial) await command('Target.closeTarget',{targetId:item.targetId});
    while(sessions.some(x=>!loaded.has(x.sessionId))&&Date.now()-start<60000)await delay(250);
    if(fixture) {
      while(Date.now()-start<60000) {
        const states=await Promise.all(sessions.map(async ({sessionId})=>(await command('Runtime.evaluate',{expression:'document.title',returnByValue:true},sessionId)).result.value));
        if(states.every(title=>title.startsWith('Room shutdown ready ')))break;
        await delay(250);
      }
    }
    await delay(3000);
    result.pages=await Promise.all(sessions.map(async ({sessionId,url})=>({url,loaded:loaded.has(sessionId),state:(await command('Runtime.evaluate',{expression:'JSON.stringify({url:location.href,ready:document.readyState,title:document.title})',returnByValue:true},sessionId)).result.value})));
    result.ready_seconds=(Date.now()-start)/1000; result.complete=result.pages.every(p=>p.loaded&&JSON.parse(p.state).ready==='complete'&&(!fixture||JSON.parse(p.state).title.startsWith('Room shutdown ready ')));
    stopTime=Date.now(); result.helpers=snapshot(child.pid);
    await command('Browser.close');
    let sampled=false;
    while(!exit&&Date.now()-stopTime<20000){
      if(process.env.ROOM_COMPARE_SAMPLE==='1'&&!sampled&&Date.now()-stopTime>3000){sampled=true;const rows=snapshot(child.pid);writeFileSync(join(dir,'shutdown-processes.json'),JSON.stringify(rows,null,2));
        for(const row of rows.filter(x=>x.pid===child.pid||x.command.includes('network.mojom.NetworkService'))){
          const sampler=spawn('sample',[String(row.pid),'8','10','-file',join(dir,`${row.pid}-sample.txt`)],{stdio:'ignore'});
          samples.push(new Promise(resolve=>sampler.once('exit',resolve)));}}
      await delay(50);}
    result.quit_seconds=exit?(exit.time-stopTime)/1000:null;result.exit=exit;
    // Match the Room runner's unchanged five-second helper grace.
    const helperCommands=new Map(result.helpers.filter(row=>row.pid!==child.pid&&row.command.includes(' Helper')).map(row=>[row.pid,row.command]));
    const grace=Date.now()+5000;
    do {
      const rows=execFileSync('ps',['-axo','pid=,command='],{encoding:'utf8'}).trim().split('\n');
      result.leftover_helpers=rows.filter(row=>{const match=row.trim().match(/^(\d+)\s+(.*)$/);return match&&helperCommands.get(Number(match[1]))===match[2];});
      if(!result.leftover_helpers.length)break;
      await delay(100);
    }while(Date.now()<grace);
    result.helper_grace_seconds=5;
    result.new_crash_reports=[...crashReports()].filter(name=>!before.has(name));
    await Promise.all(samples);
  } catch(error) {result.error=String(error);} finally {
    if(socket)socket.close();for(const item of pending.values())clearTimeout(item.timer);
    if(!exit)child.kill('SIGTERM');await delay(500);if(!exit)child.kill('SIGKILL');
    result.final_exit=exit;clearTimeout(deadline);closeSync(log);writeFileSync(join(dir,'receipt.json'),JSON.stringify(result,null,2)+'\n');
  }
  return {group:index,complete:result.complete,quit_seconds:result.quit_seconds,exit:result.exit,helpers_left:result.leftover_helpers?.length,new_crash_reports:result.new_crash_reports,error:result.error};
}
writeFileSync(join(output,'machine-before.txt'),execFileSync('top',['-l','1','-n','0'],{encoding:'utf8'}));
const results=await Promise.all(Array.from({length:count},(_,i)=>run(i+1)));
console.log(JSON.stringify(results,null,2));
if(results.some(r=>r.error||!r.complete||r.helpers_left!==0||r.new_crash_reports?.length!==0||r.exit?.code!==0))process.exitCode=1;
