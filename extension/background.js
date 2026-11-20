// 后台：上报当前页 + 接收桌面壳的请求
const SRV = 'http://127.0.0.1:8787';

async function post(path, body){
  try {
    await fetch(SRV + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
  } catch (e) {}
}

const APP_URL_RE = /^https?:\/\/127\.0\.0\.1:8787\//i;

/* 选一个"值得读"的标签页：优先当前活动页，但如果活动页是本应用，就退回最近看过的网页 */
async function pickTab(){
  const tabs = await chrome.tabs.query({ lastFocusedWindow: true });
  if (!tabs || !tabs.length) return null;

  const usable = tabs.filter(t => /^https?:/i.test(t.url || '') && !APP_URL_RE.test(t.url || ''));
  const active = tabs.find(t => t.active);

  if (active && !APP_URL_RE.test(active.url || '') && /^https?:/i.test(active.url || '')) return active;
  if (usable.length){
    usable.sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
    return usable[0];
  }
  return active || null;
}

async function reportPage(){
  try {
    const tab = await pickTab();
    if (!tab) return;
    const bad = /^(chrome|edge|about|chrome-extension|devtools|view-source):/i.test(tab.url || '');
    await post('/api/page', bad ? { title: '', url: '' } : { title: tab.title || '', url: tab.url || '' });
  } catch (e) {}
}

chrome.tabs.onActivated.addListener(reportPage);
chrome.tabs.onUpdated.addListener((id, info) => { if (info.status === 'complete') reportPage(); });
chrome.windows.onFocusChanged.addListener(reportPage);

/* ---------- 注入用的取文函数（必须自包含） ---------- */
function extractText(){
  const norm = (s) => (s || '').replace(/\r/g, '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  let sel = '';
  try { sel = String(window.getSelection ? window.getSelection() : ''); } catch (e) {}
  if (sel && sel.trim().length > 120) {
    return { src: '选中文本', title: document.title, text: norm(sel).slice(0, 14000) };
  }
  const main = document.querySelector(
    'article, main, [role="main"], .article-content, .post-content, .rich_media_content, ' +
    '#js_content, #content, .content, .article, .entry-content, .note-content, #detail-desc'
  );
  let text = main ? (main.innerText || '') : '';
  if (!text || text.length < 200) text = document.body ? document.body.innerText : '';
  return { src: '正文', title: document.title, text: norm(text).slice(0, 14000) };
}

/* ---------- 取 Key（优先用本地服务里的，和网页共用一份） ---------- */
let keyCache = null;
let keyCacheAt = 0;

async function getKey(){
  const now = Date.now();
  if (keyCache && now - keyCacheAt < 30000) return keyCache;

  try {
    const r = await fetch(SRV + '/api/key', { cache: 'no-store' });
    if (r.ok){
      const d = await r.json();
      if (d && d.key){
        keyCache = { key: d.key, base: d.base || 'https://api.deepseek.com', model: d.model || 'deepseek-chat' };
        keyCacheAt = now;
        return keyCache;
      }
    }
  } catch (e) {}

  const st = await chrome.storage.local.get(['key', 'base', 'model']);
  if (st.key){
    keyCache = { key: st.key, base: st.base || 'https://api.deepseek.com', model: st.model || 'deepseek-chat' };
    keyCacheAt = now;
    return keyCache;
  }
  return null;
}

/* ---------- 调模型 ---------- */
async function callAI(messages, maxTokens){
  const c = await getKey();
  if (!c || !c.key) throw new Error('还没有 API Key（先在网页的设置里填）');

  const base  = String(c.base).replace(/\/+$/, '');
  const model = c.model;

  const res = await fetch(base + '/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + c.key },
    body: JSON.stringify({ model, messages, max_tokens: maxTokens || 600, temperature: 0.7 })
  });

  const raw = await res.text();
  if (!res.ok) throw new Error('HTTP ' + res.status + ' · ' + raw.slice(0, 140));

  const data = JSON.parse(raw);
  return (data.choices && data.choices[0] && data.choices[0].message.content || '').trim();
}

/* ---------- 处理一次请求 ---------- */
async function handle(action){
  const videoMode = action === 'video';
  await post('/api/read', { status: 'reading', title: '', url: '', summary: '' });

  try {
    const tab = await pickTab();
    if (!tab) throw new Error('没有可读的网页');

    const out = await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: extractText });
    const page = out && out[0] && out[0].result;
    if (!page || !page.text || page.text.length < 40) throw new Error('这个页面文字太少');

    const sys = videoMode
      ? '你是一只住在水缸里的小鲸鱼，正在帮主人看一个视频页面。' +
        '你只能看到标题、简介、评论和页面文字，看不到画面也听不到声音。' +
        '请说明：这个视频大概讲什么、评论里在说什么、值不值得看。' +
        '用中文，先给结论，再列 2-3 条要点，120 字以内。不要编造画面内容。'
      : '你是一只住在水缸里的小鲸鱼，正在帮主人读网页。' +
        '用中文回答，先给结论，再列要点，不要客套话。' +
        '只使用正文里出现的信息；正文没提到就说「正文里没写」。';

    const cmd = videoMode ? '这个视频讲什么，值不值得看' : '总结这一页的要点';

    const text = await callAI([
      { role: 'system', content: sys },
      { role: 'user', content: '【主人的要求】\n' + cmd + '\n\n【网页标题】\n' + page.title + '\n\n【正文】\n' + page.text }
    ], videoMode ? 500 : 700);

    await post('/api/read', { status: 'done', title: page.title, url: tab.url || '', summary: text, tokens: 0 });
  } catch (e) {
    await post('/api/read', { status: 'error', title: '', url: '', summary: e.message, tokens: 0 });
  }
}

/* ---------- 轮询 ---------- */
async function poll(){
  try {
    const r = await fetch(SRV + '/api/request', { cache: 'no-store' });
    const d = await r.json();
    if (d && d.action) await handle(d.action);
  } catch (e) {}
  setTimeout(poll, 2000);
}

reportPage();
poll();
