import 'package:flutter/material.dart';
import '../core/services/notification_service.dart';
import '../core/theme/app_theme.dart';
class NotificationCenterSheet extends StatelessWidget {
  const NotificationCenterSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (c, ctrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ValueListenableBuilder<List<AppNotification>>(
          valueListenable: AppNotifier.instance.feed,
          builder: (c, items, _) => Column(children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primary)),
              TextButton(onPressed: AppNotifier.instance.markAllRead, child: const Text('Mark all read')),
            ])),
            const Divider(height: 1),
            Expanded(child: items.isEmpty ? const Center(child: Text('No notifications yet', style: TextStyle(color: AppColors.textLight))) : ListView.separated(controller: ctrl, padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (c, i) {
                  final n = items[i];
                  final color = {NotifyType.success: AppColors.accentGreen, NotifyType.error: AppColors.accentRed, NotifyType.warning: const Color(0xFFD97706), NotifyType.info: AppColors.primary}[n.type]!;
                  return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: n.read ? Colors.white : AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(n.type == NotifyType.success ? Icons.check_circle : n.type == NotifyType.error ? Icons.error : n.type == NotifyType.warning ? Icons.warning : Icons.info, color: color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(n.message, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                      const SizedBox(height: 4),
                      Text('${n.at.hour}:${n.at.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                    ])),
                    if (!n.read) Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ]));
                })),
          ]),
        ),
      ),
    );
  }
  static void show(BuildContext c) => showModalBottomSheet(context: c, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const NotificationCenterSheet());
}
