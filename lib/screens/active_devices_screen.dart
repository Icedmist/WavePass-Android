import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class ActiveDevicesScreen extends StatefulWidget {
  const ActiveDevicesScreen({super.key});

  @override
  State<ActiveDevicesScreen> createState() => _ActiveDevicesScreenState();
}

class _ActiveDevicesScreenState extends State<ActiveDevicesScreen> {
  final List<Map<String, dynamic>> _devices = [
    {
      'name': 'Samsung Galaxy S23',
      'mac': 'D4:3A:48:9E:C1:8A',
      'ip': '10.5.50.14',
      'plan': '12 Hour Pass',
      'timeLeft': '5h 12m left',
      'progress': 0.58,
    },
    {
      'name': 'Apple iPhone 15 Pro',
      'mac': 'A8:51:5B:3C:99:12',
      'ip': '10.5.50.22',
      'plan': '1 Hour Pass',
      'timeLeft': '24m left',
      'progress': 0.40,
    },
    {
      'name': 'MacBook Pro 14"',
      'mac': '3C:06:30:4F:77:E1',
      'ip': '10.5.50.08',
      'plan': '24 Hour All-Day',
      'timeLeft': '18h 40m left',
      'progress': 0.77,
    },
    {
      'name': 'Google Pixel 8',
      'mac': '90:9A:4A:12:33:FF',
      'ip': '10.5.50.31',
      'plan': '1 Hour Pass',
      'timeLeft': '8m left',
      'progress': 0.13,
    },
  ];

  void _disconnectDevice(int index) {
    final dev = _devices[index];
    setState(() {
      _devices.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${dev['name']} disconnected from Wi-Fi."),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Active Devices",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                "${_devices.length} Online",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentGreen,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _devices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final dev = _devices[index];

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smartphone, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          dev['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _disconnectDevice(index),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Text(
                          "Disconnect",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Text(
                      dev['mac'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      dev['ip'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Time remaining progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: dev['progress'],
                    minHeight: 6,
                    backgroundColor: Colors.black.withOpacity(0.06),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                  ),
                ),
                const SizedBox(height: 6),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dev['plan'],
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                    Text(
                      dev['timeLeft'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
