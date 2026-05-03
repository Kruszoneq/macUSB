/* --- NAVBAR + FOOTER INCLUDE --- */
(function () {
  const navMount = document.getElementById('navbar');
  const footerMount = document.getElementById('footer');
  if (!navMount && !footerMount) return;

  const path = window.location.pathname;
  const basePrefix = path === '/macUSB' || path.startsWith('/macUSB/') ? '/macUSB' : '';
  const navUrl = `${basePrefix}/pages/partials.html`;
  const footerUrl = `${basePrefix}/pages/footer.html`;

  function updateViewportMetrics() {
    document.documentElement.style.setProperty('--vh', `${window.innerHeight * 0.01}px`);

    const nav = document.querySelector('nav');
    if (nav) {
      document.documentElement.style.setProperty('--nav-height', `${nav.offsetHeight}px`);
    }

    const header = document.querySelector('.page-header');
    if (header) {
      document.documentElement.style.setProperty('--page-header-offset', `${header.offsetTop}px`);
    }
  }

  function initNavStateTracking() {
    function onScroll() {
      if (window.scrollY > 30) {
        document.body.classList.add('scrolled');
      } else {
        document.body.classList.remove('scrolled');
      }
      updateViewportMetrics();
    }

    updateViewportMetrics();
    onScroll();

    window.addEventListener('resize', () => {
      updateViewportMetrics();
    });
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  function initGuidesDropdown() {
    const navGuides = document.querySelector('.nav-guides');
    if (!navGuides) return;

    const trigger = navGuides.querySelector('.guides-trigger');
    const dropdown = navGuides.querySelector('.guides-dropdown');
    if (!trigger || !dropdown) return;

    let open = false;

    function canHover() {
      return window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    }

    function openDropdown() {
      if (open) return;
      navGuides.classList.add('is-open');
      trigger.setAttribute('aria-expanded', 'true');
      open = true;
    }

    function closeDropdown() {
      if (!open) return;
      navGuides.classList.remove('is-open');
      trigger.setAttribute('aria-expanded', 'false');
      open = false;
    }

    trigger.addEventListener('click', (event) => {
      if (canHover()) return;
      open ? closeDropdown() : openDropdown();
      event.stopPropagation();
    });

    trigger.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        open ? closeDropdown() : openDropdown();
        if (!open) return;
        const firstItem = dropdown.querySelector('a,button,[tabindex]:not([tabindex="-1"])');
        if (firstItem) firstItem.focus();
      } else if (event.key === 'ArrowDown') {
        event.preventDefault();
        openDropdown();
        const firstItem = dropdown.querySelector('a,button,[tabindex]:not([tabindex="-1"])');
        if (firstItem) firstItem.focus();
      }
    });

    dropdown.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        closeDropdown();
        trigger.focus();
      }
    });

    document.addEventListener('click', (event) => {
      if (!navGuides.contains(event.target)) closeDropdown();
    });

    navGuides.addEventListener('mouseenter', () => {
      if (canHover()) openDropdown();
    });

    navGuides.addEventListener('mouseleave', () => {
      if (canHover()) closeDropdown();
    });
  }

  function initThemeToggle() {
    const themeToggle = document.querySelector('.theme-toggle');
    if (!themeToggle) return;

    const themeApi = window.macUSBTheme;
    if (!themeApi || typeof themeApi.toggleThemePreference !== 'function') return;

    function describeNextAction() {
      const currentTheme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
      const nextTheme = currentTheme === 'dark' ? 'light' : 'dark';
      const label = `Switch to ${nextTheme} theme`;
      themeToggle.setAttribute('aria-label', label);
      themeToggle.setAttribute('title', label);
      themeToggle.setAttribute('aria-checked', currentTheme === 'dark' ? 'true' : 'false');
    }

    describeNextAction();

    themeToggle.addEventListener('click', () => {
      themeApi.toggleThemePreference();
      describeNextAction();
    });

    document.addEventListener('theme:change', describeNextAction);
  }

  function initAfterNavbarInjected() {
    initNavStateTracking();
    initGuidesDropdown();
    initThemeToggle();
  }

  function runScripts(mount) {
    const scripts = Array.from(mount.querySelectorAll('script'));
    scripts.forEach((script) => {
      const fresh = document.createElement('script');
      Array.from(script.attributes).forEach((attr) => fresh.setAttribute(attr.name, attr.value));
      if (script.textContent) fresh.textContent = script.textContent;
      script.replaceWith(fresh);
    });
  }

  function injectPartial(mount, url, onLoad, label) {
    if (!mount) return;

    fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.text();
      })
      .then((html) => {
        const resolved = html.replaceAll('{{BASE}}', basePrefix);
        mount.innerHTML = resolved;
        runScripts(mount);
        document.dispatchEvent(
          new CustomEvent('partial:loaded', {
            detail: { label, mountId: mount.id || null },
          })
        );
        if (onLoad) onLoad();
      })
      .catch((error) => console.error(`${label} load error:`, error));
  }

  injectPartial(navMount, navUrl, initAfterNavbarInjected, 'Navbar');
  injectPartial(footerMount, footerUrl, null, 'Footer');
})();
