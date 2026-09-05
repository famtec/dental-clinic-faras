/**
 * firebase-messaging-sw.js
 * ------------------------
 * Service Worker إشعارات المتصفح (Web Push) -- أُضيف 2026-09-05.
 *
 * **يجب أن يبقى هذا الملف في جذر الموقع بهذا الاسم بالضبط**: Firebase تبحث عنه
 * افتراضياً على المسار /firebase-messaging-sw.js، والـ Service Worker لا يستطيع
 * التحكم إلا بالصفحات الواقعة ضمن نطاق مساره (scope). المشروع يخدم مجلد
 * frontend_web من الجذر مباشرة عبر
 * app.mount("/", StaticFiles(directory="frontend_web")) في main.py، فوجوده هنا
 * يعني تلقائياً scope = "/" أي كل صفحات الموقع. لا تنقله إلى مجلد فرعي.
 *
 * دوره: عرض الإشعار والموقع مغلق تماماً أو في تبويب آخر. عندما تحمل الرسالة
 * القادمة من الخادم حقل notification (وهي حالتنا الافتراضية) تعرضه مكتبة
 * Firebase تلقائياً بنفسها، والضغط عليه يفتح الرابط الممرَّر في
 * webpush.fcm_options.link من main.py -- لذلك لا نعرضه نحن مرة ثانية هنا حتى
 * لا يظهر إشعاران متطابقان. المعالجة اليدوية بالأسفل مخصصة فقط للرسائل التي لا
 * تحمل حقل notification (رسائل data فقط).
 */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');
importScripts('./firebase-web-config.js');

(function () {
  var config = self.FIREBASE_WEB_CONFIG || {};

  // بلا إعدادات Firebase حقيقية لا نُهيّئ شيئاً إطلاقاً -- الملف يبقى موجوداً
  // وصامتاً بلا أي خطأ في الكونسول (انظر التعليمات في firebase-web-config.js).
  if (!config.apiKey || !config.projectId || !config.messagingSenderId || !config.appId) {
    return;
  }

  firebase.initializeApp(config);
  var messaging = firebase.messaging();

  messaging.onBackgroundMessage(function (payload) {
    // رسالة تحمل notification: عرضتها المكتبة تلقائياً بالفعل، فلا نكرّرها.
    if (payload && payload.notification) return;

    var data = (payload && payload.data) || {};
    var title = data.title || 'عيادتك الرقمية';
    var options = {
      body: data.body || '',
      icon: './favicon.png',
      badge: './favicon.png',
      dir: 'rtl',
      lang: 'ar',
      tag: data.type || 'clinic-notification',
      data: { clinicLink: data.link || './index.html' },
    };
    return self.registration.showNotification(title, options);
  });

  // يخصّ الإشعارات التي أنشأناها يدوياً بالأعلى فقط (تلك التي تحمل clinicLink)
  // -- إشعارات Firebase التلقائية لها معالج الضغط الخاص بها داخل المكتبة.
  self.addEventListener('notificationclick', function (event) {
    var link = event.notification && event.notification.data && event.notification.data.clinicLink;
    if (!link) return;

    event.notification.close();
    event.waitUntil(
      self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
        for (var i = 0; i < clientList.length; i += 1) {
          if ('focus' in clientList[i]) return clientList[i].focus();
        }
        if (self.clients.openWindow) return self.clients.openWindow(link);
        return undefined;
      })
    );
  });
})();
