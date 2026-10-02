const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../mobile/build/web');
http.createServer((req,res)=>{
  const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
  if(!file.startsWith(root+path.sep)&&file!==root){res.writeHead(403).end();return;}
  const target=fs.existsSync(file)&&fs.statSync(file).isFile()?file:path.join(root,'index.html');
  res.setHeader('Content-Type',({'.js':'text/javascript','.html':'text/html','.json':'application/json','.wasm':'application/wasm','.png':'image/png'})[path.extname(target)]||'application/octet-stream');
  fs.createReadStream(target).pipe(res);
}).listen(8175,'127.0.0.1',()=>console.log('Umbral QA http://127.0.0.1:8175'));
