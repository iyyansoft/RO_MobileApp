import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Company release signing (docs/ANDROID_RELEASE_SIGNING.md). The keystore and its
// passwords are never in the repository: key.properties is read from the path in
// NEEROPLUS_KEY_PROPERTIES (recommended: outside the repo) or android/key.properties
// (git-ignored).
val keyPropertiesFile: File = System.getenv("NEEROPLUS_KEY_PROPERTIES")?.let { file(it) }
    ?: rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) FileInputStream(keyPropertiesFile).use { load(it) }
}
val hasReleaseKey = keyPropertiesFile.exists()
// A Play Store bundle must never be signed with the debug key.
if (!hasReleaseKey && gradle.startParameter.taskNames.any { it.contains("bundleRelease", ignoreCase = true) }) {
    throw GradleException(
        "Release App Bundle needs the company signing key: set NEEROPLUS_KEY_PROPERTIES " +
            "(see docs/ANDROID_RELEASE_SIGNING.md). Refusing to build a debug-signed AAB."
    )
}

android {
    namespace = "com.rowholesale.ro_wholesale_dealer_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rowholesale.ro_wholesale_dealer_app"
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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // Passwords preferably come from NEEROPLUS_KEYSTORE_PASSWORD (set only for
                // the build by scripts/build-release-aab.ps1), so key.properties holds none.
                val envPassword = System.getenv("NEEROPLUS_KEYSTORE_PASSWORD")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword") ?: envPassword
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword") ?: envPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Test APKs only (emulator / internal testing). Not installable over a
                // company-signed app and not accepted by Google Play.
                logger.warn("WARNING: no company signing key found; this release APK is signed with the DEBUG key (testing only).")
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
