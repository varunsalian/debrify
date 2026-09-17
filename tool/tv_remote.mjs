import http from 'node:http';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const exec = promisify(execFile);
const serial = process.env.DEBRIFY_TV_SERIAL || 'emulator-5554';
const port = Number(process.env.DEBRIFY_TV_REMOTE_PORT || 18766);
const origin = `http://127.0.0.1:${port}`;
const keys = {up:19, down:20, left:21, right:22, ok:23, back:4, home:3, play:85};
let queue = Promise.resolve();
const adb = (...args) => exec('adb', ['-s', serial, ...args], {timeout:15000, maxBuffer:8*1024*1024});
const page = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Debrify TV remote</title>
<style>body{background:#0b1218;color:#eee;font:17px system-ui;max-width:900px;margin:40px auto;padding:20px}button{background:#203b42;color:white;border:1px solid #44616a;border-radius:14px;padding:18px;font:inherit;cursor:pointer}button:focus-visible{outline:3px solid #82e6be}.pad{display:grid;grid-template-columns:repeat(3,90px);gap:8px;margin:24px 0}.row{display:flex;gap:10px;flex-wrap:wrap}img{width:100%;border-radius:12px;margin-top:20px}small{color:#a5b6bf}</style>
<h1>Debrify TV remote</h1><small>Arrow keys navigate · Enter selects · Escape goes back. Click this page first.</small>
<div class="pad"><span></span><button data-key="up">↑</button><span></span><button data-key="left">←</button><button data-key="ok">OK</button><button data-key="right">→</button><span></span><button data-key="down">↓</button></div>
<div class="row"><button data-key="back">Back</button><button data-key="home">Home</button><button data-key="play">Play / pause</button><button id="hold">Hold OK</button><button id="launch">Open Debrify</button><button id="refresh">Screenshot</button></div><p id="status">Ready</p><img id="screen" alt="TV screenshot appears here after pressing Screenshot">
<script>
const status=document.querySelector('#status');
async function send(key,hold=false){try{let r=await fetch('/key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({key,hold})});if(!r.ok)throw Error(await r.text());status.textContent='Sent '+(hold?'hold ':'')+key;}catch(e){status.textContent=e.message}}
document.querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>send(b.dataset.key));
document.querySelector('#hold').onclick=()=>send('ok',true);
document.querySelector('#launch').onclick=()=>send('launch');
document.querySelector('#refresh').onclick=async()=>{try{const r=await fetch('/screen?t='+Date.now());if(!r.ok)throw Error(await r.text());const img=document.querySelector('#screen');if(img.src.startsWith('blob:'))URL.revokeObjectURL(img.src);img.src=URL.createObjectURL(await r.blob());}catch(e){status.textContent=e.message}};
document.onkeydown=e=>{const k={ArrowUp:'up',ArrowDown:'down',ArrowLeft:'left',ArrowRight:'right',Enter:'ok',Escape:'back'}[e.key];if(k){e.preventDefault();if(!e.repeat)send(k)}};
</script>`;
const server = http.createServer(async (req,res) => {
  res.setHeader('Cache-Control','no-store');
  if(req.headers.host !== `127.0.0.1:${port}` || (req.headers.origin && req.headers.origin !== origin)) {
    res.writeHead(403);res.end('Local requests only');return;
  }
  try {
    if(req.method==='GET' && req.url==='/') {res.setHeader('Content-Type','text/html; charset=utf-8');res.end(page);return;}
    if(req.method==='GET' && req.url.startsWith('/screen?')) {
      const {stdout}=await exec('adb',['-s',serial,'exec-out','screencap','-p'],{encoding:'buffer',timeout:15000,maxBuffer:8*1024*1024});
      if(!stdout.length)throw Error('Screenshot unavailable from this emulator. Use the emulator window to view the TV.');
      res.setHeader('Content-Type','image/png');res.end(stdout);return;
    }
    if(req.method==='POST' && req.url==='/key' && req.headers.origin===origin) {
      let body='';for await(const chunk of req){body+=chunk;if(body.length>1024)throw Error('Request too large');}
      const {key,hold}=JSON.parse(body);
      if(key!=='launch' && !Object.hasOwn(keys,key)){res.writeHead(400);res.end('Unknown key');return;}
      const action=()=>key==='launch' ? adb('shell','monkey','-p','com.debrify.app','1')
        : adb('shell','input','keyevent',...(hold?['--longpress']:[]),String(keys[key]));
      const pending=queue.then(action);queue=pending.catch(()=>{});await pending;
      res.end('OK');return;
    }
    res.writeHead(404);res.end('Not found');
  } catch(e){res.writeHead(500);res.end(e.message);}
});
server.listen(port,'127.0.0.1',()=>console.log(`Debrify TV remote: ${origin} (${serial})`));
