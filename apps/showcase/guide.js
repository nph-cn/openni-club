for (const pre of document.querySelectorAll('pre')) {
  const code = pre.querySelector('code');
  if (!code) continue;
  const button = document.createElement('button');
  button.className = 'copy-code'; button.textContent = '复制'; button.setAttribute('aria-label','复制代码');
  button.onclick = async () => {
    try { await navigator.clipboard.writeText(code.textContent); button.textContent = '已复制'; }
    catch { button.textContent = '请手动选中复制'; }
    setTimeout(()=>button.textContent='复制',2000);
  };
  pre.append(button);
}
