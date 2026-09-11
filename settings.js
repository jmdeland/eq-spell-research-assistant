(() => {
  const overlay = document.getElementById('settingsOverlay');
  const open = document.getElementById('openSettings');
  const close = document.getElementById('closeSettings');
  if (!overlay || !open || !close) return;

  let lastFocus = null;
  const skin = document.getElementById('skinSelector');
  function applySkin(value) {
    const allowed = ['default','eqblue','eqgold','eqred'];
    const v = allowed.includes(value) ? value : 'default';
    document.documentElement.dataset.skin = v;
    if (skin) skin.value = v;
    try { localStorage.setItem('eqResearchSkinV2', v); } catch (_) {}
  }
  if (skin) {
    let saved = null;
    try { saved = localStorage.getItem('eqResearchSkinV2'); } catch (_) {}
    applySkin(saved || 'default');
    skin.addEventListener('change', () => applySkin(skin.value));
  }

  function openSettings() {
    lastFocus = document.activeElement;
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');
    document.body.classList.add('settings-open');
    setTimeout(() => close.focus(), 0);
  }
  function closeSettings() {
    overlay.classList.add('hidden');
    overlay.setAttribute('aria-hidden', 'true');
    document.body.classList.remove('settings-open');
    if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
  }

  open.addEventListener('click', openSettings);
  close.addEventListener('click', closeSettings);
  overlay.addEventListener('click', e => { if (e.target === overlay) closeSettings(); });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && !overlay.classList.contains('hidden')) closeSettings();
  });
})();
