import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. CI passes the key through environment variables; on your own
// machine you can put the same four values in android/key.properties (which is
// never committed). With neither, builds are signed with Android's debug key, so
// a fresh checkout always builds and runs.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(env: String, property: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProperties.getProperty(property)

val emberStoreFile = signingValue("EMBER_KEYSTORE_PATH", "storeFile")

android {
    namespace = "com.nextlyr.ember"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nextlyr.ember"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Version name and code come from pubspec.yaml (or --build-name / --build-number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (emberStoreFile != null) {
            create("ember") {
                storeFile = file(requireNotNull(emberStoreFile))
                storePassword = signingValue("EMBER_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("EMBER_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("EMBER_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        // Debug and release builds share one key when there is one, so you can
        // switch between them without uninstalling.
        val signing = signingConfigs.findByName("ember") ?: signingConfigs.getByName("debug")
        debug {
            signingConfig = signing
        }
        release {
            signingConfig = signing
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
