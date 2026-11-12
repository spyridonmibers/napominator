import 'day.dart';
import 'goal.dart' show RepeatType;

/// Будильник — отдельная от целей сущность со своим графиком.
class AlarmItem {
  AlarmItem({
    required this.id,
    required this.nativeId,
    required this.minutes,
    this.label = '',
    this.repeat = RepeatType.daily,
    Set<int>? weekdays,
    this.cycleOn = 2,
    this.cycleOff = 2,
    required this.startDate,
    this.enabled = true,
    this.sound = 'builtin:soft',
    this.soundTitle = 'Мягкое утро',
    this.vibrate = true,
    this.ramp = true,
    this.snoozeMinutes = 10,
    this.colorIndex = 0,
  }) : weekdays = weekdays ?? <int>{1, 2, 3, 4, 5};

  final String id;

  /// Числовой id для системных будильников (PendingIntent / AlarmKit).
  final int nativeId;

  /// Время срабатывания в минутах от полуночи.
  int minutes;
  String label;
  RepeatType repeat;
  Set<int> weekdays;
  int cycleOn;
  int cycleOff;

  /// От этой даты считаются «через день» и свой график.
  DateTime startDate;
  bool enabled;

  /// builtin:<key> — встроенная мелодия; uri:<...> — системная/своя (Android).
  String sound;
  String soundTitle;
  bool vibrate;

  /// Нарастающая громкость.
  bool ramp;
  int snoozeMinutes;
  int colorIndex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nativeId': nativeId,
        'minutes': minutes,
        'label': label,
        'repeat': repeat.name,
        'weekdays': weekdays.toList()..sort(),
        'cycleOn': cycleOn,
        'cycleOff': cycleOff,
        'startDate': dayKey(startDate),
        'enabled': enabled,
        'sound': sound,
        'soundTitle': soundTitle,
        'vibrate': vibrate,
        'ramp': ramp,
        'snoozeMinutes': snoozeMinutes,
        'colorIndex': colorIndex,
      };

  factory AlarmItem.fromJson(Map<String, dynamic> j) => AlarmItem(
        id: j['id'] as String,
        nativeId: (j['nativeId'] as num).toInt(),
        minutes: (j['minutes'] as num).toInt(),
        label: j['label'] as String? ?? '',
        repeat: RepeatType.values.asNameMap()[j['repeat']] ?? RepeatType.daily,
        weekdays: ((j['weekdays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        cycleOn: (j['cycleOn'] as num?)?.toInt() ?? 2,
        cycleOff: (j['cycleOff'] as num?)?.toInt() ?? 2,
        startDate: parseDay(j['startDate'] as String),
        enabled: j['enabled'] as bool? ?? true,
        sound: j['sound'] as String? ?? 'builtin:soft',
        soundTitle: j['soundTitle'] as String? ?? 'Мягкое утро',
        vibrate: j['vibrate'] as bool? ?? true,
        ramp: j['ramp'] as bool? ?? true,
        snoozeMinutes: (j['snoozeMinutes'] as num?)?.toInt() ?? 10,
        colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
      );
}

/// Встроенные мелодии: ключ → название.
const builtinAlarmSounds = <String, String>{
  'soft': 'Мягкое утро',
  'bells': 'Колокольчики',
  'energetic': 'Бодрый',
  'classic': 'Классический звон',
  'rising': 'Нарастающий',
  'red': 'Красный',
  'green': 'Зелёный',
};

const builtinAlarmHints = <String, String>{
  'soft': 'Светлая маримба',
  'bells': 'Нежный перезвон',
  'energetic': 'Ритмичный и весёлый',
  'classic': 'Звонок механического будильника',
  'rising': 'С каждым повтором выше',
  'red': 'Тревожный и настойчивый',
  'green': 'Спокойный, тёплые аккорды и птицы',
};
