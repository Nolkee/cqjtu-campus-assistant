allprojects {
    repositories {
        // Prefer the official Flutter engine repository when a mirror is missing
        // a specific debug/profile/release artifact for the current engine revision.
        maven {
            url = uri("https://storage.googleapis.com/download.flutter.io")
            content {
                includeGroup("io.flutter")
            }
        }
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
