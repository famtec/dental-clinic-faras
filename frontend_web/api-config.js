(function () {
  const storedBase = localStorage.getItem('apiBaseUrlOverride');
  const apiBaseUrl = storedBase ? storedBase.trim().replace(/\/+$/, '') : '';
  const storedGoogleClientId = localStorage.getItem('googleClientIdOverride');
  const googleClientId = storedGoogleClientId ? storedGoogleClientId.trim() : '';

  window.DENTAL_APP_CONFIG = {
    apiBaseUrl,
    googleClientId,
  };

  window.apiUrl = function apiUrl(path) {
    const normalizedPath = String(path || '').startsWith('/') ? String(path) : '/' + String(path || '');
    return apiBaseUrl ? apiBaseUrl + normalizedPath : normalizedPath;
  };
})();
