package __PACKAGE__

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * Card-style home-screen widgets (streak, ring, week, trend, month, grid).
 * The app draws each card as a PNG and stores where they are; these classes
 * only choose the right picture and a background and show them.
 */
private const val PREFS = "HomeWidgetPreferences"

class EmberHabit(val id: Int, val name: String, val color: Int, val tappable: Boolean, val done: Boolean)

object EmberCards {
    fun habits(context: Context): List<EmberHabit> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("ember_habits", "") ?: ""
        return raw.split("\n").mapNotNull { line ->
            val p = line.split("\t")
            val id = p.getOrNull(0)?.toIntOrNull()
            val color = p.getOrNull(2)?.toLongOrNull()
            if (id == null || color == null || p.size < 4) null
            else EmberHabit(id, p[1], color.toInt(), p[3] == "1", p.getOrNull(4) == "1")
        }
    }

    fun update(context: Context, manager: AppWidgetManager, widgetId: Int, kind: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val style = prefs.getString("ember_w${widgetId}_style", "dark") ?: "dark"
        val habitId = prefs.getString("ember_w${widgetId}_habit", "0")?.toIntOrNull() ?: 0
        val habit = habits(context).firstOrNull { it.id == habitId }
        val views = RemoteViews(context.packageName, R.layout.ember_card)

        // A picture in the habit's own colour suits the dark background; white
        // suits the coloured and glass ones.
        val ink = if (style == "dark") "c" else "w"
        val dir = prefs.getString("ember_img_dir", "") ?: ""
        val file = if (kind == "grid") "ember_grid_$ink.png" else "ember_${kind}_${habitId}_$ink.png"
        val bitmap = if (dir.isEmpty()) null else BitmapFactory.decodeFile("$dir/$file")
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.ember_card_image, bitmap)
        } else {
            views.setImageViewResource(R.id.ember_card_image, android.R.color.transparent)
        }

        // The background is a white rounded shape, tinted and made see-through here.
        val (tint, alpha) = when (style) {
            "glass" -> Pair(0x101418, 120)
            "color" -> Pair((habit?.color ?: 0xFF6B2C) and 0xFFFFFF, 255)
            else -> Pair(0x211B18, 255)
        }
        views.setInt(R.id.ember_card_bg, "setColorFilter", 0xFF000000.toInt() or tint)
        views.setInt(R.id.ember_card_bg, "setImageAlpha", alpha)

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (kind == "ring" && habit != null && habit.tappable) {
            // Tapping the ring logs the habit without opening the app.
            views.setOnClickPendingIntent(
                R.id.ember_card_root,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("ember://tap?id=${habit.id}")),
            )
        } else if (launch != null) {
            views.setOnClickPendingIntent(
                R.id.ember_card_root,
                PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        manager.updateAppWidget(widgetId, views)
    }
}

open class EmberCardProvider(private val kind: String) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) EmberCards.update(context, manager, id, kind)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for (id in ids) {
            edit.remove("ember_w${id}_habit")
            edit.remove("ember_w${id}_style")
        }
        edit.apply()
    }
}

class EmberStreakWidget : EmberCardProvider("streak")
class EmberRingWidget : EmberCardProvider("ring")
class EmberWeekWidget : EmberCardProvider("week")
class EmberTrendWidget : EmberCardProvider("trend")
class EmberMonthWidget : EmberCardProvider("month")
class EmberGridWidget : EmberCardProvider("grid")

/** Asks which habit and which look a new card widget should use. */
class EmberWidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider?.className ?: ""
        if (provider.endsWith("EmberGridWidget")) {
            chooseStyle(0)
            return
        }
        val habits = EmberCards.habits(this)
        if (habits.isEmpty()) {
            AlertDialog.Builder(this)
                .setMessage("Open Ember and add a habit first, then add this widget again.")
                .setPositiveButton("OK", null)
                .setOnDismissListener { finish() }
                .show()
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Which habit?")
            .setItems(habits.map { it.name }.toTypedArray()) { _, which -> chooseStyle(habits[which].id) }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun chooseStyle(habitId: Int) {
        val names = arrayOf("Dark", "Glass", "Habit colour")
        val styles = arrayOf("dark", "glass", "color")
        AlertDialog.Builder(this)
            .setTitle("Which look?")
            .setItems(names) { _, which -> finishWith(habitId, styles[which]) }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun finishWith(habitId: Int, style: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("ember_w${widgetId}_habit", habitId.toString())
            .putString("ember_w${widgetId}_style", style)
            .apply()
        val manager = AppWidgetManager.getInstance(this)
        val provider = manager.getAppWidgetInfo(widgetId)?.provider?.className ?: ""
        val kind = when {
            provider.endsWith("EmberStreakWidget") -> "streak"
            provider.endsWith("EmberRingWidget") -> "ring"
            provider.endsWith("EmberWeekWidget") -> "week"
            provider.endsWith("EmberTrendWidget") -> "trend"
            provider.endsWith("EmberMonthWidget") -> "month"
            else -> "grid"
        }
        EmberCards.update(this, manager, widgetId, kind)
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }
}
