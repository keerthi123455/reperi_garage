{{flutter_js}}
{{flutter_build_config}}

// ---------------------------------------------------------------------------
// Reperi custom bootstrap
//
// Flutter's own service worker (flutter_service_worker.js) is deprecated and
// fights with OneSignal's push worker (OneSignalSDKWorker.js): both want the
// root scope "/", and a browser only allows ONE worker per scope. Each page
// load one replaced the other, the new worker took control of the page, and
// users got a blank screen stuck in a reload loop.
//
// So we:
//   1. load Flutter WITHOUT registering its service worker, and
//   2. clean up any old Flutter worker + caches left on returning visitors'
//      browsers (OneSignal's worker is never touched).
// ---------------------------------------------------------------------------
(function cleanUpOldFlutterServiceWorker() {
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        regs.forEach(function (reg) {
          var workers = [reg.installing, reg.waiting, reg.active].filter(Boolean);
          var hasOneSignal = workers.some(function (w) {
            return w.scriptURL.indexOf('OneSignalSDK') !== -1;
          });
          var hasFlutter = workers.some(function (w) {
            return w.scriptURL.indexOf('flutter_service_worker') !== -1;
          });
          // Only remove a registration that is purely Flutter's. If OneSignal
          // is already installing/active in it, OneSignal takes it over.
          if (hasFlutter && !hasOneSignal) {
            reg.unregister();
          }
        });
      }).catch(function () {});
    }

    if ('caches' in window) {
      caches.keys().then(function (keys) {
        keys.forEach(function (key) {
          if (key.indexOf('flutter-') === 0) {
            caches.delete(key);
          }
        });
      }).catch(function () {});
    }
  } catch (e) {
    // Never block app start-up over cleanup.
  }
})();

// No serviceWorkerSettings => Flutter does not register its service worker.
_flutter.loader.load();
