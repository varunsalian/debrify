package com.debrify.app.profiles

/**
 * One process-wide lock for the three native durable-job stores. Migration
 * must replace all stores and commit its marker as one quiesced operation;
 * store-local locks allowed a worker/alarm to write an old authority between
 * replacements.
 */
object NativeProfileMigrationGate {
    @JvmField val lock = Any()
}
