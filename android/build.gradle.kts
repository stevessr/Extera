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

    // A number of older Flutter Android plugins still pin compileSdk to 31/33.
    // Their modern AndroidX dependency graphs require API 34+, so AGP rejects
    // those library modules during AAR metadata checks even though the app
    // itself already compiles against API 37. Normalize stale Android library
    // modules after their own build scripts have finished, without changing
    // their minSdk or targetSdk/runtime behavior.
    afterEvaluate {
        if (pluginManager.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                val configuredCompileSdk = compileSdk
                if (configuredCompileSdk == null || configuredCompileSdk < 37) {
                    compileSdk = 37
                }
            }
        }
    }

    // desktop_drop 0.8.2 decides whether to apply KGP only from the AGP major
    // version. Flutter 3.47 intentionally keeps built-in Kotlin disabled while
    // plugins migrate, so on AGP 9 the plugin reaches its `kotlin {}` block
    // without a Kotlin extension and fails during configuration. Apply the
    // pinned legacy KGP to this subproject only; Flutter supports this AGP 9
    // transition mode when android.builtInKotlin=false.
    if (name == "desktop_drop") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
