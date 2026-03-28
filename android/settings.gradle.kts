pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val gradlePropertiesFile = file("gradle.properties")
        val localPropertiesFile = file("local.properties")

        if (gradlePropertiesFile.exists()) {
            gradlePropertiesFile.inputStream().use { properties.load(it) }
        }
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }

        val flutterSdkPath =
            listOfNotNull(
                properties.getProperty("flutter.sdk"),
                System.getenv("FLUTTER_ROOT"),
                System.getenv("FLUTTER_HOME"),
                System.getProperty("flutter.sdk"),
            ).firstOrNull { it.isNotBlank() }

        require(flutterSdkPath != null) {
            "Flutter SDK not configured. Set flutter.sdk in android/local.properties or define FLUTTER_ROOT."
        }
        require(file("$flutterSdkPath/packages/flutter_tools/gradle").exists()) {
            "Invalid Flutter SDK path: $flutterSdkPath"
        }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.12.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.0" apply false
}

include(":app")
