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
    // it. The native libraries and plugin registration are unaffected.
    if (name == "flutter_avif_android") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                sourceSets.getByName("main").java.setSrcDirs(emptyList<String>())
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
