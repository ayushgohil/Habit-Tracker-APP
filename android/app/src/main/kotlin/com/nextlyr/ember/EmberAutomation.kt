package com.nextlyr.ember

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/** Sends a request to the app's background code, which works with it closed. */
private fun sendToEmber(context: Context, host: String, habitId: Int) {
    try {
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("ember://$host?id=$habitId")).send()
    } catch (e: Exception) {
        // The app's background service could not be started; nothing more to do.
    }
}

/**
 * Lets automation apps (Tasker, MacroDroid, adb) drive Ember. Send one of the
 * actions below with a text extra "habit" holding the habit's name (or id).
 */
class EmberActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val host = when (intent.action) {
            "com.nextlyr.ember.action.LOG" -> "tap"
            "com.nextlyr.ember.action.COMPLETE" -> "complete"
            "com.nextlyr.ember.action.START" -> "start"
            "com.nextlyr.ember.action.STOP" -> "stop"
            else -> return
        }
        val wanted = intent.getStringExtra("habit")?.trim() ?: return
        val habit = EmberCards.habits(context).firstOrNull {
            it.id.toString() == wanted || it.name.equals(wanted, ignoreCase = true)
        } ?: return
        sendToEmber(context, host, habit.id)
    }
}

/** Quick Settings tile: logs the next habit that is still to do. */
class EmberTileService : TileService() {
    private fun next(): EmberHabit? = EmberCards.habits(this).firstOrNull { it.tappable && !it.done }

    override fun onStartListening() {
        val tile = qsTile ?: return
        val habit = next()
        tile.label = habit?.name ?: "Ember: all done"
        tile.state = if (habit != null) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = if (habit != null) "Tap to log" else "Nothing left to log"
        tile.updateTile()
    }

    override fun onClick() {
        val habit = next() ?: return
        sendToEmber(this, "tap", habit.id)
        val tile = qsTile ?: return
        tile.label = "Logged ${habit.name}"
        tile.state = Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = "Done"
        tile.updateTile()
    }
}
