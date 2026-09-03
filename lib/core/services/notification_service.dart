import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NotifyType { success, error, warning, info }

class AppNotification {
  AppNotification({required this.type, required this.title, required this.message, DateTime? at})
      : id = DateTime.now().microsecondsSinceEpoch.toString(),
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
  int get unread => feed.value.where((n) => !n.read).length;
  void _add(AppNotification n) {
    feed.value = [n, ...feed.value];
    feed.notifyListeners();
  }
  void markAllRead() {
    for (final n in feed.value) n.read = true;
    feed.notifyListeners();
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
}
