package __PACKAGE__

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * Home-screen widget showing today's habits. The app writes plain strings to
 * the "HomeWidgetPreferences" store (through the home_widget plugin) and asks
 * for an update; this class only reads them and draws.
 */
class EmberWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val rowIds = intArrayOf(
            R.id.ember_row0, R.id.ember_row1, R.id.ember_row2,
            R.id.ember_row3, R.id.ember_row4, R.id.ember_row5,
        )
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val open = launch?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.ember_widget)
            views.setTextViewText(
                R.id.ember_summary,
                prefs.getString("ember_summary", "Open Ember to get started") ?: "",
            )
            for ((i, id) in rowIds.withIndex()) {
                val text = prefs.getString("ember_row$i", "") ?: ""
                if (text.isEmpty()) {
                    views.setViewVisibility(id, View.GONE)
                } else {
                    views.setViewVisibility(id, View.VISIBLE)
                    views.setTextViewText(id, text)
                    val done = prefs.getString("ember_done$i", "0") == "1"
                    views.setTextColor(id, if (done) Color.parseColor("#A89B93") else Color.parseColor("#F6EFEA"))
                    // A plain, unfinished habit is logged by tapping its row;
                    // anything else opens the app.
                    val kind = prefs.getString("ember_kind$i", "open")
                    val habitId = prefs.getString("ember_id$i", "0") ?: "0"
                    if (kind == "tap") {
                        views.setOnClickPendingIntent(
                            id,
                            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("ember://tap?id=$habitId")),
                        )
                    } else if (open != null) {
                        views.setOnClickPendingIntent(id, open)
                    }
                }
            }
            if (open != null) views.setOnClickPendingIntent(R.id.ember_widget_root, open)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
