
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read GOOGLE_MAPS_API_KEY for the Android Maps manifest placeholder.
// Checks the environment first, then falls back to assets/env/.env.
fun googleMapsApiKey(): String {
    System.getenv("GOOGLE_MAPS_API_KEY")
        ?.takeIf { it.isNotBlank() }
        ?.let { return it }

    // rootProject is the android/ directory.
    val envFile = rootProject.file("../assets/env/.env")

    if (!envFile.exists()) return ""

    return envFile.readLines()
        .firstOrNull { it.startsWith("GOOGLE_MAPS_API_KEY=") }
        ?.substringAfter("=")
        ?.trim()
        ?: ""
}

// ── Release signing (mandatory upload keystore) ──────────────────────────────
// Requires android/key.properties.
// Never fall back to debug signing for release builds.

val keystorePropsFile = rootProject.file("key.properties")

check(keystorePropsFile.exists()) {
    "Release signing required: android/key.properties is missing."
}

val keystoreProps = Properties().apply {
    keystorePropsFile.inputStream().use { load(it) }
}

/** Resolve storeFile from key.properties. */
fun resolveKeystore(path: String): File {
    val raw = File(path)

    if (raw.isAbsolute) return raw

    return listOf(
        rootProject.file(path),
        file(path)
    ).firstOrNull { it.exists() } ?: rootProject.file(path)
}

android {
    namespace = "com.jiretalendingcorp.app"

    // Required by flutter_plugin_android_lifecycle.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required for java.time APIs on older Android versions.
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jiretalendingcorp.app"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] = googleMapsApiKey()
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProps.getProperty("storeFile")
                ?: error("Missing storeFile in android/key.properties")

            val store = resolveKeystore(storePath)

            check(store.exists()) {
                "Release keystore not found: $storePath"
            }

            storeFile = store

            storePassword = keystoreProps.getProperty("storePassword")
                ?: error("Missing storePassword in android/key.properties")

            keyAlias = keystoreProps.getProperty("keyAlias")
                ?: error("Missing keyAlias in android/key.properties")

            keyPassword = keystoreProps.getProperty("keyPassword")
                ?: error("Missing keyPassword in android/key.properties")
        }
    }

    buildTypes {
        release {
            // Always use the permanent upload keystore.
            signingConfig = signingConfigs.getByName("release")
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
    // Required companion library for core library desugaring.
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )
}
