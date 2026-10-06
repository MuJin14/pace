plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.campus_run_app"

    // compileSdk 显式锁 36：flutter_secure_storage 编译依赖 Android SDK 36。
    // 不能再用 flutter.compileSdkVersion（当前是 35），否则构建直接失败。
    compileSdk = 36

    // ndkVersion 锁 27.0.12077973：geolocator_android / flutter_secure_storage /
    // image_picker_android / path_provider_android / shared_preferences_android /
    // flutter_plugin_android_lifecycle 六个插件都要求 27.x（NDK 向后兼容，取最高即可）。
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ⚠️ flutter_local_notifications 依赖 java.time 等 Java 8+ API，
        // 在 Android 低版本上必须靠脱糖（desugaring）提供，否则构建直接失败：
        //   "Dependency ':flutter_local_notifications' requires core library
        //    desugaring to be enabled"
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.campus_run_app"
        // minSdk 必须是 23：flutter_secure_storage 的 manifest 声明了 minSdk 23，
        // 用 Flutter 默认的 21 会在 manifest 合并阶段直接失败。
        // 代价是放弃 Android 5.0/5.1（API 21-22），这两版占比已极低。
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 脱糖运行时库：配合上面的 isCoreLibraryDesugaringEnabled。
    // 版本需 >= 2.1.4（flutter_local_notifications 的要求）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
