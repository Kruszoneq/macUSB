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
