allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ✅ FIX: Some plugins (file_picker 8.3.7 pins `compileSdk 34`) depend on
//    flutter_plugin_android_lifecycle, which now requires compileSdk >= 36.
//    That makes `flutter run` fail with:
//      "Dependency ':flutter_plugin_android_lifecycle' requires ... version 36
//       or later ... :file_picker is currently compiled against android-34."
//    Forcing every Android subproject up to 36 resolves it without editing the
//    plugin sources in the pub cache. Wrapped in try/catch so a plugin that does
//    not expose the compileSdk DSL never breaks the build.
fun Project.forceCompileSdk() {
    val androidExt = this.extensions.findByName("android") ?: return
    try {
        androidExt.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(androidExt, 36)
    } catch (_: NoSuchMethodException) {
        try {
            androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(androidExt, 36)
        } catch (_: Exception) {
            // Not an Android module; nothing to configure.
        }
    } catch (_: Exception) {
        // Ignore: never fail the build because of a reflective setter.
    }
}

subprojects {
    // `evaluationDependsOn(":app")` (above) may already have evaluated the
    // project, so guard the afterEvaluate call to avoid:
    //   "Cannot run Project.afterEvaluate(Action) when the project is already evaluated."
    if (this.state.executed) {
        forceCompileSdk()
    } else {
        afterEvaluate { forceCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
