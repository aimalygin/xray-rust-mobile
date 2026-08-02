pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        val stagedRepository = providers.environmentVariable("XRAY_MAVEN_REPOSITORY")
            .orNull
            ?: error("XRAY_MAVEN_REPOSITORY must point to the staged Maven repository")
        maven { url = uri(stagedRepository) }
        google()
        mavenCentral()
    }
}

rootProject.name = "XrayRustMobileConsumerSmoke"
include(":consumer")

