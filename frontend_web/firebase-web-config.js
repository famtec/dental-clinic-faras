/**
 * firebase-web-config.js
 * ----------------------
 * إعدادات Firebase الخاصة بـ **الويب فقط** (إشعارات المتصفح / Web Push) --
 * أُضيف 2026-09-05.
 *
 * لماذا ملف منفصل؟ لأن ملف الـ Service Worker (firebase-messaging-sw.js) يعمل
 * خارج الصفحة تماماً ولا يستطيع الوصول إلى أي متغيّر داخلها، فيستورد هذا الملف
 * بنفسه عبر importScripts. استخدام `self` بدل `window` مقصود: `self` معرّف في
 * سياق الصفحة وسياق الـ Service Worker على حدّ سواء، فيعمل الملف في الاثنين.
 *
 * ⚠️ الميزة تبقى صامتة تماماً (بلا أي خطأ في الكونسول ولا أي زر معطّل يربك
 * الطبيب) طالما بقيت هذه القيم فارغة -- فقط لن تصل إشعارات المتصفح.
 *
 * كيف تملأ القيم (مرة واحدة فقط):
 *   1) افتح Firebase Console ← مشروعك ← ⚙️ Project settings ← تبويب General.
 *   2) في "Your apps" اضغط أيقونة الويب </> لإضافة تطبيق ويب (سمّه مثلاً
 *      "موقع العيادة")، ثم انسخ كائن firebaseConfig الظاهر والصق قيمه بالأسفل.
 *   3) ارجع إلى ⚙️ Project settings ← تبويب Cloud Messaging ← قسم
 *      "Web Push certificates" ← اضغط "Generate key pair" ← انسخ المفتاح
 *      الظاهر (Key pair) والصقه في FIREBASE_WEB_VAPID_KEY بالأسفل.
 *
 * ملاحظة أمنية: كل القيم هنا عامة بطبيعتها (تظهر لأي زائر في مصدر الصفحة) --
 * هذا طبيعي ومقصود في Firebase Web، والحماية الحقيقية تأتي من قواعد المشروع
 * ومن أن إرسال الإشعارات يتم من الخادم بمفتاح Service Account السرّي وحده.
 */
// القيم أدناه مأخوذة فعلياً من مشروع dental-clinic-faras-fc591 بتاريخ 2026-09-05
// (تطبيق الويب "Dental Clinic Website" + مفتاح Web Push المولَّد في نفس اليوم).
self.FIREBASE_WEB_CONFIG = {
  apiKey: 'AIzaSyCEmWPpm9divRII-y-ZNYrOwupIcceIWks',
  authDomain: 'dental-clinic-faras-fc591.firebaseapp.com',
  projectId: 'dental-clinic-faras-fc591',
  storageBucket: 'dental-clinic-faras-fc591.firebasestorage.app',
  messagingSenderId: '1048631773699',
  appId: '1:1048631773699:web:ede2d48a51e4aeb7015c36',
};

// مفتاح VAPID العام (Web Push certificate) -- انظر الخطوة 3 بالأعلى.
self.FIREBASE_WEB_VAPID_KEY = 'BCtOw999meaWeopGGi0BenMgRM5zdcdxin70QPs3k5sYQcRsJ6j_Yn2dQjo2beNpQ0T6imNeQSvWjTBdn1jpEjM';
