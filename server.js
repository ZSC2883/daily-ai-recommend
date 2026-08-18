// server.js —— 每日 AI 推荐本地服务
// 作用：让网页能读写本地收藏文件(收藏.md) + 一键重新生成
// 启动：node server.js   监听 http://127.0.0.1:8765/
const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const DIR = __dirname;
const PORT = 8765;

function send(res, code, type, text) {
  res.writeHead(code, { 'Content-Type': type + '; charset=utf-8', 'Access-Control-Allow-Origin': '*' });
  res.end(text);
}

// 读取收藏列表（结构化存 favorites.json，同时生成可读的 收藏.md）
function readFavs() {
  const jsonFile = path.join(DIR, 'favorites.json');
  if (!fs.existsSync(jsonFile)) return [];
  try {
    const arr = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
    return Array.isArray(arr) ? arr : [];
  } catch (e) {
    return [];
  }
}

// 把收藏渲染成漂亮的 Markdown（标题 + 序号 + 大纲）
function toMarkdown(favs) {
  const lines = ['# 我的收藏', ''];
  if (!favs.length) {
    lines.push('（暂无收藏）');
    return lines.join('\n');
  }
  lines.push('> 共 ' + favs.length + ' 条');
  lines.push('');
  favs.forEach((f, i) => {
    lines.push('## ' + (i + 1) + '. ' + (f.name || '未命名'));
    lines.push('');
    if (f.desc) { lines.push('**介绍**：' + f.desc); lines.push(''); }
    if (f.url) { lines.push('**链接**：' + f.url); lines.push(''); }
    if (f.usage) {
      lines.push('**使用方法**：');
      f.usage.split(/[；;]/).map(s => s.trim()).filter(Boolean).forEach(s => { lines.push('- ' + s); });
      lines.push('');
    }
    if (f.date) { lines.push('**收藏日期**：' + f.date); lines.push(''); }
    lines.push('---');
    lines.push('');
  });
  return lines.join('\n');
}

function writeFavs(favs) {
  const jsonFile = path.join(DIR, 'favorites.json');
  const mdFile = path.join(DIR, '收藏.md');
  fs.writeFileSync(jsonFile, JSON.stringify(favs, null, 2), 'utf8');
  fs.writeFileSync(mdFile, toMarkdown(favs), 'utf8');
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1:' + PORT);
  const p = url.pathname;

  // 返回最新生成的推荐页（固定单页，每日覆盖）
  if (req.method === 'GET' && (p === '/' || p === '/index.html')) {
    const page = path.join(DIR, '今日推荐.html');
    const html = fs.existsSync(page)
      ? fs.readFileSync(page, 'utf8')
      : '<h1 style="font-family:sans-serif">还没有推荐，请先运行生成脚本</h1>';
    send(res, 200, 'text/html', html);
    return;
  }

  // 读取收藏列表
  if (req.method === 'GET' && p === '/favs') {
    send(res, 200, 'application/json', JSON.stringify(readFavs()));
    return;
  }

  // 添加/删除收藏
  if (req.method === 'POST' && p === '/fav') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        let favs = readFavs();
        favs = favs.filter(f => f.url !== data.url);   // 先移除同链接的
        if (data.action === 'add') {
          const date = new Date().toISOString().slice(0, 10);
          favs.push({ name: data.name || '', desc: data.desc || '', url: data.url || '', usage: data.usage || '', date });
        }
        writeFavs(favs);
        send(res, 200, 'application/json', JSON.stringify({ ok: true }));
      } catch (e) {
        send(res, 500, 'application/json', JSON.stringify({ ok: false, error: e.message }));
      }
    });
    return;
  }

  // 一键重新生成
  if (req.method === 'POST' && p === '/regen') {
    exec('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + path.join(DIR, 'daily-ai-recommend.ps1') + '" -Test', { windowsHide: true });
    send(res, 200, 'application/json', JSON.stringify({ ok: true, msg: '已触发重新生成，约 1-2 分钟后刷新页面' }));
    return;
  }

  // 返回静态文件（基金黄金页面、背景图等）
  if (req.method === 'GET') {
    const name = path.basename(p);
    if (name && name !== '/') {
      const filePath = path.join(DIR, name);
      if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        const ext = path.extname(name).toLowerCase();
        let type = 'application/octet-stream';
        if (ext === '.html') type = 'text/html; charset=utf-8';
        else if (ext === '.jpg' || ext === '.jpeg') type = 'image/jpeg';
        else if (ext === '.png') type = 'image/png';
        res.writeHead(200, { 'Content-Type': type });
        res.end(fs.readFileSync(filePath));
        return;
      }
    }
  }

  send(res, 404, 'text/plain', 'not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('每日 AI 推荐服务已启动: http://127.0.0.1:' + PORT + '/');
});
