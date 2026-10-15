const english = document.documentElement.lang === 'en';
const toggle = document.querySelector('[role="switch"]');
toggle?.addEventListener('click', () => {
  const enabled = toggle.getAttribute('aria-checked') !== 'true';
  toggle.setAttribute('aria-checked', String(enabled));
  document.querySelector('.stage').classList.toggle('is-off', !enabled);
  document.querySelector('.screen-status').textContent = english
    ? (enabled ? 'Sleep prevention is on' : 'Normal sleep is allowed')
    : (enabled ? '잠자기 방지 중' : '잠자기 허용 중');
});
document.querySelector('.copy')?.addEventListener('click', async (event) => {
  const button = event.currentTarget;
  try {
    await navigator.clipboard.writeText(document.querySelector('#install-command').textContent.trim());
    button.textContent = english ? 'Copied!' : '복사 완료';
    setTimeout(() => { button.textContent = english ? 'Copy' : '복사'; }, 2200);
  } catch {
    button.textContent = english ? 'Select code to copy' : '코드를 선택해 복사하세요';
  }
});
