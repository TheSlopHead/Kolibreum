import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeysFile = rootProject.file("key.properties")
val releaseKeys = Properties().apply {
    if (releaseKeysFile.isFile) releaseKeysFile.inputStream().use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseRequested) {
    require(releaseKeysFile.isFile) {
        "Release signing is required. Configure android/key.properties; see docs/RELEASE.md."
    }
    for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!releaseKeys.getProperty(name).isNullOrBlank()) {
            "Missing release signing property: $name"
        }
    }
    require(rootProject.file(releaseKeys.getProperty("storeFile")).isFile) {
        "Release keystore does not exist."
    }
}

android {
    namespace = "dev.mut.mut_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this ID stable so future signed releases can update the app.
        applicationId = "dev.mut.mut_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeysFile.isFile) {
            create("release") {
                storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
