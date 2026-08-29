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

    // flutter_avif_android 3.1.0 publishes FlutterAvifPlugin twice: once as
    // Java and once as Kotlin under the same package/class name. Recent Kotlin
    // (K2) therefore fails with a redeclaration error. Keep the Kotlin plugin
    // implementation and exclude the stale Java source until upstream removes
    // it.
    //
    // The same upstream Android module also hard-codes compileSdkVersion 31,
    // while its current AndroidX dependency graph requires API 34+. The plugin
    // applies that compileSdk value after the Android library plugin, so setting
    // it inside plugins.withId() would be overwritten by the upstream build
    // script. Override it after this subproject has finished evaluation instead.
    if (name == "flutter_avif_android") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                sourceSets.getByName("main").java.setSrcDirs(emptyList<String>())
            }
        }

        afterEvaluate {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                compileSdk = 37
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
    // CI verification branch intentionally touches this Android build file so
    // the pull_request workflow exercises every Android ABI.
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
