pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("dev.flutter.flutter-gradle-plugin")
    }
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "dev.flutter.flutter-gradle-plugin") {
                useId("dev.flutter.flutter-gradle-plugin")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-gradle-plugin") apply false
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        flatDir {
            dirs("C:\\src\\flutter\\packages\\flutter_tools\\gradle")
        }
    }
}

include(":app")
