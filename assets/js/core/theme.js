/* --- THEME MANAGEMENT --- */
(function () {
  const STORAGE_KEY = 'macusb-theme-preference';
  const THEME_DARK = 'dark';
  const THEME_LIGHT = 'light';
  const THEME_TRANSITION_CLASS = 'theme-transition';
  const THEME_TRANSITION_MS = 320;
  const root = document.documentElement;
  const themeQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  let transitionTimer = null;

  function normalizeTheme(value) {
    return value === THEME_DARK || value === THEME_LIGHT ? value : null;
  }

  function getStoredTheme() {
    try {
      return normalizeTheme(window.localStorage.getItem(STORAGE_KEY));
    } catch (_error) {
      return null;
    }
  }

  function getSystemTheme() {
    return themeQuery && themeQuery.matches ? THEME_DARK : THEME_LIGHT;
  }

  function resolveTheme() {
    return getStoredTheme() || getSystemTheme();
  }

  function applyTheme(theme) {
    const nextTheme = normalizeTheme(theme) || THEME_LIGHT;
    root.setAttribute('data-theme', nextTheme);
    root.style.colorScheme = nextTheme;
    return nextTheme;
  }

  function runThemeTransition() {
    root.classList.add(THEME_TRANSITION_CLASS);
    if (transitionTimer) window.clearTimeout(transitionTimer);
    transitionTimer = window.setTimeout(() => {
      root.classList.remove(THEME_TRANSITION_CLASS);
      transitionTimer = null;
    }, THEME_TRANSITION_MS);
  }

  function emitThemeChange(theme, source) {
    document.dispatchEvent(
      new CustomEvent('theme:change', {
        detail: { theme, source },
      })
    );
  }

  function applyResolvedTheme() {
    const theme = applyTheme(resolveTheme());
    emitThemeChange(theme, getStoredTheme() ? 'stored' : 'system');
    return theme;
  }

  function setThemePreference(theme) {
    const normalized = normalizeTheme(theme);
    if (!normalized) return applyResolvedTheme();
    runThemeTransition();
    try {
      window.localStorage.setItem(STORAGE_KEY, normalized);
    } catch (_error) {
      // Ignore storage write failures (private mode / blocked storage).
    }
    const applied = applyTheme(normalized);
    emitThemeChange(applied, 'user');
    return applied;
  }

  function clearThemePreference() {
    try {
      window.localStorage.removeItem(STORAGE_KEY);
    } catch (_error) {
      // Ignore storage failures.
    }
    return applyResolvedTheme();
  }

  function toggleThemePreference() {
    const current = normalizeTheme(root.getAttribute('data-theme')) || resolveTheme();
    const next = current === THEME_DARK ? THEME_LIGHT : THEME_DARK;
    return setThemePreference(next);
  }

  function bindSystemThemeListener() {
    if (!themeQuery) return;

    const onSystemThemeChange = () => {
      if (getStoredTheme()) return;
      runThemeTransition();
      const applied = applyTheme(getSystemTheme());
      emitThemeChange(applied, 'system');
    };

    if (typeof themeQuery.addEventListener === 'function') {
      themeQuery.addEventListener('change', onSystemThemeChange);
    } else if (typeof themeQuery.addListener === 'function') {
      themeQuery.addListener(onSystemThemeChange);
    }
  }

  window.macUSBTheme = {
    getStoredTheme,
    getSystemTheme,
    resolveTheme,
    applyTheme,
    applyResolvedTheme,
    setThemePreference,
    clearThemePreference,
    toggleThemePreference,
  };

  applyResolvedTheme();
  bindSystemThemeListener();
})();
