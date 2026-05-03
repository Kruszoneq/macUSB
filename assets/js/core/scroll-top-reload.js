/* --- Scroll to top on reload --- */
(function () {
  const navEntry = performance.getEntriesByType && performance.getEntriesByType('navigation')[0];
  const isReload = navEntry
    ? navEntry.type === 'reload'
    : window.performance &&
      window.performance.navigation &&
      window.performance.navigation.type === 1;

  if (!isReload) return;
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';

  window.addEventListener(
    'load',
    () => {
      window.requestAnimationFrame(() => {
        window.scrollTo(0, 0);
      });
    },
    { once: true }
  );
})();
