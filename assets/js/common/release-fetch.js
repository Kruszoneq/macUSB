/* --- Latest release fetch --- */
(function () {
  let latestVersionLabel = null;
  let latestDmgUrl = null;
  let fetchFailed = false;

  function getReleaseTargets() {
    return Array.from(document.querySelectorAll('[data-latest-version]'));
  }

  function getDownloadButtons() {
    return Array.from(document.querySelectorAll('a.cta-button[href*="github.com/Kruszoneq/macUSB/releases"]'));
  }

  function renderVersionTargets() {
    const releaseTargets = getReleaseTargets();
    releaseTargets.forEach((node) => {
      if (latestVersionLabel) {
        node.textContent = latestVersionLabel;
        node.style.opacity = '1';
      } else if (fetchFailed) {
        node.textContent = 'Latest release';
        node.style.opacity = '0.9';
      }
    });
  }

  function updateDownloadButtons(isMobileOrTablet) {
    if (!latestDmgUrl || isMobileOrTablet) return;
    const downloadButtons = getDownloadButtons();
    downloadButtons.forEach((button) => {
      button.href = latestDmgUrl;
    });
  }

  if (!getReleaseTargets().length && !getDownloadButtons().length) return;
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
      latestVersionLabel = `Latest version: ${data.tag_name}`;
      renderVersionTargets();

      const latestDmgAsset = Array.isArray(data.assets)
        ? data.assets.find((asset) => /\.dmg$/i.test(asset.name || ''))
        : null;
      latestDmgUrl = latestDmgAsset && latestDmgAsset.browser_download_url ? latestDmgAsset.browser_download_url : null;

      updateDownloadButtons(isMobileOrTablet);
    })
    .catch((error) => {
      console.log('Version fetch error:', error);
      fetchFailed = true;
      renderVersionTargets();
    });

  document.addEventListener('partial:loaded', () => {
    renderVersionTargets();
    updateDownloadButtons(isMobileOrTablet);
  });
})();
