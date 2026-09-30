import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String? htmlUrl;
  final DateTime? publishedAt;
  final int? assetSizeBytes;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    this.releaseNotes = '',
    this.downloadUrl,
    this.htmlUrl,
    this.publishedAt,
    this.assetSizeBytes,
  });
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String currentVersion = '1.0.1+2';
  static const String repoOwner = 'Icedmist';
  static const String repoName = 'WavePass-Android';
  static const String keyLastCheck = 'wavepass_last_update_check_ms';
  static const int checkCooldownHours = 4;

  http.Client? _client;

  @visibleForTesting
  set mockClient(http.Client client) => _client = client;

  http.Client get _httpClient => _client ?? http.Client();

  /// Compares two semver strings (supports optional 'v' prefix and build suffix e.g. 1.0.1+2).
  /// Returns true if [latestStr] is strictly greater than [currentStr].
  static bool isNewerVersion(String latestStr, String currentStr) {
    try {
      final cleanLatest = latestStr.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final cleanCurrent = currentStr.trim().replaceFirst(RegExp(r'^[vV]'), '');

      final latestParts = cleanLatest.split('+');
      final currentParts = cleanCurrent.split('+');

      final latestSemver = latestParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentSemver = currentParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (latestSemver.length < 3) {
        latestSemver.add(0);
      }
      while (currentSemver.length < 3) {
        currentSemver.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (latestSemver[i] > currentSemver[i]) return true;
        if (latestSemver[i] < currentSemver[i]) return false;
      }

      // If major.minor.patch are equal, check build number if present
      final latestBuild = latestParts.length > 1 ? (int.tryParse(latestParts[1]) ?? 0) : 0;
      final currentBuild = currentParts.length > 1 ? (int.tryParse(currentParts[1]) ?? 0) : 0;
      return latestBuild > currentBuild;
    } catch (_) {
      return false;
    }
  }

  /// Checks GitHub Releases for a newer version of WavePass Android.
  Future<AppUpdateInfo> checkForUpdate({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(keyLastCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && (now - lastCheck) < (checkCooldownHours * 3600 * 1000)) {
      return const AppUpdateInfo(
        hasUpdate: false,
        latestVersion: currentVersion,
        currentVersion: currentVersion,
      );
    }

    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await _httpClient.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'WavePass-Android-Updater',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await prefs.setInt(keyLastCheck, now);
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name']?.toString() ?? '';
        final body = data['body']?.toString() ?? 'Bug fixes and performance improvements.';
        final htmlUrl = data['html_url']?.toString();
        final publishedAtStr = data['published_at']?.toString();
        final publishedAt = publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

        String? apkDownloadUrl;
        int? assetSize;

        final assets = data['assets'] as List<dynamic>?;
        if (assets != null) {
          for (final asset in assets) {
            final name = asset['name']?.toString().toLowerCase() ?? '';
            if (name.endsWith('.apk')) {
              apkDownloadUrl = asset['browser_download_url']?.toString();
              assetSize = asset['size'] as int?;
              break;
            }
          }
        }

        final hasNewer = isNewerVersion(tagName, currentVersion);
        return AppUpdateInfo(
          hasUpdate: hasNewer,
          latestVersion: tagName.replaceFirst(RegExp(r'^[vV]'), ''),
          currentVersion: currentVersion,
          releaseNotes: body,
          downloadUrl: apkDownloadUrl,
          htmlUrl: htmlUrl,
          publishedAt: publishedAt,
          assetSizeBytes: assetSize,
        );
      }
    } catch (_) {}

    return const AppUpdateInfo(
      hasUpdate: false,
      latestVersion: currentVersion,
      currentVersion: currentVersion,
    );
  }

  /// Downloads the release APK with progress and triggers native Android package installer.
  Future<bool> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, String status) onProgress,
  }) async {
    try {
      onProgress(0.0, 'Connecting to release server...');
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'WavePass-Android-Updater';

      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        onProgress(0.0, 'Download failed (HTTP ${response.statusCode})');
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/wavepass_release_update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int downloaded = 0;

      await for (final chunk in response.stream) {
        downloaded += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          final progress = downloaded / contentLength;
          final mbDownloaded = (downloaded / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, 'Downloading: $mbDownloaded / $mbTotal MB');
        } else {
          final mbDownloaded = (downloaded / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, 'Downloading: $mbDownloaded MB');
        }
      }

      await sink.flush();
      await sink.close();

      onProgress(1.0, 'Download complete. Launching installer...');

      final result = await OpenFile.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      return result.type == ResultType.done;
    } catch (e) {
      onProgress(0.0, 'Update error: $e');
      return false;
    }
  }

  /// Checks and presents an update modal if a newer release exists.
  Future<void> checkAndPromptIfAvailable(BuildContext context, {bool force = false}) async {
    final update = await checkForUpdate(force: force);
    if (!update.hasUpdate || !context.mounted) return;
    showUpdateDialog(context, update);
  }

  /// Shows the interactive update dialog.
  void showUpdateDialog(BuildContext context, AppUpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AppUpdateDialog(update: update),
    );
  }
}

class _AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;
  const _AppUpdateDialog({required this.update});

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _error;

  Future<void> _startUpdate() async {
    final url = widget.update.downloadUrl;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No APK attached to release. Please visit GitHub to download.');
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0.0;
      _statusText = 'Starting download...';
    });

    final success = await AppUpdateService.instance.downloadAndInstall(
      downloadUrl: url,
      onProgress: (p, status) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _statusText = status;
        });
      },
    );

    if (!success && mounted) {
      setState(() {
        _downloading = false;
        _error = _statusText.contains('error') ? _statusText : 'Could not launch package installer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.update.currentVersion;
    final latest = widget.update.latestVersion;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.white,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded, color: AppColors.navy, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current: v$current', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.navy),
                  Text('Latest: v$latest', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'What\'s New:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textLight),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.update.releaseNotes.isEmpty ? 'Performance improvements and bug fixes.' : widget.update.releaseNotes,
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.primary),
                ),
              ),
            ),
            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: AppColors.containerBg,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.navy),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.accentRed, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _downloading ? null : _startUpdate,
          child: Text(
            _downloading ? 'Downloading...' : 'Update Now',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
