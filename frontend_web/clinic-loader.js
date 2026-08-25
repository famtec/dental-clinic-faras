/**
 * clinic-loader.js
 * -----------------
 * Shared "tooth" loading indicator used across the clinic's pages whenever
 * the user adds or deletes something (patient, payment, appointment,
 * inventory item, ...). Two patterns:
 *
 *   1. Button loader  — ClinicLoader.setButtonLoading(btn, true, {loadingText})
 *      Disables the button, swaps its content for a small tooth icon that
 *      fills with color + a reassuring label. Call again with `false` to
 *      restore the button exactly as it was.
 *
 *   2. Overlay loader — ClinicLoader.showOverlay(container, {title, subtitle})
 *      Lays a light, semi-transparent frosted panel over a table/section
 *      (e.g. while a list re-fetches after an add/delete), with a bigger
 *      ring + tooth loader. ClinicLoader.hideOverlay(container) removes it.
 *
 * Include with a single <script src="clinic-loader.js"></script> — it
 * injects its own <style> block on first load, so no CSS file changes are
 * needed on any page.
 */
(function () {
  if (window.ClinicLoader) return; // avoid double-init if included twice

  var TOOTH_PATH =
    'M12 2.4c-2.7 0-5 1.4-5 4.3 0 1.4.3 2.6.5 3.8.3 1.7.6 3.4 1.1 5.1.3 1.2.8 2.8 1.7 3.3.8.4 1.1-.5 1.4-1.2.3-.9.4-2.1.8-2.1s.5 1.2.8 2.1c.2.7.6 1.6 1.4 1.2.9-.5 1.4-2.1 1.7-3.3.5-1.7.8-3.4 1.1-5.1.2-1.2.5-2.4.5-3.8 0-2.9-2.3-4.3-5-4.3z';

  var uid = 0;
  function nextId(prefix) {
    uid += 1;
    return prefix + '-' + Date.now().toString(36) + '-' + uid;
  }

  function injectStyles() {
    if (document.getElementById('clinic-loader-styles')) return;
    var style = document.createElement('style');
    style.id = 'clinic-loader-styles';
    style.textContent = [
      '.clinic-tooth-icon{display:inline-flex;flex:none;vertical-align:middle;}',
      '.clinic-tooth-icon svg{display:block;}',
      '.clinic-tooth-fill{animation:clinicToothRise 1.7s ease-in-out infinite;transform-origin:center;}',
      '@keyframes clinicToothRise{0%{transform:translateY(0);}55%{transform:translateY(-24px);}100%{transform:translateY(0);}}',

      '.clinic-btn-loading{cursor:not-allowed !important;opacity:.88;pointer-events:none;}',
      '.clinic-btn-loading .clinic-btn-loading-inner{display:inline-flex;align-items:center;gap:9px;}',
      '@keyframes clinicSoftGlow{0%,100%{filter:brightness(1);}50%{filter:brightness(1.08);}}',
      '.clinic-btn-loading{animation:clinicSoftGlow 1.8s ease-in-out infinite;}',

      '.clinic-reassure-text{display:inline-block;animation:clinicFadeSlideIn 420ms cubic-bezier(.2,.9,.2,1) both,clinicBreathe 2.6s ease-in-out 420ms infinite;}',
      '@keyframes clinicFadeSlideIn{from{opacity:0;transform:translateY(5px);}to{opacity:1;transform:translateY(0);}}',
      '@keyframes clinicBreathe{0%,100%{opacity:1;}50%{opacity:.72;}}',

      '.clinic-overlay{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;',
      'background:rgba(255,255,255,.72);backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px);',
      'border-radius:inherit;z-index:40;opacity:0;transition:opacity 180ms ease;}',
      '.clinic-overlay.is-visible{opacity:1;}',

      '.clinic-overlay-card{width:min(320px,86%);border-radius:24px;border:1px solid rgba(255,255,255,.85);',
      'background:rgba(255,255,255,.97);box-shadow:0 24px 60px rgba(49,46,129,.2);padding:28px 24px 24px;text-align:center;',
      'font-family:"Tajawal",system-ui,sans-serif;}',

      '.clinic-loader-wrap{position:relative;width:72px;height:72px;margin:0 auto 16px;}',
      '.clinic-loader-track{position:absolute;inset:0;border-radius:50%;border:6px solid #eef2ff;}',
      '.clinic-loader-ring{position:absolute;inset:0;border-radius:50%;',
      'background:conic-gradient(from 0deg,#4f46e5,#7c3aed 55%,transparent 78%);',
      '-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 calc(100% - 6px));',
      'mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 calc(100% - 6px));',
      'animation:clinicRingSpin 2.1s linear infinite;}',
      '@keyframes clinicRingSpin{to{transform:rotate(360deg);}}',
      '.clinic-loader-core{position:absolute;inset:11px;border-radius:50%;background:#fff;',
      'box-shadow:0 10px 22px rgba(79,70,229,.18),inset 0 0 0 1px #eef2ff;display:flex;align-items:center;justify-content:center;',
      'animation:clinicCoreBreathe 2.6s ease-in-out infinite;}',
      '@keyframes clinicCoreBreathe{0%,100%{transform:scale(1);}50%{transform:scale(1.035);}}',

      '.clinic-overlay-title{margin:0 0 4px;font-size:15px;font-weight:800;color:#1e293b;}',
      '.clinic-overlay-sub{margin:0;font-size:12px;line-height:1.8;color:#94a3b8;}',
      '.clinic-overlay-dots{display:flex;align-items:center;justify-content:center;gap:6px;margin-top:12px;}',
      '.clinic-overlay-dots span{width:6px;height:6px;border-radius:50%;',
      'background:linear-gradient(135deg,#4f46e5,#7c3aed);animation:clinicDotBounce 1.3s ease-in-out infinite;}',
      '.clinic-overlay-dots span:nth-child(2){animation-delay:.16s;}',
      '.clinic-overlay-dots span:nth-child(3){animation-delay:.32s;}',
      '@keyframes clinicDotBounce{0%,80%,100%{transform:translateY(0);opacity:.5;}40%{transform:translateY(-5px);opacity:1;}}',
    ].join('\n');
    document.head.appendChild(style);
  }

  function toothIconMarkup(sizePx, fillColor) {
    var gid = nextId('cg');
    var cid = nextId('cc');
    var useGradient = fillColor === 'gradient';
    var fillDef = useGradient
      ? '<linearGradient id="' + gid + '" x1="0" y1="1" x2="1" y2="0">' +
        '<stop offset="0%" stop-color="#4f46e5"/><stop offset="100%" stop-color="#7c3aed"/></linearGradient>'
      : '';
    var fillRef = useGradient ? 'url(#' + gid + ')' : (fillColor || '#ffffff');
    return (
      '<span class="clinic-tooth-icon" aria-hidden="true">' +
      '<svg width="' + sizePx + '" height="' + sizePx + '" viewBox="0 0 24 24">' +
      '<defs>' + fillDef +
      '<clipPath id="' + cid + '"><path d="' + TOOTH_PATH + '"/></clipPath>' +
      '</defs>' +
      '<path d="' + TOOTH_PATH + '" fill="rgba(255,255,255,0.32)"/>' +
      '<g clip-path="url(#' + cid + ')">' +
      '<rect class="clinic-tooth-fill" x="0" y="24" width="24" height="24" fill="' + fillRef + '"/>' +
      '</g>' +
      '</svg>' +
      '</span>'
    );
  }

  /**
   * Toggle a button between its normal state and a disabled "loading" state
   * with a tooth-fill icon + reassuring label.
   *
   * @param {HTMLButtonElement} button
   * @param {boolean} isLoading
   * @param {{loadingText?: string, iconColor?: string, iconSize?: number}} [options]
   */
  function setButtonLoading(button, isLoading, options) {
    if (!button) return;
    injectStyles();
    options = options || {};

    if (isLoading) {
      if (button.dataset.clinicOriginalHtml === undefined) {
        button.dataset.clinicOriginalHtml = button.innerHTML;
      }
      if (button.dataset.clinicOriginalDisabled === undefined) {
        button.dataset.clinicOriginalDisabled = button.disabled ? '1' : '0';
      }

      var iconSize = options.iconSize || 15;
      var iconColor = options.iconColor || '#ffffff';
      var label = options.loadingText || '...جاري المعالجة';

      button.disabled = true;
      button.setAttribute('aria-busy', 'true');
      button.classList.add('clinic-btn-loading');
      button.innerHTML =
        '<span class="clinic-btn-loading-inner">' +
        toothIconMarkup(iconSize, iconColor) +
        '<span class="clinic-reassure-text">' + label + '</span>' +
        '</span>';
    } else {
      if (button.dataset.clinicOriginalHtml !== undefined) {
        button.innerHTML = button.dataset.clinicOriginalHtml;
        delete button.dataset.clinicOriginalHtml;
      }
      button.disabled = button.dataset.clinicOriginalDisabled === '1';
      delete button.dataset.clinicOriginalDisabled;
      button.removeAttribute('aria-busy');
      button.classList.remove('clinic-btn-loading');
    }
  }

  /**
   * Lay a light, semi-transparent overlay (ring + tooth loader + message)
   * over a container — use while a table/list re-fetches after an add or
   * delete, especially useful on slow connections.
   *
   * @param {HTMLElement} container - should be position:relative (or will be set to it)
   * @param {{title?: string, subtitle?: string}} [options]
   */
  function showOverlay(container, options) {
    if (!container) return;
    injectStyles();
    options = options || {};

    var existing = container.querySelector(':scope > .clinic-overlay');
    if (existing) {
      var t = existing.querySelector('.clinic-overlay-title');
      var s = existing.querySelector('.clinic-overlay-sub');
      if (t && options.title) t.textContent = options.title;
      if (s && options.subtitle) s.textContent = options.subtitle;
      return;
    }

    var computedPosition = window.getComputedStyle(container).position;
    if (computedPosition === 'static' || !computedPosition) {
      container.style.position = 'relative';
      container.dataset.clinicPositionPatched = '1';
    }

    var overlay = document.createElement('div');
    overlay.className = 'clinic-overlay';
    overlay.innerHTML =
      '<div class="clinic-overlay-card">' +
      '<div class="clinic-loader-wrap">' +
      '<div class="clinic-loader-track"></div>' +
      '<div class="clinic-loader-ring"></div>' +
      '<div class="clinic-loader-core">' + toothIconMarkup(30, 'gradient') + '</div>' +
      '</div>' +
      '<p class="clinic-overlay-title">' + (options.title || 'جاري تسجيل المريض...') + '</p>' +
      '<p class="clinic-overlay-sub">' + (options.subtitle || 'يرجى الانتظار قليلاً، نقوم بتحديث سجلات العيادة بأمان 🔒') + '</p>' +
      '<div class="clinic-overlay-dots"><span></span><span></span><span></span></div>' +
      '</div>';

    container.appendChild(overlay);
    requestAnimationFrame(function () {
      overlay.classList.add('is-visible');
    });
  }

  function hideOverlay(container) {
    if (!container) return;
    var overlay = container.querySelector(':scope > .clinic-overlay');
    if (!overlay) return;

    overlay.classList.remove('is-visible');
    window.setTimeout(function () {
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
      if (container.dataset.clinicPositionPatched === '1') {
        container.style.position = '';
        delete container.dataset.clinicPositionPatched;
      }
    }, 200);
  }

  window.ClinicLoader = {
    setButtonLoading: setButtonLoading,
    showOverlay: showOverlay,
    hideOverlay: hideOverlay,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectStyles);
  } else {
    injectStyles();
  }
})();
