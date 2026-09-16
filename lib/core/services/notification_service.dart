import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../theme/app_theme.dart';
import 'wavepass_api.dart';

enum NotifyType { success, error, warning, info }

class AppNotification {
  AppNotification({required this.type, required this.title, required this.message, DateTime? at, String? remoteId})
      : id = remoteId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        at = at ?? DateTime.now(),
        read = false;
  final String id;
  final NotifyType type;
  final String title;
  final String message;
  final DateTime at;
  bool read;
}

class AppNotifier {
  AppNotifier._();
  static final AppNotifier instance = AppNotifier._();
  final ValueNotifier<List<AppNotification>> feed = ValueNotifier([]);
  final FlutterLocalNotificationsPlugin _bar = FlutterLocalNotificationsPlugin();
  bool _barReady = false;
  Timer? _pollTimer;
  String? _pollVenueId;
  final Set<String> _seenRemoteIds = {};

  int get unread => feed.value.where((n) => !n.read).length;

  void _add(AppNotification n) {
    if (_seenRemoteIds.contains(n.id)) return;
    _seenRemoteIds.add(n.id);
    feed.value = [n, ...feed.value];
  }

  /// In-feed only (no snackbar) — used by backend payment polling.
  void push({required NotifyType type, required String title, required String message, String? remoteId, DateTime? at}) {
    _add(AppNotification(type: type, title: title, message: message, remoteId: remoteId, at: at));
  }
  void markAllRead() {
    for (final n in feed.value) {
      n.read = true;
    }
    feed.value = List.from(feed.value);
  }

  void show(BuildContext context,
      {required NotifyType type,
      required String title,
      required String message,
      String? actionLabel,
      VoidCallback? onAction}) {
    final n = AppNotification(type: type, title: title, message: message);
    _add(n);
    final colors = {
      NotifyType.success: AppColors.accentGreen,
      NotifyType.error: AppColors.accentRed,
      NotifyType.warning: const Color(0xFFD97706),
      NotifyType.info: AppColors.primary,
    };
    final icons = {
      NotifyType.success: Icons.check_circle,
      NotifyType.error: Icons.error,
      NotifyType.warning: Icons.warning_amber_rounded,
      NotifyType.info: Icons.info,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      backgroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: colors[type]!.withValues(alpha: 0.2))),
      duration: const Duration(seconds: 4),
      content: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colors[type]!.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icons[type], color: colors[type], size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: colors[type])),
          Text(message, style: const TextStyle(fontSize: 12, color: AppColors.textLight), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
      action: actionLabel != null ? SnackBarAction(label: actionLabel, textColor: colors[type], onPressed: () => onAction?.call()) : null,
    ));
  }
  void success(BuildContext c, String title, String msg, {String? action, VoidCallback? onAction}) => show(c, type: NotifyType.success, title: title, message: msg, actionLabel: action, onAction: onAction);
  void error(BuildContext c, String title, String msg, {String? action, VoidCallback? onAction}) => show(c, type: NotifyType.error, title: title, message: msg, actionLabel: action, onAction: onAction);
  void warning(BuildContext c, String title, String msg) => show(c, type: NotifyType.warning, title: title, message: msg);
  void info(BuildContext c, String title, String msg) => show(c, type: NotifyType.info, title: title, message: msg);

  // ── Device notification bar (venue-owner payment alerts) ──────────────
  Future<void> _ensureBar() async {
    if (_barReady) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _bar.initialize(const InitializationSettings(android: android));
      const channel = AndroidNotificationChannel(
        'wavepass_payments',
        'Venue payments',
        description: 'Alerts when a guest pays your venue',
        importance: Importance.high,
      );
      await _bar.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
      _barReady = true;
    } catch (_) {
      // Plugin not installed yet (flutter pub get pending) — in-feed still works.
    }
  }

  Future<void> _showBar({required String title, required String message}) async {
    try {
      await _ensureBar();
      if (!_barReady) return;
      await _bar.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails('wavepass_payments', 'Venue payments', importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {}
  }

  /// Polls GET /notifications for the active venue and surfaces payment alerts
  /// in both the in-app feed and the Android notification bar.
  void startPaymentPolling(String venueId, {Duration interval = const Duration(seconds: 30)}) {
    if (_pollVenueId == venueId && _pollTimer?.isActive == true) return;
    stopPaymentPolling();
    _pollVenueId = venueId;
    _pollTimer = Timer.periodic(interval, (_) => refreshPayments(venueId, showBar: true));
    refreshPayments(venueId, showBar: false);
  }

  void stopPaymentPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollVenueId = null;
  }

  Future<void> refreshPayments(String venueId, {bool showBar = true}) async {
    try {
      final rows = await WavePassApi.instance.listNotifications(venueId);
      for (final r in rows) {
        if (r is! Map) continue;
        final id = r['id']?.toString();
        if (id == null || _seenRemoteIds.contains(id)) continue;
        final typeRaw = (r['type']?.toString() ?? 'PAYMENT').toUpperCase();
        final type = typeRaw == 'VOUCHER' ? NotifyType.info : NotifyType.success;
        final title = r['title']?.toString() ?? 'Payment received';
        final message = r['body']?.toString() ?? '';
        DateTime? at;
        try {
          if (r['createdAt'] != null) at = DateTime.parse(r['createdAt'].toString());
        } catch (_) {}
        push(type: type, title: title, message: message, remoteId: id, at: at);
        if (showBar && typeRaw == 'PAYMENT') {
          await _showBar(title: title, message: message);
        }
      }
    } catch (_) {}
  }
}
