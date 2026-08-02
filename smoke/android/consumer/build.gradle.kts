plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "org.xrayrust.mobile.smoke"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.xrayrust.mobile.smoke"
        minSdk = 24
        targetSdk = 35
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

dependencies {
    val sdkVersion = providers.environmentVariable("XRAY_MOBILE_VERSION").get()
    implementation("io.github.aimalygin:xray-rust-mobile:$sdkVersion")
}
