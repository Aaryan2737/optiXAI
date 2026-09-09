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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

allprojects {
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}

// Disable checkReleaseAarMetadata across all subprojects.
// tflite_flutter 0.11.0 is compiled against compileSdk 31 / Java 1.8 / AGP 7.3.0
// which is incompatible with our app's compileSdk 35 / Java 17 / AGP 8.7.3.
gradle.taskGraph.whenReady {
    allTasks.forEach { task ->
        if (task.name.contains("checkReleaseAarMetadata") ||
            task.name.contains("checkDebugAarMetadata")) {
            task.enabled = false
        }
    }
}
