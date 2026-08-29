import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // Flutter 3.47 applies/configures Kotlin through its Gradle plugin. Keep the
    // app plugin list aligned with the current Flutter template for AGP 9.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

configurations.all {
    // Use the latest version published: https://central.sonatype.com/artifact/com.google.crypto.tink/tink-android
    val tink = "com.google.crypto.tink:tink-android:1.17.0"
    resolutionStrategy {
        force(tink)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink")).using(module(tink))
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // For flutter_local_notifications // Workaround for: https://github.com/MaikuB/flutter_local_notifications/issues/2286
}

android {
    namespace = "xyz.extera.next"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
       create("release") {
            keyAlias = "dummyAlias"
            keyPassword = "dummyPassword"
            storeFile = file("dummy.keystore")
            storePassword = "dummyStorePassword"
        }
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        signingConfigs.getByName("release").apply {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        applicationId = "xyz.extera.next"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    flavorDimensions += "type"
    productFlavors {
        create("fDebug") {
            dimension = "type"
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            resValue("string", "app_name", "Extera Next (Debug)")
        }

        create("fRelease") {
            dimension = "type"
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
