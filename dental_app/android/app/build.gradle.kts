import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // مطلوب لقراءة google-services.json وتفعيل Firebase -- أُضيف 2026-08-24
    // (لن يعمل الـ build إلا بعد وضع الملف الحقيقي في هذا المجلد -- android/app/)
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -- توقيع نسخة الإصدار الرسمية (release) -- 2026-08-31
// يقرأ بيانات مفتاح التوقيع من android/key.properties (ملف محلي على جهازك،
// غير موجود بالمستودع أصلاً بحسب android/.gitignore، ويجب ألا يُرفع أبداً).
// إن لم يكن الملف موجوداً بعد (قبل إنشاء المفتاح) يستمر الـ build بالتوقيع
// المؤقت (debug) كما كان، فلا ينكسر أي شيء حالياً.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.dental_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // مطلوب لحزمة flutter_local_notifications -- أُضيف 2026-08-24
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mydigitalclinic.doctor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // يوقّع بمفتاح الإصدار الحقيقي إن وُجد key.properties، وإلا
            // يستمر مؤقتاً بتوقيع debug (نفس سلوك قالب Flutter الافتراضي).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // مطلوب لحزمة flutter_local_notifications (core library desugaring) -- أُضيف 2026-08-24
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
