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

  function initAfterNavbarInjected() {
    initNavStateTracking();
    initGuidesDropdown();
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
        if (onLoad) onLoad();
      })
      .catch((error) => console.error(`${label} load error:`, error));
  }

  injectPartial(navMount, navUrl, initAfterNavbarInjected, 'Navbar');
  injectPartial(footerMount, footerUrl, null, 'Footer');
})();

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

/* --- Homebrew command toggle --- */
(function () {
  const toggle = document.querySelector('.brew-toggle');
  const panel = document.getElementById('brew-command-panel');
  const copyButton = panel ? panel.querySelector('.brew-copy-button') : null;
  const commandText = document.getElementById('brew-command-text');
  if (!toggle || !panel) return;

  let hideTimer = null;
  let copiedTimer = null;

  function openPanel() {
    if (hideTimer) {
      window.clearTimeout(hideTimer);
      hideTimer = null;
    }
    panel.hidden = false;
    window.requestAnimationFrame(() => {
      panel.classList.add('is-open');
    });
    toggle.setAttribute('aria-expanded', 'true');
  }

  function closePanel() {
    panel.classList.remove('is-open');
    toggle.setAttribute('aria-expanded', 'false');
    hideTimer = window.setTimeout(() => {
      panel.hidden = true;
      hideTimer = null;
    }, 260);
  }

  toggle.addEventListener('click', () => {
    const isOpen = toggle.getAttribute('aria-expanded') === 'true';
    if (isOpen) {
      closePanel();
    } else {
      openPanel();
    }
  });

  function setCopiedState() {
    if (!copyButton) return;
    copyButton.classList.add('is-copied');
    copyButton.setAttribute('aria-label', 'Command copied');

    if (copiedTimer) window.clearTimeout(copiedTimer);
    copiedTimer = window.setTimeout(() => {
      copyButton.classList.remove('is-copied');
      copyButton.setAttribute('aria-label', 'Copy Homebrew command');
      copiedTimer = null;
    }, 2000);
  }

  async function copyCommand() {
    if (!copyButton || !commandText) return;
    const value = commandText.textContent ? commandText.textContent.trim() : '';
    if (!value) return;

    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
      setCopiedState();
      return;
    }

    const area = document.createElement('textarea');
    area.value = value;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    area.style.pointerEvents = 'none';
    document.body.appendChild(area);
    area.select();
    const copied = document.execCommand('copy');
    document.body.removeChild(area);

    if (copied) setCopiedState();
  }

  if (copyButton) {
    copyButton.addEventListener('click', () => {
      copyCommand().catch(() => {});
    });
  }
})();

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

/* --- Generic reveal animation --- */
(function () {
  const elements = Array.from(document.querySelectorAll('.reveal'));
  if (!elements.length) return;

  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduced || !('IntersectionObserver' in window)) {
    elements.forEach((element) => element.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      });
    },
    { threshold: 0.16, rootMargin: '0px 0px -8% 0px' }
  );

  elements.forEach((element) => observer.observe(element));
})();

/* --- App screenshots carousel --- */
(function () {
  const carousels = Array.from(document.querySelectorAll('.screenshot-carousel'));
  if (!carousels.length) return;
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function initCarousel(carousel) {
    const stage = carousel.querySelector('.screenshot-stage');
    if (!stage) return;

    const slides = Array.from(stage.querySelectorAll('img')).sort(
      (a, b) => Number(a.dataset.step || 0) - Number(b.dataset.step || 0)
    );
    if (!slides.length) return;

    const dots = Array.from(carousel.querySelectorAll('.screenshot-dot[data-step]')).sort(
      (a, b) => Number(a.dataset.step || 0) - Number(b.dataset.step || 0)
    );

    let index = 0;
    let intervalId = null;
    let resumeTimerId = null;
    let started = false;

    function updateDots() {
      if (!dots.length) return;
      dots.forEach((dot, dotIndex) => {
        const active = dotIndex === index;
        dot.classList.toggle('is-active', active);
        dot.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
    }

    function showInitial() {
      slides.forEach((img) => img.classList.remove('is-active', 'is-exiting'));
      index = 0;
      slides[0].classList.add('is-active');
      updateDots();
    }

    function showSlide(nextIndex) {
      if (nextIndex < 0 || nextIndex >= slides.length) return;
      if (nextIndex === index) {
        updateDots();
        return;
      }

      const current = slides[index];
      const next = slides[nextIndex];

      current.classList.remove('is-active');
      if (!reduced) current.classList.add('is-exiting');

      next.classList.add('is-active');
      index = nextIndex;
      updateDots();

      if (!reduced) {
        setTimeout(() => current.classList.remove('is-exiting'), 850);
      }
    }

    function restartAutoRotation() {
      if (reduced || slides.length === 1 || !started) return;
      if (intervalId) clearInterval(intervalId);
      intervalId = setInterval(() => {
        showSlide((index + 1) % slides.length);
      }, 2000);
    }

    function pauseAutoRotation(durationMs) {
      if (reduced || slides.length === 1 || !started) return;
      if (intervalId) {
        clearInterval(intervalId);
        intervalId = null;
      }
      if (resumeTimerId) clearTimeout(resumeTimerId);
      resumeTimerId = setTimeout(() => {
        resumeTimerId = null;
        restartAutoRotation();
      }, durationMs);
    }

    function bindDots() {
      if (!dots.length) return;
      dots.forEach((dot) => {
        dot.addEventListener('click', () => {
          const dotStep = Number(dot.dataset.step || 1) - 1;
          showSlide(dotStep);
          pauseAutoRotation(7000);
        });
      });
    }

    function start() {
      if (!started) {
        started = true;
        showInitial();
      }
      restartAutoRotation();
    }

    function stop() {
      if (intervalId) {
        clearInterval(intervalId);
        intervalId = null;
      }
      if (resumeTimerId) {
        clearTimeout(resumeTimerId);
        resumeTimerId = null;
      }
    }

    bindDots();
    if (reduced) {
      showInitial();
      return;
    }

    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              start();
            } else {
              stop();
            }
          });
        },
        { threshold: 0.3 }
      );

      observer.observe(stage);
    } else {
      start();
    }
  }

  carousels.forEach((carousel) => initCarousel(carousel));
})();

/* --- Latest release fetch --- */
(function () {
  const releaseTargets = Array.from(document.querySelectorAll('#latest-version'));
  const downloadButtons = Array.from(
    document.querySelectorAll('a.cta-button[href*="github.com/Kruszoneq/macUSB/releases"]')
  );
  if (!releaseTargets.length && !downloadButtons.length) return;
  const userAgent = navigator.userAgent || '';
  const isIPadDesktopMode = /Macintosh/.test(userAgent) && navigator.maxTouchPoints > 1;
  const isMobileOrTablet =
    /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|Tablet/i.test(userAgent) ||
    isIPadDesktopMode;

  fetch('https://api.github.com/repos/Kruszoneq/macUSB/releases/latest')
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    })
    .then((data) => {
      releaseTargets.forEach((node) => {
        node.textContent = `Latest version: ${data.tag_name}`;
        node.style.opacity = '1';
      });

      const latestDmgAsset = Array.isArray(data.assets)
        ? data.assets.find((asset) => /\.dmg$/i.test(asset.name || ''))
        : null;

      if (!isMobileOrTablet && latestDmgAsset && latestDmgAsset.browser_download_url) {
        downloadButtons.forEach((button) => {
          button.href = latestDmgAsset.browser_download_url;
        });
      }
    })
    .catch((error) => {
      console.log('Version fetch error:', error);
      releaseTargets.forEach((node) => {
        node.textContent = 'Latest release';
        node.style.opacity = '0.9';
      });
    });
})();

/* --- Lightbox for docs + app images --- */
(function () {
  function ensureLightbox() {
    let lightbox = document.querySelector('.lightbox');
    if (lightbox) return lightbox;

    lightbox = document.createElement('div');
    lightbox.className = 'lightbox';
    lightbox.hidden = true;
    lightbox.setAttribute('role', 'dialog');
    lightbox.setAttribute('aria-modal', 'true');
    lightbox.setAttribute('aria-label', 'Image preview');

    lightbox.innerHTML = `
      <button class="lightbox-close" type="button" aria-label="Close preview" title="Close">
        <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M7 7l10 10M17 7 7 17" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
      <div class="lightbox-content">
        <img class="lightbox-img" alt="" />
        <p class="lightbox-caption"></p>
      </div>
    `;

    document.body.appendChild(lightbox);
    return lightbox;
  }

  function openLightbox(src, alt) {
    const lightbox = ensureLightbox();
    const image = lightbox.querySelector('.lightbox-img');
    const caption = lightbox.querySelector('.lightbox-caption');

    image.src = src;
    image.alt = alt || 'Screenshot preview';
    caption.textContent = alt || '';

    lightbox.hidden = false;
    document.body.style.overflow = 'hidden';

    const closeButton = lightbox.querySelector('.lightbox-close');
    if (closeButton) closeButton.focus();
  }

  function closeLightbox() {
    const lightbox = document.querySelector('.lightbox');
    if (!lightbox || lightbox.hidden) return;

    const image = lightbox.querySelector('.lightbox-img');
    if (image) image.src = '';

    lightbox.hidden = true;
    document.body.style.overflow = '';
  }

  function bind() {
    const images = document.querySelectorAll('img.guide-image, img.zoom-image');
    images.forEach((image) => {
      if (image.dataset.zoomBound === '1') return;
      image.dataset.zoomBound = '1';

      image.addEventListener('click', () => {
        openLightbox(image.currentSrc || image.src, image.alt || '');
      });
    });

    const lightbox = ensureLightbox();

    lightbox.addEventListener('click', (event) => {
      if (event.target === lightbox) closeLightbox();
    });

    const closeButton = lightbox.querySelector('.lightbox-close');
    if (closeButton) closeButton.addEventListener('click', closeLightbox);

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') closeLightbox();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();

/* --- Auto TOC + scroll spy (for long guide pages) --- */
(function () {
  function initAutoTOCAndSpy() {
    const layouts = document.querySelectorAll('.page-layout');
    if (!layouts.length) return;

    layouts.forEach((layout) => {
      if (layout.dataset.tocInit === '1') return;
      layout.dataset.tocInit = '1';

      const toc = layout.querySelector('.page-toc-sidebar');
      const content = layout.querySelector('.page-content') || document.querySelector('.page');
      if (!toc || !content) return;

      const headings = Array.from(content.querySelectorAll('.page-section > h2'));
      if (!headings.length) return;

      const list = document.createElement('ul');
      list.className = 'page-toc-list';
      const items = [];

      headings.forEach((heading) => {
        const section = heading.closest('.page-section');
        if (!section) return;

        const id = section.getAttribute('id');
        if (!id) return;

        const anchor = document.createElement('a');
        anchor.href = `#${id}`;
        anchor.textContent = heading.textContent.trim();

        const item = document.createElement('li');
        item.appendChild(anchor);
        list.appendChild(item);

        items.push({ id, link: anchor, section });
      });

      const existing = toc.querySelector('.page-toc-list');
      if (existing) existing.remove();
      toc.appendChild(list);

      function setActive(id) {
        items.forEach((item) => {
          if (item.id === id) {
            item.link.classList.add('is-active');
            item.link.setAttribute('aria-current', 'location');
          } else {
            item.link.classList.remove('is-active');
            item.link.removeAttribute('aria-current');
          }
        });
      }

      function getNavHeight() {
        const raw = getComputedStyle(document.documentElement).getPropertyValue('--nav-height');
        const value = parseFloat(raw);
        return Number.isFinite(value) ? value : 72;
      }

      let rafId = null;

      function computeActiveFromScroll() {
        const y = window.scrollY + getNavHeight() + 18;

        let current = items[0] ? items[0].id : null;
        items.forEach((item) => {
          const top = item.section.getBoundingClientRect().top + window.scrollY;
          if (top <= y) current = item.id;
        });

        if (current) setActive(current);
      }

      function onScroll() {
        if (rafId) return;
        rafId = requestAnimationFrame(() => {
          rafId = null;
          computeActiveFromScroll();
        });
      }

      if (window.location.hash) {
        const initialId = window.location.hash.replace('#', '');
        if (items.some((item) => item.id === initialId)) {
          setActive(initialId);
        }
      }

      computeActiveFromScroll();
      window.addEventListener('scroll', onScroll, { passive: true });
      window.addEventListener('resize', onScroll);
      window.addEventListener('hashchange', () => {
        const id = window.location.hash.replace('#', '');
        if (items.some((item) => item.id === id)) setActive(id);
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAutoTOCAndSpy);
  } else {
    initAutoTOCAndSpy();
  }

  window.addEventListener('load', initAutoTOCAndSpy);
})();
