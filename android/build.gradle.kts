allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // Temporary patch for a plugin bug: receive_sharing_intent 1.9.0 declares
    // compileSdk 37, but Google ships no platforms;android-37 package — only
    // android-37.0 — so Gradle dies with
    //   Failed to find target with hash string 'android-37'
    // Align every Android module with the app instead, which follows
    // flutter.compileSdkVersion, so nothing here pins an SDK level of its own.
    // Reflection is used because the root script has no AGP on its classpath.
    // Remove once the plugin declares a compileSdk that actually resolves.
    afterEvaluate {
        if (path == ":app") return@afterEvaluate

        val android = extensions.findByName("android") ?: return@afterEvaluate
        val appAndroid = project(":app").extensions.findByName("android")
            ?: return@afterEvaluate

        fun compileSdkOf(extension: Any): String? = runCatching {
            extension.javaClass.getMethod("getCompileSdkVersion").invoke(extension) as? String
        }.getOrNull()

        val appCompileSdk = compileSdkOf(appAndroid) ?: return@afterEvaluate
        val current = compileSdkOf(android)
        if (current == null || current == appCompileSdk) return@afterEvaluate

        val applied = listOf("compileSdkVersion", "setCompileSdkVersion").any { method ->
            runCatching {
                android.javaClass.getMethod(method, String::class.java).invoke(android, appCompileSdk)
            }.isSuccess
        }

        if (applied) {
            logger.lifecycle("Patched $path compileSdk: $current -> $appCompileSdk")
        } else {
            logger.warn("Could not align $path compileSdk ($current) with $appCompileSdk")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}