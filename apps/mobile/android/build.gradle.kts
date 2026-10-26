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
    // Only relocate build directories for subprojects that live on the same drive as this
    // project. Plugins resolved from the pub cache may live on another drive (sources on C:,
    // project on D:), and Gradle/AGP cannot compute a relative path between a project directory
    // and its build directory when the two drives differ. That breaks task creation, e.g.:
    //   Could not create task ':camera_android_camerax:generateDebugUnitTestConfig'.
    //   > this and base files have different roots: D:\...\build\camera_android_camerax and
    //     C:\...\Pub\Cache\hosted\...\camera_android_camerax-0.7.4+7\android.
    // Cross-drive plugins therefore keep Gradle's default build directory inside their package.
    val sameDriveAsRootProject: Boolean =
        project.projectDir.toPath().root == rootProject.projectDir.toPath().root
    if (sameDriveAsRootProject) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
