(function () {
  const storedBase = localStorage.getItem('apiBaseUrlOverride');
  const apiBaseUrl = storedBase ? storedBase.trim().replace(/\/+$/, '') : '';

  window.DENTAL_APP_CONFIG = {
    apiBaseUrl,
  };

  window.apiUrl = function apiUrl(path) {
    const normalizedPath = String(path || '').startsWith('/') ? String(path) : '/' + String(path || '');
    return apiBaseUrl ? apiBaseUrl + normalizedPath : normalizedPath;
  };
})();
