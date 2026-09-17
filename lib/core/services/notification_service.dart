import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../theme/app_theme.dart';
import 'wavepass_api.dart';

enum NotifyType { success, error, warning, info }

class AppNotification {
  AppNotification({
    required this.type,
    required this.title,
    required this.message,
    DateTime? at,
    String? remoteId,
    this.reference,
    this.orderId,
    this.mac,
    this.planId,
    this.venueId,
    this.isApproval = false,
  })  : id = remoteId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        at = at ?? DateTime.now(),
        read = false;

  final String id;
  final NotifyType type;
  final String title;
  final String message;
  final DateTime at;
  final String? reference;
  final String? orderId;
  final String? mac;
  final String? planId;
  final String? venueId;
  final bool isApproval;
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
  GlobalKey<ScaffoldMessengerState>? _messengerKey;

  /// Bound once from main.dart so background pollers can render the exact
  /// same in-app modal as foreground callers without a BuildContext.
  void bindMessenger(GlobalKey<ScaffoldMessengerState> key) {
    _messengerKey = key;
  }

  /// Initializes the local notifications plugin, sets up high-importance channels,
  /// and requests POST_NOTIFICATIONS permission on Android 13+.
  Future<void> init() async {
    await _ensureBar();
  }

  int get unread => feed.value.where((n) => !n.read).length;

  void _add(AppNotification n) {
    if (_seenRemoteIds.contains(n.id)) return;
    _seenRemoteIds.add(n.id);
    feed.value = [n, ...feed.value];
  }

  /// In-feed only (or optional device bar) — used by backend payment polling.
  void push({
    required NotifyType type,
    required String title,
    required String message,
    String? remoteId,
    DateTime? at,
    bool showDeviceBar = false,
    String? reference,
    String? orderId,
    String? mac,
    String? planId,
    String? venueId,
    bool isApproval = false,
  }) {
    _add(AppNotification(
      type: type,
      title: title,
      message: message,
      remoteId: remoteId,
      at: at,
      reference: reference,
      orderId: orderId,
      mac: mac,
      planId: planId,
      venueId: venueId,
      isApproval: isApproval,
    ));
    if (showDeviceBar) {
      _showBar(
        title: title,
        message: message,
        type: type,
        payload: reference,
        isApproval: isApproval,
      );
    }
  }

  /// The single in-app modal renderer (floating white SnackBar). Both
  /// foreground `show()` and background poll alerts use this, so a payment
  /// alert looks exactly like the "Voucher In Use" modal.
  SnackBar _buildModal({
    required NotifyType type,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
    return SnackBar(
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
    );
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
      VoidCallback? onAction,
      bool showDeviceBar = true}) {
    final n = AppNotification(type: type, title: title, message: message);
    _add(n);
    ScaffoldMessenger.of(context).showSnackBar(
      _buildModal(type: type, title: title, message: message, actionLabel: actionLabel, onAction: onAction),
    );
    if (showDeviceBar) {
      _showBar(title: title, message: message, type: type);
    }
  }

  /// Same modal as [show], for callers without a BuildContext (payment poll).
  /// No-op when the messenger key is not bound yet.
  void showViaKey({
    required NotifyType type,
    required String title,
    required String message,
    bool showDeviceBar = true,
  }) {
    try {
      _messengerKey?.currentState?.showSnackBar(
        _buildModal(type: type, title: title, message: message),
      );
    } catch (_) {}
    if (showDeviceBar) {
      _showBar(title: title, message: message, type: type);
    }
  }
  void success(BuildContext c, String title, String msg, {String? action, VoidCallback? onAction, bool showDeviceBar = true}) =>
      show(c, type: NotifyType.success, title: title, message: msg, actionLabel: action, onAction: onAction, showDeviceBar: showDeviceBar);
  void error(BuildContext c, String title, String msg, {String? action, VoidCallback? onAction, bool showDeviceBar = true}) =>
      show(c, type: NotifyType.error, title: title, message: msg, actionLabel: action, onAction: onAction, showDeviceBar: showDeviceBar);
  void warning(BuildContext c, String title, String msg, {bool showDeviceBar = true}) =>
      show(c, type: NotifyType.warning, title: title, message: msg, showDeviceBar: showDeviceBar);
  void info(BuildContext c, String title, String msg, {bool showDeviceBar = true}) =>
      show(c, type: NotifyType.info, title: title, message: msg, showDeviceBar: showDeviceBar);

  // ── Device notification bar (venue-owner payment alerts & system bar) ───
  Future<bool> requestPermission() async {
    try {
      await _ensureBar();
      final androidPlugin = _bar.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final res = await androidPlugin.requestNotificationsPermission();
        return res ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _ensureBar() async {
    if (_barReady) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _bar.initialize(
        const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          await _handleNotificationAction(response);
        },
      );
      final androidPlugin = _bar.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        const channelPayments = AndroidNotificationChannel(
          'wavepass_payments',
          'Venue payments',
          description: 'Alerts when a guest pays your venue',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        );
        const channelAlerts = AndroidNotificationChannel(
          'wavepass_alerts',
          'WavePass Alerts',
          description: 'System alerts and voucher activity',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        );
        await androidPlugin.createNotificationChannel(channelPayments);
        await androidPlugin.createNotificationChannel(channelAlerts);
        // Explicitly request notification permissions on Android 13+ (POST_NOTIFICATIONS)
        await androidPlugin.requestNotificationsPermission();
      }
      _barReady = true;
    } catch (e) {
      debugPrint('Error initializing notification bar: $e');
    }
  }

  Future<void> _handleNotificationAction(NotificationResponse response) async {
    final payload = response.payload ?? '';
    final actionId = response.actionId ?? '';

    if (actionId == 'approve_access' || payload.startsWith('TRANSFER_APPROVAL:')) {
      final parts = payload.split(':');
      if (parts.length >= 4) {
        final orderId = parts[1];
        final mac = parts[2];
        final planId = parts[3];
        final venueId = parts.length >= 5 ? parts[4] : (_pollVenueId ?? '');

        try {
          final res = await WavePassApi.instance.approveAccess(
            venueId: venueId,
            orderId: orderId.isNotEmpty ? orderId : null,
            mac: mac,
            planId: planId.isNotEmpty ? planId : null,
            reference: payload,
          );

          final vCode = res['voucherCode']?.toString() ?? 'ACTIVE';

          await _showBar(
            title: '✅ Wi-Fi Access Approved',
            message: 'Access granted for $mac. Voucher $vCode is active.',
            type: NotifyType.success,
          );

          for (final n in feed.value) {
            if (n.reference == payload || (orderId.isNotEmpty && n.id.contains(orderId))) {
              n.read = true;
            }
          }
          feed.value = List.from(feed.value);

          showViaKey(
            type: NotifyType.success,
            title: '✅ Access Granted',
            message: 'Wi-Fi access approved for $mac (Pass: $vCode).',
            showDeviceBar: false,
          );
        } catch (e) {
          debugPrint('Error approving access from notification panel: $e');
        }
      }
    }
  }

  Future<bool> approveTransfer(AppNotification n) async {
    final venueId = n.venueId ?? _pollVenueId;
    final mac = n.mac;
    if (venueId == null || mac == null) {
      throw Exception('Approval is missing venue or device details — reopen the notification and retry.');
    }

    try {
      final res = await WavePassApi.instance.approveAccess(
        venueId: venueId,
        orderId: n.orderId,
        mac: mac,
        planId: n.planId,
        reference: n.reference,
      );
      if (res['ok'] == false) {
        throw Exception(
          res['error']?.toString() ?? res['message']?.toString() ?? 'Approval failed on server.',
        );
      }

      final vCode = res['voucherCode']?.toString() ?? 'ACTIVE';

      n.read = true;
      feed.value = List.from(feed.value);

      await _showBar(
        title: '✅ Wi-Fi Access Approved',
        message: 'Access granted for $mac (Voucher $vCode).',
        type: NotifyType.success,
      );

      showViaKey(
        type: NotifyType.success,
        title: '✅ Access Granted',
        message: 'Wi-Fi access approved for $mac (Pass: $vCode).',
        showDeviceBar: false,
      );
      return true;
    } catch (e) {
      debugPrint('Error approving transfer: $e');
      // Surface the real reason so owners never see a dead button again.
      rethrow;
    }
  }

  Future<void> _showBar({
    required String title,
    required String message,
    NotifyType type = NotifyType.info,
    String? payload,
    bool isApproval = false,
  }) async {
    try {
      await _ensureBar();
      if (!_barReady) return;
      final isPayment = type == NotifyType.success || isApproval;
      final channelId = isPayment ? 'wavepass_payments' : 'wavepass_alerts';
      final channelName = isPayment ? 'Venue payments' : 'WavePass Alerts';

      final List<AndroidNotificationAction> actions = [];
      if (isApproval) {
        actions.add(const AndroidNotificationAction(
          'approve_access',
          '✅ Approve Access',
          showsUserInterface: true,
          cancelNotification: true,
        ));
      }

      await _bar.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        message,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: isPayment ? Importance.max : Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
            actions: actions.isNotEmpty ? actions : null,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing bar notification: $e');
    }
  }

  /// Polls GET /notifications for the active venue. New alerts land in the
  /// in-app feed (Notifications tab) and — except on the silent first fill —
  /// render the identical in-app modal plus the Android notification bar.
  void startPaymentPolling(String venueId, {Duration interval = const Duration(seconds: 30)}) {
    if (_pollVenueId == venueId && _pollTimer?.isActive == true) return;
    stopPaymentPolling();
    _pollVenueId = venueId;
    _pollTimer = Timer.periodic(interval, (_) => refreshPayments(venueId, showBar: true, showModal: true));
    refreshPayments(venueId, showBar: false, showModal: false);
  }

  void stopPaymentPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollVenueId = null;
  }

  Future<void> refreshPayments(String venueId, {bool showBar = true, bool showModal = true}) async {
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
        final ref = r['reference']?.toString();
        final isApproval = ref != null && ref.startsWith('TRANSFER_APPROVAL:');
        String? orderId;
        String? mac;
        String? planId;
        if (isApproval) {
          final parts = ref.split(':');
          if (parts.length >= 4) {
            orderId = parts[1];
            mac = parts[2];
            planId = parts[3];
          }
        }

        DateTime? at;
        try {
          if (r['createdAt'] != null) at = DateTime.parse(r['createdAt'].toString());
        } catch (_) {}

        push(
          type: isApproval ? NotifyType.warning : type,
          title: title,
          message: message,
          remoteId: id,
          at: at,
          reference: ref,
          orderId: orderId,
          mac: mac,
          planId: planId,
          venueId: venueId,
          isApproval: isApproval,
        );

        if (typeRaw == 'PAYMENT' || isApproval) {
          if (showModal) {
            showViaKey(
              type: isApproval ? NotifyType.warning : type,
              title: title,
              message: message,
              showDeviceBar: false,
            );
          }
          if (showBar) {
            await _showBar(
              title: title,
              message: message,
              type: isApproval ? NotifyType.warning : type,
              payload: isApproval ? ref : null,
              isApproval: isApproval,
            );
          }
        }
      }
    } catch (_) {}
  }

  /// Interactive pop-up dialog upon adding or activating a venue to prompt enabling notifications.
  static Future<void> promptEnableNotifications(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Enable Notifications",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Stay instantly alerted about your venue customers even when the app is closed:",
              style: TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.4),
            ),
            const SizedBox(height: 16),
            _buildNotificationFeature(
              Icons.check_circle_rounded,
              AppColors.accentGreen,
              "Bank Transfer Approvals",
              "Confirm & grant Wi-Fi access with 1 tap directly from the notification panel.",
            ),
            const SizedBox(height: 12),
            _buildNotificationFeature(
              Icons.payments_rounded,
              AppColors.primary,
              "Online Store Payments",
              "Instant device chime when customers buy passes online via Paystack.",
            ),
            const SizedBox(height: 12),
            _buildNotificationFeature(
              Icons.router_rounded,
              Colors.amber.shade800,
              "Router & Voucher Alerts",
              "Immediate notice if your MikroTik router goes offline or passes expire.",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Maybe Later", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AppNotifier.instance.requestPermission();
              await AppNotifier.instance.init();
              if (context.mounted) {
                AppNotifier.instance.success(
                  context,
                  "Notifications Active",
                  "Device alerts are enabled. You will receive notifications for customer transfers and sales.",
                );
              }
            },
            child: const Text("Enable Notifications", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  static Widget _buildNotificationFeature(IconData icon, Color color, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              const SizedBox(height: 1),
              Text(
                desc,
                style: const TextStyle(fontSize: 11, color: AppColors.textLight, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
