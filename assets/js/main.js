/* --- NAVBAR INCLUDE + POST-INJECT INIT --- */
(function () {
  const mount = document.getElementById('navbar');
  if (!mount) return;

  // Support both:
  // - GitHub Pages: https://kruszoneq.github.io/macUSB/...  -> basePrefix = '/macUSB'
  // - Local dev server from repo root: http://localhost:.../ -> basePrefix = ''
  const basePrefix = window.location.pathname.includes('/macUSB/') ? '/macUSB' : '';
  const partialUrl = `${basePrefix}/pages/partials.html`;

  function initAfterNavbarInjected() {
    // Keep CSS viewport units in sync with the *actual* window height (mobile address bar, etc.)
    function updateViewportMetrics() {
      document.documentElement.style.setProperty('--vh', `${window.innerHeight * 0.01}px`);
      const nav = document.querySelector('nav');
      if (nav) {
        document.documentElement.style.setProperty('--nav-height', `${nav.offsetHeight}px`);
      }
      const header = document.querySelector('.page-header');
      if (header) {
        document.documentElement.style.setProperty(
          '--page-header-offset',
          `${header.offsetTop}px`
        );
      }
    }

    updateViewportMetrics();
    window.addEventListener('resize', updateViewportMetrics);

    // Use a slightly larger threshold for smoother trigger
    window.addEventListener('scroll', () => {
      if (window.scrollY > 30) {
        document.body.classList.add('scrolled');
      } else {
        document.body.classList.remove('scrolled');
      }
      // nav height changes between states; keep spacing correct
      updateViewportMetrics();
    });

    // --- Theme: system auto + manual override (Light / Dark / Auto) ---
    (function () {
      const STORAGE_KEY = 'macusb-theme'; // 'auto' | 'light' | 'dark'
      const toggle = document.getElementById('theme-toggle');
      if (!toggle) return;

      const icons = {
        light: `
          <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M12 18a6 6 0 1 0 0-12 6 6 0 0 0 0 12Z" stroke="currentColor" stroke-width="1.8"/>
            <path d="M12 2v2.6M12 19.4V22M2 12h2.6M19.4 12H22M4.2 4.2l1.8 1.8M18 18l1.8 1.8M19.8 4.2 18 6M6 18l-1.8 1.8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>`,
        dark: `
          <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M21 14.5A7.5 7.5 0 0 1 9.5 3a6.5 6.5 0 1 0 11.5 11.5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
          </svg>`,
        auto: `
          <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z" stroke="currentColor" stroke-width="1.8"/>
            <path d="M9.2 15.4 12 8.6l2.8 6.8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M10.2 13.2h3.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>`
      };

      const media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

      function systemTheme() {
        return media && media.matches ? 'dark' : 'light';
      }

      function applyMode(mode) {
        if (mode === 'light') {
          document.body.setAttribute('data-theme', 'light');
        } else if (mode === 'dark') {
          document.body.setAttribute('data-theme', 'dark');
        } else {
          document.body.removeAttribute('data-theme');
        }

        const effective = mode === 'auto' ? systemTheme() : mode;
        toggle.innerHTML = mode === 'auto' ? icons.auto : (effective === 'dark' ? icons.dark : icons.light);
        const label = mode === 'auto' ? 'Theme: Auto' : `Theme: ${effective.charAt(0).toUpperCase() + effective.slice(1)}`;
        toggle.setAttribute('aria-label', label);
        toggle.setAttribute('title', label);
      }

      function nextMode(current) {
        if (current === 'auto') return 'dark';
        if (current === 'dark') return 'light';
        return 'auto';
      }

      const saved = localStorage.getItem(STORAGE_KEY);
      const initial = (saved === 'light' || saved === 'dark' || saved === 'auto') ? saved : 'auto';
      applyMode(initial);

      toggle.addEventListener('click', () => {
        const current = localStorage.getItem(STORAGE_KEY) || 'auto';
        const mode = nextMode(current);
        localStorage.setItem(STORAGE_KEY, mode);
        applyMode(mode);
      });

      if (media) {
        media.addEventListener('change', () => {
          const mode = localStorage.getItem(STORAGE_KEY) || 'auto';
          if (mode === 'auto') applyMode('auto');
        });
      }
    })();

    // --- Guides dropdown (hover on desktop, click on touch/mobile + keyboard support) ---
    (function () {
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
        if (!open) {
          navGuides.classList.add('is-open');
          trigger.setAttribute('aria-expanded', 'true');
          open = true;
        }
      }

      function closeDropdown() {
        if (open) {
          navGuides.classList.remove('is-open');
          trigger.setAttribute('aria-expanded', 'false');
          open = false;
        }
      }

      trigger.addEventListener('click', (e) => {
        if (canHover()) return;
        open ? closeDropdown() : openDropdown();
        e.stopPropagation();
      });

      trigger.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          open ? closeDropdown() : openDropdown();
          if (!open) return;
          const firstItem = dropdown.querySelector('a,button,[tabindex]:not([tabindex="-1"])');
          if (firstItem) firstItem.focus();
        } else if (e.key === 'ArrowDown') {
          e.preventDefault();
          openDropdown();
          const firstItem = dropdown.querySelector('a,button,[tabindex]:not([tabindex="-1"])');
          if (firstItem) firstItem.focus();
        }
      });

      dropdown.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          closeDropdown();
          trigger.focus();
        }
      });

      document.addEventListener('click', (e) => {
        if (!navGuides.contains(e.target)) closeDropdown();
      });

      navGuides.addEventListener('mouseenter', () => {
        if (canHover()) openDropdown();
      });

      navGuides.addEventListener('mouseleave', () => {
        if (canHover()) closeDropdown();
      });
    })();
  }

  fetch(partialUrl)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.text();
    })
    .then((html) => {
      const resolved = html.replaceAll('{{BASE}}', basePrefix);
      mount.innerHTML = resolved;
      initAfterNavbarInjected();
    })
    .catch((err) => console.error('Navbar load error:', err));
})();

// Scroll cue (hero -> screenshots)
const scrollCue = document.querySelector('.scroll-cue');
if (scrollCue) {
    scrollCue.addEventListener('click', () => {
        const target = document.getElementById('screenshots');
        if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
}

// --- App screenshots: auto-advancing carousel (starts when screenshots are visible) ---
(function () {
    const stage = document.querySelector('.screenshot-stage');
    if (!stage) return;

    const slides = Array.from(stage.querySelectorAll('img'))
        .sort((a, b) => Number(a.dataset.step || 0) - Number(b.dataset.step || 0));
    if (slides.length === 0) return;

    let index = 0;
    let intervalId = null;
    let started = false;

    function showInitial() {
        slides.forEach(img => img.classList.remove('is-active', 'is-exiting'));
        index = 0;
        slides[index].classList.add('is-active');
    }

    function start() {
        if (started) return;
        started = true;

        showInitial();

        const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (prefersReducedMotion || slides.length === 1) return;

        const INTERVAL_MS = 4500;
        intervalId = setInterval(() => {
            const current = slides[index];
            current.classList.remove('is-active');
            current.classList.add('is-exiting');

            index = (index + 1) % slides.length;
            const next = slides[index];
            next.classList.add('is-active');

            setTimeout(() => current.classList.remove('is-exiting'), 900);
        }, INTERVAL_MS);
    }

    function stop() {
        if (!intervalId) return;
        clearInterval(intervalId);
        intervalId = null;
    }

    // Start only when the screenshots section enters the viewport
    const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) {
        // still show first slide immediately
        showInitial();
        return;
    }

    if ('IntersectionObserver' in window) {
        const observer = new IntersectionObserver((entries) => {
            for (const entry of entries) {
                if (entry.isIntersecting) {
                    start();
                } else {
                    // optional: stop timer when not visible
                    stop();
                }
            }
        }, { threshold: 0.25 });

        observer.observe(stage);
    } else {
        // Fallback: start immediately
        start();
    }
})();

fetch('https://api.github.com/repos/Kruszoneq/macUSB/releases/latest')
    .then(response => {
        if (!response.ok) throw new Error('No release found');
        return response.json();
    })
    .then(data => {
        const versionElement = document.getElementById('latest-version');
        versionElement.textContent = `Latest version: ${data.tag_name}`;
        versionElement.style.opacity = 1;
    })
    .catch(error => { console.log('Version fetch error:', error); });

// --- Click-to-zoom for docs screenshots (.guide-image) ---
(function () {
  function ensureLightbox() {
    let lb = document.querySelector('.lightbox');
    if (lb) return lb;

    lb = document.createElement('div');
    lb.className = 'lightbox';
    lb.hidden = true;
    lb.setAttribute('role', 'dialog');
    lb.setAttribute('aria-modal', 'true');
    lb.setAttribute('aria-label', 'Image preview');

    lb.innerHTML = `
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

    document.body.appendChild(lb);
    return lb;
  }

  function openLightbox(src, alt) {
    const lb = ensureLightbox();
    const img = lb.querySelector('.lightbox-img');
    const cap = lb.querySelector('.lightbox-caption');

    img.src = src;
    img.alt = alt || 'Screenshot preview';
    cap.textContent = alt || '';

    lb.hidden = false;
    document.body.style.overflow = 'hidden';

    // focus close for accessibility
    const closeBtn = lb.querySelector('.lightbox-close');
    if (closeBtn) closeBtn.focus();
  }

  function closeLightbox() {
    const lb = document.querySelector('.lightbox');
    if (!lb || lb.hidden) return;

    const img = lb.querySelector('.lightbox-img');
    if (img) img.src = '';

    lb.hidden = true;
    document.body.style.overflow = '';
  }

  function bind() {
    const imgs = document.querySelectorAll('img.guide-image');
    imgs.forEach((img) => {
      if (img.dataset.zoomBound === '1') return;
      img.dataset.zoomBound = '1';

      img.addEventListener('click', () => {
        // Use currentSrc to support responsive images in the future
        openLightbox(img.currentSrc || img.src, img.alt || '');
      });
    });

    const lb = ensureLightbox();
    lb.addEventListener('click', (e) => {
      // close when clicking backdrop, not the image itself
      if (e.target === lb) closeLightbox();
    });

    const closeBtn = lb.querySelector('.lightbox-close');
    if (closeBtn) closeBtn.addEventListener('click', closeLightbox);

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeLightbox();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();

// --- Auto-generate TOC + highlight current section (ScrollSpy) ---
(function () {
  function initAutoTOCAndSpy() {
    // Support multiple docs pages; initialize each once.
    const layouts = document.querySelectorAll('.page-layout');
    if (!layouts.length) return;

    layouts.forEach((layout) => {
      if (layout.dataset.tocInit === '1') return;
      layout.dataset.tocInit = '1';

      const toc = layout.querySelector('.page-toc-sidebar');
      const content = layout.querySelector('.page-content') || document.querySelector('.page');
      if (!toc || !content) return;

      // Build TOC items from H2 headings inside sections.
      const headings = Array.from(content.querySelectorAll('.page-section > h2'));
      if (!headings.length) return;

      const list = document.createElement('ul');
      list.className = 'page-toc-list';

      const items = [];

      headings.forEach((h2) => {
        const section = h2.closest('.page-section');
        if (!section) return;
        const id = section.getAttribute('id');
        if (!id) return;

        const a = document.createElement('a');
        a.href = `#${id}`;
        a.textContent = h2.textContent.trim();

        const li = document.createElement('li');
        li.appendChild(a);
        list.appendChild(li);

        items.push({ id, link: a, section });
      });

      // Replace any existing TOC list, keep the title element.
      const existing = toc.querySelector('.page-toc-list');
      if (existing) existing.remove();
      toc.appendChild(list);

      function setActive(id) {
        items.forEach((it) => {
          if (it.id === id) {
            it.link.classList.add('is-active');
            it.link.setAttribute('aria-current', 'location');
          } else {
            it.link.classList.remove('is-active');
            it.link.removeAttribute('aria-current');
          }
        });
      }

      // ScrollSpy (stable): pick the last section whose top has passed under the fixed nav.
      // This avoids jitter where the previous section is still "intersecting".
      function getNavHeight() {
        const v = getComputedStyle(document.documentElement).getPropertyValue('--nav-height');
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 72;
      }

      let rafId = null;

      function computeActiveFromScroll() {
        const navH = getNavHeight();
        const y = window.scrollY + navH + 18; // small comfort offset

        let current = items[0]?.id;
        for (const it of items) {
          const top = it.section.getBoundingClientRect().top + window.scrollY;
          if (top <= y) current = it.id;
        }
        if (current) setActive(current);
      }

      function onScroll() {
        if (rafId) return;
        rafId = requestAnimationFrame(() => {
          rafId = null;
          computeActiveFromScroll();
        });
      }

      // Initial state (supports deep links too)
      if (window.location.hash) {
        const initialId = window.location.hash.replace('#', '');
        if (items.some((it) => it.id === initialId)) {
          setActive(initialId);
        }
      }
      computeActiveFromScroll();

      window.addEventListener('scroll', onScroll, { passive: true });
      window.addEventListener('resize', onScroll);

      window.addEventListener('hashchange', () => {
        const id = window.location.hash.replace('#', '');
        if (items.some((it) => it.id === id)) {
          setActive(id);
        }
      });
    });
  }

  // Run on DOM ready.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAutoTOCAndSpy);
  } else {
    initAutoTOCAndSpy();
  }

  // Also re-run after navbar is injected (it updates --nav-height).
  // Safe due to per-layout dataset guard.
  window.addEventListener('load', initAutoTOCAndSpy);
})();
         