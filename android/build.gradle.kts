buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.12.0") // Use a recent version
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.0") 
        classpath("com.google.gms:google-services:4.4.3")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = file("../build")
subprojects {
    project.buildDir = file("${rootProject.buildDir}/${project.name}")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}