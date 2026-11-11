package ru.napominator.napominator

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Виджет «Цели на сегодня». Данные готовит Dart (lib/services/widget_sync.dart). */
class TodayWidgetProvider : HomeWidgetProvider() {

    private val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val dotIds = intArrayOf(R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4, R.id.dot5)
    private val titleIds = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4, R.id.title5)
    private val checkIds = intArrayOf(R.id.check0, R.id.check1, R.id.check2, R.id.check3, R.id.check4, R.id.check5)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        var items = JSONArray()
        try {
            val raw = widgetData.getString("today_json", null)
            if (raw != null) {
                val obj = JSONObject(raw)
                items = if (obj.optString("date") == today) {
                    obj.optJSONArray("today") ?: JSONArray()
                } else {
                    // День сменился, а приложение ещё не запускалось — показываем прогноз.
                    obj.optJSONArray("next") ?: JSONArray()
                }
            }
        } catch (e: Exception) {
            items = JSONArray()
        }

        val total = items.length()
        var done = 0
        for (i in 0 until total) {
            if (items.optJSONObject(i)?.optBoolean("done") == true) done++
        }
        val textColor = context.getColor(R.color.widget_text)
        val mutedColor = context.getColor(R.color.widget_muted)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)

            views.setOnClickPendingIntent(
                R.id.w_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
            views.setTextViewText(
                R.id.w_progress,
                if (total == 0) "" else "$done из $total"
            )
            views.setProgressBar(R.id.w_bar, if (total == 0) 1 else total, done, false)
            views.setViewVisibility(R.id.w_empty, if (total == 0) View.VISIBLE else View.GONE)

            for (r in rowIds.indices) {
                val item = if (r < total) items.optJSONObject(r) else null
                if (item == null) {
                    views.setViewVisibility(rowIds[r], View.GONE)
                    continue
                }
                val isDone = item.optBoolean("done")
                val color = try {
                    Color.parseColor(item.optString("color", "#FF6366F1"))
                } catch (e: Exception) {
                    Color.parseColor("#FF6366F1")
                }
                views.setViewVisibility(rowIds[r], View.VISIBLE)
                views.setTextViewText(titleIds[r], item.optString("title"))
                views.setTextColor(titleIds[r], if (isDone) mutedColor else textColor)
                views.setInt(dotIds[r], "setColorFilter", color)
                views.setImageViewResource(
                    checkIds[r],
                    if (isDone) R.drawable.w_check_on else R.drawable.w_check_off
                )
                views.setInt(checkIds[r], "setColorFilter", if (isDone) color else mutedColor)
                val uri = Uri.parse("napominator://toggle?id=" + Uri.encode(item.optString("id")))
                views.setOnClickPendingIntent(
                    checkIds[r],
                    HomeWidgetBackgroundIntent.getBroadcast(context, uri)
                )
            }

            if (total > rowIds.size) {
                views.setViewVisibility(R.id.w_more, View.VISIBLE)
                views.setTextViewText(R.id.w_more, "и ещё ${total - rowIds.size} — открыть приложение")
            } else {
                views.setViewVisibility(R.id.w_more, View.GONE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
