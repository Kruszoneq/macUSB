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
