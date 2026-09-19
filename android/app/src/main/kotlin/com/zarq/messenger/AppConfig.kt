package com.zarq.messenger

/**
 * Global application configuration for Native Kotlin services.
 * Change the BASE_URL here to switch between local development and production.
 */
object AppConfig {
    // Local Development
    const val BASE_URL = "http://192.168.29.81:8080"
    
    // Production
    // const val BASE_URL = "https://api.zarqmessenger.com"
}
