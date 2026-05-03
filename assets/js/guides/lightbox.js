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
