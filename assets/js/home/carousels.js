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
