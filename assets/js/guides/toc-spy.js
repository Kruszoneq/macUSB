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
