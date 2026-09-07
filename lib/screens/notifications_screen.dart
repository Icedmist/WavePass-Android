import 'package:flutter/material.dart';
import '../core/services/notification_service.dart';
import '../core/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NState();
}

class _NState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => Navigator.of(context).maybePop()), title: const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)), actions: [TextButton(onPressed: AppNotifier.instance.markAllRead, child: const Text('Mark all read')), IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.textLight), onPressed: () { AppNotifier.instance.feed.value = []; }, tooltip: 'Clear all')]),
      body: ValueListenableBuilder<List<AppNotification>>(
        valueListenable: AppNotifier.instance.feed,
        builder: (c, items, _) {
          if (items.isEmpty) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.textLight), SizedBox(height: 12), Text('No notifications yet', style: TextStyle(color: AppColors.textLight)), SizedBox(height: 4), Text('Device alerts, voucher usage and cashouts will appear here.', style: TextStyle(fontSize: 12, color: AppColors.textLight))]));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (c, i) {
              final n = items[i];
              final color = {NotifyType.success: AppColors.accentGreen, NotifyType.error: AppColors.accentRed, NotifyType.warning: const Color(0xFFD97706), NotifyType.info: AppColors.primary}[n.type]!;
              final icon = {NotifyType.success: Icons.check_circle_rounded, NotifyType.error: Icons.error_rounded, NotifyType.warning: Icons.warning_amber_rounded, NotifyType.info: Icons.info_rounded}[n.type]!;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: n.read ? Colors.white : AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                    const SizedBox(height: 2),
                    Text(n.message, style: const TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4)),
                    const SizedBox(height: 6),
                    Text('${n.at.hour.toString().padLeft(2, '0')}:${n.at.minute.toString().padLeft(2, '0')} • ${n.at.day}/${n.at.month}', style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                  ])),
                  if (!n.read) Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
