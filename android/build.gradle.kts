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
