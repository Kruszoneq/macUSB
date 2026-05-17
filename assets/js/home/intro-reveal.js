/* --- Intro reveal after load --- */
(function () {
  const body = document.body;
  if (!body || !body.classList.contains('home-page')) return;

  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const introActionsDelayMs = reduced ? 0 : 500;
  const navDelayMs = introActionsDelayMs;

  function revealIntro() {
    body.classList.remove('intro-loading');
    body.classList.add('intro-ready');
    window.setTimeout(() => {
      body.classList.add('intro-nav-visible');
    }, navDelayMs);
  }

  function startIntroAnimation() {
    window.requestAnimationFrame(() => {
      revealIntro();
    });
  }

  if (document.readyState === 'complete') {
    startIntroAnimation();
    return;
  }

  window.addEventListener('load', () => {
    startIntroAnimation();
  }, { once: true });
})();
