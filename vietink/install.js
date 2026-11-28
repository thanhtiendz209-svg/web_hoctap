(() => {
  'use strict';

  const button = document.getElementById('install');
  let installRequest;

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installRequest = event;
    button.hidden = false;
  });

  button.addEventListener('click', async () => {
    const request = installRequest;
    if (!request) return;
    installRequest = undefined;
    button.hidden = true;
    try {
      await request.prompt();
    } catch (error) {
      console.warn('Ink Study could not open the installation prompt.', error);
    }
  });

  window.addEventListener('appinstalled', () => {
    installRequest = undefined;
    button.hidden = true;
  });

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js', { updateViaCache: 'none' })
      .catch((error) => console.warn('Ink Study offline setup failed.', error));
  }
})();
