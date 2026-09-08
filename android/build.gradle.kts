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

// Some transitive plugins (e.g. appflowy_editor -> keyboard_height_plugin)
// ship an Android build.gradle pinned to an old compileSdk, which AGP now
// rejects once other androidx deps require 33/34+. Force every module to
// compile against the same SDK the app itself targets — must happen
// *after* each module's own build.gradle runs (it sets compileSdk itself,
// so anything earlier gets clobbered), hence afterEvaluate rather than
// plugins.withId. `:app` (evaluated eagerly via evaluationDependsOn above)
// is often already evaluated by the time this block runs, which makes a
// blanket `afterEvaluate` throw — so apply directly when that's the case.
subprojects {
    fun forceCompileSdk() {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.let { it.compileSdk = 36 }
    }
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
