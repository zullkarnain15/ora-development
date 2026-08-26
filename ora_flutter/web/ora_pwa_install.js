'use strict';

(function initializeOraPwaInstall() {
  let deferredPrompt = null;
  let installed = false;

  const isStandalone = () => installed ||
    window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;

  const notifyStateChanged = () => {
    window.dispatchEvent(new Event('ora-pwa-install-state-changed'));
  };

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    notifyStateChanged();
  });

  window.addEventListener('appinstalled', () => {
    installed = true;
    deferredPrompt = null;
    notifyStateChanged();
  });

  window.oraIsPwaStandalone = () => isStandalone();
  window.oraCanPromptPwaInstall = () => deferredPrompt !== null && !isStandalone();
  window.oraPromptPwaInstall = async () => {
    if (!deferredPrompt || isStandalone()) return 'unavailable';
    const prompt = deferredPrompt;
    await prompt.prompt();
    const choice = await prompt.userChoice;
    // A captured prompt can only be used once. A later eligible event will
    // supply a fresh prompt if the user dismissed this one.
    deferredPrompt = null;
    notifyStateChanged();
    return choice && choice.outcome ? choice.outcome : 'dismissed';
  };
})();
