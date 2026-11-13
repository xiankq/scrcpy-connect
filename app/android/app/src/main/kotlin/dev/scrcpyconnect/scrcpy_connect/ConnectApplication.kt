package dev.scrcpyconnect.scrcpy_connect

import android.app.Application
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.FlutterEngineGroupCache

/** Shared engine group for independent control windows. */
class ConnectApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FlutterEngineGroupCache.getInstance().put(
            ENGINE_GROUP_ID,
            FlutterEngineGroup(this),
        )
    }

    companion object {
        const val ENGINE_GROUP_ID = "scrcpy_connect_engine_group"
    }
}
