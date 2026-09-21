import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read GOOGLE_MAPS_API_KEY for the Android Maps manifest placeholder. Checks
// the environment first, then falls back to assets/env/.env (the same file the
// Dart runtime loads via flutter_dotenv).
fun googleMapsApiKey(): String {
    System.getenv("GOOGLE_MAPS_API_KEY")?.takeIf { it.isNotBlank() }?.let { return it }
    // rootProject is the `android/` dir, so the Flutter project root is one level up.
    val envFile = rootProject.file("../assets/env/.env")
    if (!envFile.exists()) return ""
    return envFile.readLines()
        .firstOrNull { it.startsWith("GOOGLE_MAPS_API_KEY=") }
        ?.substringAfter("=")
        ?.trim()
        ?: ""
}

// ── Release signing (upload keystore) ────────────────────────────────────────
// `android/key.properties` (git-ignored) points at the upload keystore. Ginagawa
// ito ng `.github/workflows/android-apk-release.yml` mula sa GitHub secrets, at
// manu-manong ginagawa sa local kapag gusto ng sariling keystore.
// Kapag wala ang file (hal. fresh clone), babalik sa debug signing — tulad ng
// dati — para hindi masira ang `flutter run --release`.
// Tingnan ang web/downloads/README.md para sa setup.
val keystoreProps: Properties? = rootProject.file("key.properties")
    .takeIf { it.exists() }
    ?.let { propsFile ->
        Properties().apply { propsFile.inputStream().use { load(it) } }
    }

/** Resolve `storeFile` mula sa key.properties: absolute, `android/`, o `android/app/`. */
fun resolveKeystore(path: String): File {
    val raw = File(path)
    if (raw.isAbsolute) return raw
    return listOf(rootProject.file(path), file(path)).firstOrNull { it.exists() }
        ?: rootProject.file(path)
}

android {
    namespace = "com.example.jireta_loans"
    // ✅ FIX: flutter_plugin_android_lifecycle (via file_picker) requires
    //    compileSdk 36+. Pin it explicitly — flutter.compileSdkVersion resolved
    //    to 34 on this Flutter version, breaking assembleDebug with
    //    "Dependency ... requires ... compile against version 36 or later".
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ FIX: flutter_local_notifications v17+ uses java.time APIs that
        // require desugaring on Android API < 26. Enable this even if you
        // target Java 17 — the flag controls *library* desugaring, not the
        // compiler source level.
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.jireta_loans"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        //
        // ✅ FIX: flutter_local_notifications v17+ requires minSdk >= 21.
        //    Override flutter.minSdkVersion here to guarantee it.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] = googleMapsApiKey()
    }

    signingConfigs {
        keystoreProps?.let { props ->
            create("release") {
                val storePath = props.getProperty("storeFile")
                val store = resolveKeystore(storePath)
                check(store.exists()) {
                    "android/key.properties -> storeFile '$storePath' not found " +
                        "(looked in android/ and android/app/)."
                }
                storeFile = store
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Upload keystore kapag may `android/key.properties` (CI at local
            // release builds); kung wala, debug keys para gumana pa rin ang
            // `flutter run --release`.
            signingConfig = if (keystoreProps != null) {
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
    // ✅ FIX: Required companion library for isCoreLibraryDesugaringEnabled.
    //    Use the latest stable version of desugar_jdk_libs.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}