plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ae.vipvalet.vip_fleet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ae.vipvalet.vip_fleet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release key: the same keystore as the VIP Valet app, given at build time (never kept in git):
    //   VIP_KEYSTORE=/path/vip_valet_signing.keystore VIP_KEY_PASS=... flutter build apk
    // Every update must be signed with the same key (or Android refuses it).
    val ks = System.getenv("VIP_KEYSTORE")
    signingConfigs {
        if (ks != null) {
            create("vipFleet") {
                storeFile = file(ks)
                storePassword = System.getenv("VIP_KEY_PASS")
                keyAlias = System.getenv("VIP_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("VIP_KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (ks != null) signingConfigs.getByName("vipFleet") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
