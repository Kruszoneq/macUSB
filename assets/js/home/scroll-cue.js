/* --- Scroll cue (hero -> section) --- */
(function () {
  const scrollCue = document.querySelector('.scroll-cue');
  if (!scrollCue) return;

  scrollCue.addEventListener('click', () => {
    const targetId = scrollCue.dataset.scrollTarget || 'screenshots';
    const target = document.getElementById(targetId);
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
})();
