import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';

/// [DateFormat] construction is expensive (locale data lookup + pattern
/// parsing), and these formatters run for every visible room tile and message
/// timestamp on every rebuild. Instances are therefore cached per
/// pattern/locale pair; the key set stays bounded because every pattern is a
/// compile-time constant and the locale count is small.
final Map<String, DateFormat> _dateFormatCache = <String, DateFormat>{};

DateFormat _cachedDateFormat(String key, DateFormat Function() build) =>
    _dateFormatCache.putIfAbsent(key, build);

DateFormat _cachedPatternFormat(String pattern, String locale) =>
    _cachedDateFormat(
      '$pattern\u0000$locale',
      () => DateFormat(pattern, locale),
    );

/// Provides extra functionality for formatting the time.
extension DateTimeExtension on DateTime {
  bool operator <(DateTime other) {
    return millisecondsSinceEpoch < other.millisecondsSinceEpoch;
  }

  bool operator >(DateTime other) {
    return millisecondsSinceEpoch > other.millisecondsSinceEpoch;
  }

  bool operator >=(DateTime other) {
    return millisecondsSinceEpoch >= other.millisecondsSinceEpoch;
  }

  bool operator <=(DateTime other) {
    return millisecondsSinceEpoch <= other.millisecondsSinceEpoch;
  }

  /// Checks if two DateTimes are close enough to belong to the same
  /// environment.
  bool sameEnvironment(DateTime prevTime) =>
      difference(prevTime) < const Duration(hours: 1);

  String localizedMessageTime(BuildContext context) =>
      AppSettings.showSeconds.value
      ? localizedTimeOfDaySeconds(context)
      : localizedTimeOfDay(context);

  String localizedTimeOfDaySeconds(BuildContext context) =>
      (MediaQuery.alwaysUse24HourFormatOf(context) ||
          L10n.of(context).alwaysUse24HourFormat == 'true')
      ? _cachedPatternFormat(
          'HH:mm:ss',
          L10n.of(context).localeName,
        ).format(this)
      : _cachedPatternFormat(
          'h:mm:ss a',
          L10n.of(context).localeName,
        ).format(this);

  /// Returns a simple time String.
  String localizedTimeOfDay(BuildContext context) =>
      (MediaQuery.alwaysUse24HourFormatOf(context) ||
          L10n.of(context).alwaysUse24HourFormat == 'true')
      ? _cachedPatternFormat('HH:mm', L10n.of(context).localeName).format(this)
      : _cachedPatternFormat(
          'h:mm a',
          L10n.of(context).localeName,
        ).format(this);

  /// Returns [localizedTimeOfDay()] if the ChatTime is today, the name of the week
  /// day if the ChatTime is this week and a date string else.
  String localizedTimeShort(BuildContext context) {
    final now = DateTime.now();

    final sameYear = now.year == year;

    final sameDay = sameYear && now.month == month && now.day == day;

    final sameWeek =
        sameYear &&
        !sameDay &&
        now.millisecondsSinceEpoch - millisecondsSinceEpoch <
            1000 * 60 * 60 * 24 * 7;

    if (sameDay) {
      return localizedTimeOfDay(context);
    } else if (sameWeek) {
      final languageCode = Localizations.localeOf(context).languageCode;
      return _cachedDateFormat(
        'E\u0000$languageCode',
        () => DateFormat.E(languageCode),
      ).format(this);
    } else if (sameYear) {
      final languageCode = Localizations.localeOf(context).languageCode;
      return _cachedDateFormat(
        'MMMd\u0000$languageCode',
        () => DateFormat.MMMd(languageCode),
      ).format(this);
    }
    final languageCode = Localizations.localeOf(context).languageCode;
    return _cachedDateFormat(
      'yMMMd\u0000$languageCode',
      () => DateFormat.yMMMd(languageCode),
    ).format(this);
  }

  /// If the DateTime is today, this returns [localizedTimeOfDay()], if not it also
  /// shows the date.
  /// TODO: Add localization
  String localizedTime(BuildContext context) {
    final now = DateTime.now();

    final sameYear = now.year == year;

    final sameDay = sameYear && now.month == month && now.day == day;

    if (sameDay) return localizedTimeOfDay(context);
    return L10n.of(context).dateAndTimeOfDay(
      localizedTimeShort(context),
      localizedTimeOfDay(context),
    );
  }
}
