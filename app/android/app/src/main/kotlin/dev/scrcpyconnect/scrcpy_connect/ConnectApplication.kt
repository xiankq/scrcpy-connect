package dev.scrcpyconnect.scrcpy_connect

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.FlutterEngineGroupCache

class ConnectApplication : Application() {
    companion object {
        const val ENGINE_GROUP_ID = "scrcpy_connect_engine_group"

        fun engineGroup(context: Context, vmArgs: Array<String> = emptyArray()): FlutterEngineGroup {
            val cache = FlutterEngineGroupCache.getInstance()
            return cache.get(ENGINE_GROUP_ID) ?: FlutterEngineGroup(
                context.applicationContext, vmArgs,
            ).also { cache.put(ENGINE_GROUP_ID, it) }
        }
    }
}
