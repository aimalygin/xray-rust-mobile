import org.gradle.api.publish.maven.MavenPublication
import org.gradle.plugins.signing.SigningExtension

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
}

val xrayFfiAndroidDir = providers.environmentVariable("XRAY_FFI_ANDROID_DIR")
    .getOrElse(rootProject.file("../.build/android/native").absolutePath)

android {
    namespace = "org.xrayrust.mobile"
    compileSdk = 35
    ndkVersion = "26.3.11579264"

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")

        ndk {
            abiFilters += setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(file("$xrayFfiAndroidDir/jniLibs"))
        }
    }

    packaging {
        jniLibs {
            keepDebugSymbols += "**/libxray_ffi.so"
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                artifactId = providers.gradleProperty("POM_ARTIFACT_ID").get()

                pom {
                    name.set(providers.gradleProperty("POM_NAME"))
                    description.set(providers.gradleProperty("POM_DESCRIPTION"))
                    url.set(providers.gradleProperty("POM_URL"))

                    licenses {
                        license {
                            name.set("Mozilla Public License 2.0")
                            url.set("https://www.mozilla.org/MPL/2.0/")
                            distribution.set("repo")
                        }
                    }

                    developers {
                        developer {
                            id.set("aimalygin")
                            name.set("Anton Malygin")
                        }
                    }

                    scm {
                        connection.set("scm:git:https://github.com/aimalygin/xray-rust-mobile.git")
                        developerConnection.set("scm:git:ssh://git@github.com/aimalygin/xray-rust-mobile.git")
                        url.set("https://github.com/aimalygin/xray-rust-mobile")
                    }

                    issueManagement {
                        system.set("GitHub")
                        url.set("https://github.com/aimalygin/xray-rust-mobile/issues")
                    }
                }
            }
        }

        repositories {
            maven {
                name = "staging"
                url = uri(rootProject.layout.buildDirectory.dir("maven-repository"))
            }

            maven {
                name = "GitHubPackages"
                val repository = providers.environmentVariable("GITHUB_REPOSITORY")
                    .getOrElse("aimalygin/xray-rust-mobile")
                url = uri("https://maven.pkg.github.com/$repository")
                credentials {
                    username = providers.environmentVariable("GITHUB_ACTOR").orNull
                    password = providers.environmentVariable("GITHUB_TOKEN").orNull
                }
            }
        }
    }

    val signingKey = providers.environmentVariable("MAVEN_SIGNING_KEY").orNull
    val signingPassword = providers.environmentVariable("MAVEN_SIGNING_PASSWORD").orNull
    if (!signingKey.isNullOrBlank()) {
        extensions.configure<SigningExtension> {
            useInMemoryPgpKeys(signingKey, signingPassword)
            sign(publishing.publications["release"])
        }
    }
}
