{{flutter_js}}
{{flutter_build_config}}

const oraServiceWorkerVersion = {{flutter_service_worker_version}};
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: oraServiceWorkerVersion,
    serviceWorkerUrl: `ora_service_worker.js?v=${oraServiceWorkerVersion}`,
  },
});
