package ru.napominator.napominator

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Виджет «Цели на сегодня» + постоянное уведомление-панель на экране блокировки.
 * Данные готовит Dart (lib/services/widget_sync.dart) и кладёт в HomeWidgetPreferences.
 * Каждое обновление из Dart присылает сюда broadcast — по нему перерисовываем и виджет, и панель.
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_MIDNIGHT = "ru.napominator.napominator.MIDNIGHT"
        private const val PANEL_CHANNEL = "today_panel"
        private const val PANEL_ID = 7
        private const val DEFAULT_COLOR = "#FF6366F1"
        private const val MUTED = "#FF8A8A99"

        fun readItems(prefs: SharedPreferences): JSONArray {
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            return try {
                val raw = prefs.getString("today_json", null) ?: return JSONArray()
                val obj = JSONObject(raw)
                if (obj.optString("date") == today) {
                    obj.optJSONArray("today") ?: JSONArray()
                } else {
                    // День сменился, а приложение ещё не запускалось — показываем прогноз.
                    obj.optJSONArray("next") ?: JSONArray()
                }
            } catch (e: Exception) {
                JSONArray()
            }
        }

        /** Включена ли панель на экране блокировки (настройка в приложении). */
        fun panelEnabled(prefs: SharedPreferences): Boolean = try {
            val raw = prefs.getString("today_json", null)
            raw == null || JSONObject(raw).optBoolean("panel", true)
        } catch (e: Exception) {
            true
        }

        fun countDone(items: JSONArray): Int {
            var done = 0
            for (i in 0 until items.length()) {
                if (items.optJSONObject(i)?.optBoolean("done") == true) done++
            }
            return done
        }

        fun parseColor(s: String?): Int = try {
            Color.parseColor(s ?: DEFAULT_COLOR)
        } catch (e: Exception) {
            Color.parseColor(DEFAULT_COLOR)
        }

        /** Заполнить строки целей (точка цвета, название, кружок-отметка). */
        fun fillRows(
            context: Context,
            views: RemoteViews,
            items: JSONArray,
            rowIds: IntArray,
            dotIds: IntArray,
            titleIds: IntArray,
            checkIds: IntArray,
            textColor: Int?,
            mutedColor: Int
        ) {
            for (r in rowIds.indices) {
                val item = if (r < items.length()) items.optJSONObject(r) else null
                if (item == null) {
                    views.setViewVisibility(rowIds[r], View.GONE)
                    continue
                }
                val isDone = item.optBoolean("done")
                val color = parseColor(item.optString("color", DEFAULT_COLOR))
                views.setViewVisibility(rowIds[r], View.VISIBLE)
                views.setTextViewText(titleIds[r], item.optString("title"))
                if (isDone) {
                    views.setTextColor(titleIds[r], mutedColor)
                } else if (textColor != null) {
                    views.setTextColor(titleIds[r], textColor)
                }
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
        }

        private fun headerText(done: Int, total: Int): String {
            val left = total - done
            return if (left == 0) "Сегодня всё выполнено · $done из $total"
            else "Сегодня: осталось $left из $total"
        }

        /** Постоянное уведомление со списком целей (видно на экране блокировки). */
        fun updatePanel(context: Context, items: JSONArray) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val total = items.length()
            if (total == 0) {
                nm.cancel(PANEL_ID)
                return
            }
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) return

            if (Build.VERSION.SDK_INT >= 26) {
                // IMPORTANCE_DEFAULT без звука: «тихие» (LOW) Android прячет с экрана блокировки.
                val ch = NotificationChannel(
                    PANEL_CHANNEL, "Цели на экране блокировки",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
                ch.description = "Список целей на сегодня с отметкой прямо с экрана блокировки"
                ch.setSound(null, null)
                ch.enableVibration(false)
                ch.setShowBadge(false)
                ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                nm.createNotificationChannel(ch)
            }

            val done = countDone(items)
            val muted = parseColor(MUTED)
            val header = headerText(done, total)

            // Свёрнутый вид: заголовок + первая невыполненная цель.
            val small = RemoteViews(context.packageName, R.layout.notif_small)
            small.setTextViewText(R.id.s_header, header)
            val firstOpen = JSONArray()
            for (i in 0 until total) {
                val obj = items.optJSONObject(i)
                if (obj != null && !obj.optBoolean("done")) {
                    firstOpen.put(obj); break
                }
            }
            fillRows(
                context, small, firstOpen,
                intArrayOf(R.id.s_row0), intArrayOf(R.id.s_dot0),
                intArrayOf(R.id.s_title0), intArrayOf(R.id.s_check0), null, muted
            )

            // Развёрнутый вид: прогресс + до 5 целей.
            val big = RemoteViews(context.packageName, R.layout.notif_big)
            big.setTextViewText(R.id.n_header, header)
            big.setProgressBar(R.id.n_bar, total, done, false)
            fillRows(
                context, big, items,
                intArrayOf(R.id.n_row0, R.id.n_row1, R.id.n_row2, R.id.n_row3, R.id.n_row4),
                intArrayOf(R.id.n_dot0, R.id.n_dot1, R.id.n_dot2, R.id.n_dot3, R.id.n_dot4),
                intArrayOf(R.id.n_title0, R.id.n_title1, R.id.n_title2, R.id.n_title3, R.id.n_title4),
                intArrayOf(R.id.n_check0, R.id.n_check1, R.id.n_check2, R.id.n_check3, R.id.n_check4),
                null, muted
            )
            if (total > 5) {
                big.setViewVisibility(R.id.n_more, View.VISIBLE)
                big.setTextViewText(R.id.n_more, "и ещё ${total - 5} — открыть приложение")
            } else {
                big.setViewVisibility(R.id.n_more, View.GONE)
            }

            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, PANEL_CHANNEL)
            } else {
                Notification.Builder(context).setPriority(Notification.PRIORITY_DEFAULT)
            }
            builder
                .setSmallIcon(R.drawable.ic_stat_goal)
                .setContentTitle(header)
                .setContentText(if (done == total) "Отличная работа!" else "Нажмите на кружок, чтобы отметить")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setCategory(Notification.CATEGORY_STATUS)
                .setContentIntent(HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            if (Build.VERSION.SDK_INT >= 24) {
                builder.setStyle(Notification.DecoratedCustomViewStyle())
                builder.setCustomContentView(small)
                builder.setCustomBigContentView(big)
            }
            nm.notify(PANEL_ID, builder.build())
        }

        /** Перерисовать всё сразу после полуночи, даже если приложение не открывали. */
        fun scheduleMidnight(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, TodayWidgetProvider::class.java).setAction(ACTION_MIDNIGHT)
            val pi = PendingIntent.getBroadcast(
                context, 7001, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val cal = Calendar.getInstance()
            cal.add(Calendar.DAY_OF_YEAR, 1)
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 1)
            cal.set(Calendar.SECOND, 0)
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            }
        }
    }

    private val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val dotIds = intArrayOf(R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4, R.id.dot5)
    private val titleIds = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4, R.id.title5)
    private val checkIds = intArrayOf(R.id.check0, R.id.check1, R.id.check2, R.id.check3, R.id.check4, R.id.check5)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        if (action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            action == ACTION_MIDNIGHT ||
            action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            try {
                updatePanel(context, if (panelEnabled(prefs)) readItems(prefs) else JSONArray())
            } catch (e: Exception) {
                // не мешаем работе виджета
            }
            scheduleMidnight(context)
            if (action != AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = mgr.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
                if (ids.isNotEmpty()) onUpdate(context, mgr, ids, prefs)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val items = readItems(widgetData)
        val total = items.length()
        val done = countDone(items)
        val textColor = context.getColor(R.color.widget_text)
        val mutedColor = context.getColor(R.color.widget_muted)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setOnClickPendingIntent(
                R.id.w_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
            views.setTextViewText(R.id.w_progress, if (total == 0) "" else "$done из $total")
            views.setProgressBar(R.id.w_bar, if (total == 0) 1 else total, done, false)
            views.setViewVisibility(R.id.w_empty, if (total == 0) View.VISIBLE else View.GONE)
            fillRows(context, views, items, rowIds, dotIds, titleIds, checkIds, textColor, mutedColor)
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
