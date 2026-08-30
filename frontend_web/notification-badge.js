/**
 * notification-badge.js
 * ----------------------
 * شارة تنبيه حمراء متوهجة تُظهر عدد طلبات الحجز الواردة من المرضى عبر صفحة
 * الحجز العامة (booking.html) التي ما زالت بانتظار رد الطبيب (قبول/رفض) --
 * تُرسم فوق زر "المواعيد اليومية" في شريط التنقل (النسخة المكتبية والقائمة
 * المنسدلة على الجوال معاً) في كل صفحة ما عدا appointments.html نفسها، لأن
 * تلك الصفحة تعرض هذه الطلبات مباشرة في لوحتها الخاصة أعلاها.
 *
 * تُحدَّث الشارة عبر استطلاع دوري للخادم (كل 25 ثانية) وأيضاً عند عودة
 * المستخدم إلى التبويب (visibilitychange)، فتختفي وحدها بمجرد أن يردّ
 * الطبيب على الطلب من appointments.html.
 *
 * يعتمد على window.apiUrl من api-config.js ورمز الدخول المخزّن في
 * localStorage باسم authToken (نفس النمط المستخدم في كل الصفحات). أدرجه
 * بعد api-config.js مباشرة:
 *   <script src="api-config.js"></script>
 *   <script src="notification-badge.js"></script>
 */
(function () {
  var currentPage = (window.location.pathname.split('/').pop() || '').toLowerCase();
  if (currentPage === 'appointments.html') return;

  var POLL_INTERVAL_MS = 25000;
  var pollTimer = null;

  function injectStyles() {
    if (document.getElementById('nav-notify-badge-styles')) return;
    var style = document.createElement('style');
    style.id = 'nav-notify-badge-styles';
    style.textContent = [
      '.nav-notify-badge{position:absolute;top:-7px;right:-7px;min-width:20px;height:20px;padding:0 5px;',
      'display:flex;align-items:center;justify-content:center;border-radius:999px;',
      'background:linear-gradient(135deg,#f87171 0%,#dc2626 100%);color:#fff;',
      'font-size:11px;line-height:1;font-weight:800;font-family:inherit;direction:ltr;',
      'border:2px solid #1e1b4b;box-shadow:0 0 0 1px rgba(248,113,113,.35),0 0 14px rgba(220,38,38,.85);',
      'animation:navNotifyPulse 1.6s ease-in-out infinite;pointer-events:none;z-index:5;}',
      '@keyframes navNotifyPulse{',
      '0%,100%{box-shadow:0 0 0 1px rgba(248,113,113,.35),0 0 14px rgba(220,38,38,.85);transform:scale(1);}',
      '50%{box-shadow:0 0 0 1px rgba(248,113,113,.5),0 0 20px rgba(220,38,38,1);transform:scale(1.08);}}',
    ].join('\n');
    document.head.appendChild(style);
  }

  function getAppointmentNavLinks() {
    return Array.prototype.slice.call(document.querySelectorAll('a[href="appointments.html"]'));
  }

  function renderBadge(count) {
    var links = getAppointmentNavLinks();
    links.forEach(function (link) {
      var badge = link.querySelector(':scope > .nav-notify-badge');
      if (!count || count <= 0) {
        if (badge) badge.remove();
        return;
      }
      if (window.getComputedStyle(link).position === 'static') {
        link.style.position = 'relative';
      }
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'nav-notify-badge';
        link.appendChild(badge);
      }
      badge.textContent = count > 99 ? '99+' : String(count);
      badge.setAttribute('aria-label', 'لديك ' + count + ' طلب حجز جديد بانتظار الرد');
    });
  }

  function fetchPendingCount() {
    var token = String(localStorage.getItem('authToken') || '').trim();
    if (!token || typeof window.apiUrl !== 'function') return;
    var headers = { Authorization: token.startsWith('Bearer ') ? token : 'Bearer ' + token };
    fetch(window.apiUrl('/api/appointments/pending-count'), { headers: headers })
      .then(function (res) {
        return res.ok ? res.json() : null;
      })
      .then(function (data) {
        if (data && typeof data.count === 'number') {
          injectStyles();
          renderBadge(data.count);
        }
      })
      .catch(function () {
        // صمت -- خطأ شبكة عابر هنا لا يستحق إزعاج المستخدم بأي رسالة.
      });
  }

  function startPolling() {
    fetchPendingCount();
    if (pollTimer) window.clearInterval(pollTimer);
    pollTimer = window.setInterval(fetchPendingCount, POLL_INTERVAL_MS);
  }

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') fetchPendingCount();
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startPolling);
  } else {
    startPolling();
  }
})();
