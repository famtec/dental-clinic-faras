/**
 * web-push.js
 * -----------
 * إشعارات المتصفح للموقع (Firebase Web Push) -- أُضيف 2026-09-05.
 *
 * يجعل تذكيرات العيادة (وأي إشعار يرسله الخادم للطبيب) تصل إلى متصفح الطبيب
 * على حاسوبه حتى والموقع مغلق تماماً، تماماً كما تصل إلى تطبيق أندرويد.
 *
 * مبادئ التصميم هنا:
 *  - **لا نطلب الإذن تلقائياً عند فتح الصفحة إطلاقاً.** كروم يعاقب المواقع التي
 *    تفعل ذلك بحجب الطلب نهائياً وبشكل دائم، والطبيب حينها لا يستطيع التفعيل
 *    حتى لو أرادَه. الطلب يتم فقط عند ضغط الطبيب زر التفعيل في صفحة "حسابي".
 *  - عند تحميل أي صفحة نكتفي بتحديث الرمز بصمت إن كان الإذن ممنوحاً مسبقاً --
 *    رموز FCM تتغيّر من وقت لآخر، وبلا هذا التحديث تتوقف الإشعارات فجأة.
 *  - مكتبة Firebase تُحمَّل عند الحاجة فقط (lazy) بدل تحميل ~150KB في كل صفحة.
 *  - best-effort بالكامل: أي فشل هنا يُبتلع بصمت ولا يعطّل أي شيء في الصفحة.
 *
 * يعتمد على window.apiUrl من api-config.js ورمز الدخول المخزّن في localStorage
 * باسم authToken (نفس نمط notification-badge.js). أدرجه بعد api-config.js:
 *   <script src="api-config.js"></script>
 *   <script src="firebase-web-config.js"></script>
 *   <script src="web-push.js"></script>
 *
 * الواجهة العامة (تستخدمها profile.html):
 *   ClinicWebPush.getStatus()        -> 'unsupported' | 'not-configured' |
 *                                       'not-logged-in' | 'denied' |
 *                                       'default' | 'granted'
 *   ClinicWebPush.enable()           -> Promise<{ ok, status, message }>
 *   ClinicWebPush.disable()          -> Promise<{ ok, status, message }>
 *   ClinicWebPush.onStatusChange(fn) -> يُستدعى fn(status) عند كل تغيّر
 *
 * وواجهة ثانية خاصة بصفحة الحجز العامة (المريض، بلا تسجيل دخول) -- 2026-09-05:
 *   ClinicWebPush.getPublicStatus()
 *   ClinicWebPush.enableForBooking({ slug, phone }) -> Promise<{ ok, status, message }>
 * يحفظ رمز متصفح المريض على طلب حجزه ليصله إشعار بقرار الطبيب (قبول/رفض).
 */
(function () {
  var SDK_VERSION = '10.12.2';
  var SDK_BASE = 'https://www.gstatic.com/firebasejs/' + SDK_VERSION + '/';
  var SERVICE_WORKER_FILE = 'firebase-messaging-sw.js';

  var sdkLoadPromise = null;
  var messagingInstance = null;
  var statusListeners = [];

  // ---------------------------------------------------------------- أدوات
  function config() {
    return window.FIREBASE_WEB_CONFIG || {};
  }

  function vapidKey() {
    return String(window.FIREBASE_WEB_VAPID_KEY || '').trim();
  }

  function isConfigured() {
    var c = config();
    return !!(c.apiKey && c.projectId && c.messagingSenderId && c.appId && vapidKey());
  }

  function isSupported() {
    return (
      typeof window !== 'undefined' &&
      'Notification' in window &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      window.isSecureContext === true
    );
  }

  function authToken() {
    try {
      return String(localStorage.getItem('authToken') || '').trim();
    } catch (error) {
      return '';
    }
  }

  function getStatus() {
    if (!isSupported()) return 'unsupported';
    if (!isConfigured()) return 'not-configured';
    if (!authToken()) return 'not-logged-in';
    if (Notification.permission === 'denied') return 'denied';
    if (Notification.permission === 'granted') return 'granted';
    return 'default';
  }

  function notifyStatusListeners() {
    var status = getStatus();
    statusListeners.forEach(function (listener) {
      try {
        listener(status);
      } catch (error) {
        /* مستمع واحد معطوب لا يجب أن يُسقط البقية */
      }
    });
  }

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var existing = document.querySelector('script[src="' + src + '"]');
      if (existing) {
        if (existing.getAttribute('data-loaded') === '1') return resolve();
        existing.addEventListener('load', function () {
          resolve();
        });
        existing.addEventListener('error', reject);
        return undefined;
      }
      var script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.addEventListener('load', function () {
        script.setAttribute('data-loaded', '1');
        resolve();
      });
      script.addEventListener('error', function () {
        reject(new Error('تعذر تحميل ' + src));
      });
      document.head.appendChild(script);
      return undefined;
    });
  }

  function loadSdk() {
    if (sdkLoadPromise) return sdkLoadPromise;
    sdkLoadPromise = loadScript(SDK_BASE + 'firebase-app-compat.js').then(function () {
      return loadScript(SDK_BASE + 'firebase-messaging-compat.js');
    });
    return sdkLoadPromise;
  }

  function serviceWorkerUrl() {
    // مسار مطلق من جذر الموقع، وليس نسبياً -- مقصود: صفحة الحجز العامة تُخدَّم
    // عبر /d/<slug> (مسارين بالعمق)، فالمسار النسبي كان سيُحَلّ إلى
    // /d/firebase-messaging-sw.js غير الموجود. هذا بالضبط نفس الخطأ الذي عطّل
    // api-config.js في تلك الصفحة سابقاً (انظر التعليق في booking.html).
    // الجذر هو المكان الصحيح أصلاً: Service Worker لا يتحكم إلا بالصفحات ضمن
    // نطاق مساره، ونحن نريد نطاق الموقع كله.
    return new URL('/' + SERVICE_WORKER_FILE, window.location.origin).href;
  }

  function getMessaging() {
    if (messagingInstance) return Promise.resolve(messagingInstance);
    return loadSdk().then(function () {
      if (!window.firebase || !window.firebase.messaging) {
        throw new Error('لم تُحمَّل مكتبة Firebase.');
      }
      if (!window.firebase.apps || !window.firebase.apps.length) {
        window.firebase.initializeApp(config());
      }
      messagingInstance = window.firebase.messaging();
      bindForegroundHandler(messagingInstance);
      return messagingInstance;
    });
  }

  // إشعار وصل والموقع مفتوح أمام الطبيب فعلاً: المتصفح لا يعرض إشعار النظام في
  // هذه الحالة، فنعرضه نحن كبطاقة داخل الصفحة بنفس هوية الموقع البصرية.
  var foregroundHandlerBound = false;
  function bindForegroundHandler(messaging) {
    if (foregroundHandlerBound) return;
    foregroundHandlerBound = true;
    try {
      messaging.onMessage(function (payload) {
        var notification = (payload && payload.notification) || {};
        // إشعارات الطبيب (حجز جديد / تذكير العيادة) وجهتها صفحة المواعيد -- نفس
        // وجهة إشعار الخلفية (webpush.fcm_options.link من main.py) ونفس وجهة
        // الإشعار في تطبيق أندرويد. أما إشعار المريض في صفحة الحجز العامة فلا
        // وجهة له (لا يملك حساباً ولا وصولاً لصفحة المواعيد)، فنعرض البطاقة
        // للقراءة فقط. وجود authToken هو ما يفرّق بين السياقين.
        showInPageNotification(
          notification.title || 'عيادتك الرقمية',
          notification.body || '',
          authToken() ? '/appointments.html' : null
        );
      });
    } catch (error) {
      /* صمت */
    }
  }

  function showInPageNotification(title, body, link) {
    var existing = document.getElementById('clinicWebPushToast');
    if (existing) existing.remove();

    var card = document.createElement('div');
    card.id = 'clinicWebPushToast';
    card.setAttribute('dir', 'rtl');
    card.style.cssText = [
      'position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:80;',
      'max-width:min(420px,calc(100vw - 32px));padding:14px 18px;border-radius:20px;',
      'background:linear-gradient(135deg,#4f46e5 0%,#312e81 100%);color:#fff;',
      'box-shadow:0 18px 40px rgba(49,46,129,.35);cursor:pointer;',
      'font-family:inherit;line-height:1.6;',
    ].join('');

    var titleEl = document.createElement('div');
    titleEl.style.cssText = 'font-weight:800;font-size:14px;margin-bottom:2px;';
    titleEl.textContent = title;

    var bodyEl = document.createElement('div');
    bodyEl.style.cssText = 'font-size:13px;opacity:.92;';
    bodyEl.textContent = body;

    card.appendChild(titleEl);
    card.appendChild(bodyEl);
    if (link) {
      card.addEventListener('click', function () {
        window.location.href = link;
      });
    } else {
      card.style.cursor = 'default';
      card.addEventListener('click', function () {
        card.remove();
      });
    }

    document.body.appendChild(card);
    window.setTimeout(function () {
      if (card.parentNode) card.remove();
    }, 8000);
  }

  // -------------------------------------------------- التخاطب مع الخادم
  function sendTokenToServer(webPushToken) {
    var token = authToken();
    if (!token || typeof window.apiUrl !== 'function') return Promise.resolve(false);
    return fetch(window.apiUrl('/api/auth/register-device'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: token.indexOf('Bearer ') === 0 ? token : 'Bearer ' + token,
      },
      body: JSON.stringify({ web_push_token: webPushToken }),
    })
      .then(function (response) {
        return response.ok;
      })
      .catch(function () {
        return false;
      });
  }

  // يسجّل الـ Service Worker ويستخرج رمز الجهاز من Firebase -- بلا أي إرسال
  // للخادم. الفصل مقصود: نفس الرمز يُسلَّم إما لمسار الطبيب الموثّق أو لمسار
  // المريض العام في صفحة الحجز، وكلاهما يشترك في هذه الخطوة حرفياً.
  function fetchWebPushToken() {
    return getMessaging().then(function (messaging) {
      return navigator.serviceWorker.register(serviceWorkerUrl(), { scope: '/' }).then(function (registration) {
        return messaging.getToken({
          vapidKey: vapidKey(),
          serviceWorkerRegistration: registration,
        });
      });
    });
  }

  function fetchAndRegisterToken() {
    return fetchWebPushToken().then(function (webPushToken) {
      if (!webPushToken) return false;
      return sendTokenToServer(webPushToken);
    });
  }

  // مسار المريض في صفحة الحجز العامة: لا يوجد تسجيل دخول للمريض إطلاقاً، والخادم
  // يتحقق من ملكية الطلب بمطابقة رقم الهاتف المطبَّع (نفس ضمانة "تحقق من حالة طلبي").
  function sendBookingTokenToServer(slug, phone, webPushToken) {
    if (typeof window.apiUrl !== 'function') return Promise.resolve(false);
    return fetch(window.apiUrl('/api/public/doctor/' + encodeURIComponent(slug) + '/booking-push'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone, web_push_token: webPushToken }),
    })
      .then(function (response) {
        return response.ok;
      })
      .catch(function () {
        return false;
      });
  }

  // ----------------------------------------------------- الواجهة العامة
  function enable() {
    var status = getStatus();

    if (status === 'unsupported') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'متصفحك الحالي لا يدعم إشعارات الويب. جرّب Chrome أو Edge على الحاسوب، أو استخدم تطبيق الجوال.',
      });
    }
    if (status === 'not-configured') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'إشعارات المتصفح غير مهيّأة بعد على هذا الموقع. راجع مطوّر المنصة.',
      });
    }
    if (status === 'not-logged-in') {
      return Promise.resolve({ ok: false, status: status, message: 'يرجى تسجيل الدخول أولاً.' });
    }
    if (status === 'denied') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'الإشعارات محجوبة من إعدادات المتصفح لهذا الموقع. اضغط أيقونة القفل بجانب العنوان ← الإشعارات ← السماح.',
      });
    }

    return Notification.requestPermission()
      .then(function (permission) {
        if (permission !== 'granted') {
          notifyStatusListeners();
          return { ok: false, status: getStatus(), message: 'لم يُمنح إذن الإشعارات.' };
        }
        return fetchAndRegisterToken().then(function (saved) {
          notifyStatusListeners();
          return saved
            ? { ok: true, status: getStatus(), message: 'تم تفعيل إشعارات المتصفح بنجاح ✅' }
            : { ok: false, status: getStatus(), message: 'مُنح الإذن لكن تعذر حفظ الجهاز على الخادم. حاول مرة أخرى.' };
        });
      })
      .catch(function () {
        notifyStatusListeners();
        return { ok: false, status: getStatus(), message: 'تعذر تفعيل إشعارات المتصفح حالياً. حاول مرة أخرى.' };
      });
  }

  function disable() {
    // إلغاء التسجيل من الخادم هو ما يوقف الإشعارات فعلياً؛ حذف الرمز محلياً
    // تنظيف إضافي best-effort (إذن المتصفح نفسه لا يمكن سحبه برمجياً -- ذلك
    // بيد المستخدم من إعدادات المتصفح، وهذا مقصود من مصمّمي المعيار).
    return sendTokenToServer('')
      .then(function (saved) {
        return getMessaging()
          .then(function (messaging) {
            return messaging.deleteToken();
          })
          .catch(function () {
            return null;
          })
          .then(function () {
            notifyStatusListeners();
            return saved
              ? { ok: true, status: getStatus(), message: 'تم إيقاف إشعارات المتصفح على هذا الجهاز.' }
              : { ok: false, status: getStatus(), message: 'تعذر إيقاف الإشعارات حالياً. حاول مرة أخرى.' };
          });
      })
      .catch(function () {
        return { ok: false, status: getStatus(), message: 'تعذر إيقاف الإشعارات حالياً. حاول مرة أخرى.' };
      });
  }

  // ---- مسار المريض في صفحة الحجز العامة (booking.html) -- أُضيف 2026-09-05 ----
  // نسخة مستقلة عن enable() أعلاه لأن المريض ليس مستخدماً مسجّلاً: لا authToken
  // ولا حساب، والهوية الوحيدة التي يملكها هي رقم هاتفه الذي حجز به.
  function getPublicStatus() {
    if (!isSupported()) return 'unsupported';
    if (!isConfigured()) return 'not-configured';
    if (Notification.permission === 'denied') return 'denied';
    if (Notification.permission === 'granted') return 'granted';
    return 'default';
  }

  function enableForBooking(options) {
    var slug = (options && options.slug) || '';
    var phone = (options && options.phone) || '';

    if (!slug || !phone) {
      return Promise.resolve({ ok: false, status: 'error', message: 'بيانات الطلب ناقصة.' });
    }

    var status = getPublicStatus();
    if (status === 'unsupported') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'متصفحك لا يدعم التنبيهات. لا تقلق — سيصلك رد الطبيب عبر واتساب.',
      });
    }
    if (status === 'not-configured') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'التنبيهات غير متاحة حالياً. سيصلك رد الطبيب عبر واتساب.',
      });
    }
    if (status === 'denied') {
      return Promise.resolve({
        ok: false,
        status: status,
        message: 'التنبيهات محجوبة في متصفحك لهذا الموقع. اسمح بها من إعدادات المتصفح ثم أعد المحاولة.',
      });
    }

    return Notification.requestPermission()
      .then(function (permission) {
        if (permission !== 'granted') {
          return { ok: false, status: getPublicStatus(), message: 'لم تسمح بالتنبيهات. سيصلك رد الطبيب عبر واتساب.' };
        }
        return fetchWebPushToken().then(function (webPushToken) {
          if (!webPushToken) {
            return { ok: false, status: getPublicStatus(), message: 'تعذر تفعيل التنبيه. حاول مرة أخرى.' };
          }
          return sendBookingTokenToServer(slug, phone, webPushToken).then(function (saved) {
            return saved
              ? { ok: true, status: 'granted', message: 'تم تفعيل التنبيه ✅ سيصلك إشعار فور رد الطبيب.' }
              : { ok: false, status: getPublicStatus(), message: 'تعذر تفعيل التنبيه حالياً. حاول مرة أخرى.' };
          });
        });
      })
      .catch(function () {
        return { ok: false, status: getPublicStatus(), message: 'تعذر تفعيل التنبيه حالياً. حاول مرة أخرى.' };
      });
  }

  function onStatusChange(listener) {
    if (typeof listener === 'function') {
      statusListeners.push(listener);
      try {
        listener(getStatus());
      } catch (error) {
        /* صمت */
      }
    }
  }

  window.ClinicWebPush = {
    isSupported: isSupported,
    isConfigured: isConfigured,
    getStatus: getStatus,
    enable: enable,
    disable: disable,
    onStatusChange: onStatusChange,
    // خاصّان بصفحة الحجز العامة (المريض، بلا تسجيل دخول)
    getPublicStatus: getPublicStatus,
    enableForBooking: enableForBooking,
  };

  // تحديث صامت للرمز عند كل تحميل صفحة -- فقط إذا كان الإذن ممنوحاً مسبقاً.
  // بلا هذا التحديث تتوقف الإشعارات فجأة عندما يُدوّر Firebase رمز الجهاز.
  function silentRefresh() {
    if (getStatus() !== 'granted') return;
    fetchAndRegisterToken().catch(function () {
      /* صمت تام -- ليست عملية طلبها المستخدم */
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', silentRefresh);
  } else {
    silentRefresh();
  }
})();
