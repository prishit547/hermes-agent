allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some transitive plugins (e.g. flutter_timezone) still default their Kotlin
// compile to JVM 1.8 while their Java compiles at 11, which fails the build with
// "Inconsistent JVM-target compatibility". Force every plugin module to 17
// (matching the app) so Java and Kotlin agree within each module. Java is set
// via the android {} extension (not the raw JavaCompile task) so AGP keeps
// android.jar on the bootclasspath — and inside afterEvaluate, before AGP
// finalizes compileOptions. `:app` is skipped: it is already 17/17 and is
// force-evaluated early by the evaluationDependsOn above, so afterEvaluate would
// throw "already evaluated" on it.
subprojects {
    if (name != "app") {
        afterEvaluate {
            (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
