// Service worker registration.
// Allowed contexts: HTTPS and localhost (browsers treat localhost as secure,
// which means Push API and Notifications work in dev too).
export function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return Promise.resolve(null);

  const host = window.location.hostname;
  const isLocalhost = host === "localhost" || host === "127.0.0.1";

  if (window.location.protocol !== "https:" && !isLocalhost) {
    return Promise.resolve(null);
  }

  return navigator.serviceWorker.register("/sw.js").catch((err) => {
    console.warn("[pwa] service worker registration failed", err);
    return null;
  });
}
