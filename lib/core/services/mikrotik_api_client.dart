import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'router_discovery_service.dart';

/// Exception thrown when MikroTik RouterOS API authentication fails.
class MikrotikAuthException implements Exception {
  final String message;
  MikrotikAuthException(this.message);
  @override
  String toString() => 'MikrotikAuthException: $message';
}

/// Exception thrown when a MikroTik RouterOS API command returns !trap error.
class MikrotikCommandException implements Exception {
  final String message;
  final String? category;
  MikrotikCommandException(this.message, {this.category});
  @override
  String toString() => 'MikrotikCommandException: $message${category != null ? ' ($category)' : ''}';
}

/// Represents a single sentence response from RouterOS API (!re, !done, !trap, !fatal).
class MikrotikSentence {
  final String type;
  final Map<String, String> attributes;

  MikrotikSentence(this.type, this.attributes);

  @override
  String toString() => '$type $attributes';
}

/// Native client for MikroTik RouterOS API (Port 8728).
/// Provides binary length-prefixed protocol communication over TCP socket.
/// This protocol is NOT intercepted by HotSpot captive portals (unlike HTTP Port 80).
class MikrotikApiClient {
  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  StreamSubscription<List<int>>? _socketSub;
  final List<int> _buffer = [];
  final List<String> _currentWords = [];
  final StreamController<MikrotikSentence> _sentenceStream = StreamController<MikrotikSentence>.broadcast();
  bool _isConnected = false;

  MikrotikApiClient({
    required this.host,
    this.port = 8728,
    this.timeout = const Duration(seconds: 6),
  });

  bool get isConnected => _isConnected && _socket != null;

  /// Connects to MikroTik RouterOS TCP socket on Port 8728.
  Future<bool> connect() async {
    if (isConnected) return true;
    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _isConnected = true;

      _socketSub = _socket!.listen(
        _onData,
        onError: (err) {
          _isConnected = false;
          if (!_sentenceStream.isClosed) {
            _sentenceStream.addError(err);
          }
        },
        onDone: () {
          _isConnected = false;
        },
        cancelOnError: false,
      );
      return true;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  /// Logs in using admin credentials over the established socket connection.
  Future<bool> login(String username, String password) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) return false;
    }
    final loginRes = await executeSentence([
      '/login',
      '=name=$username',
      '=password=$password',
    ]);
    return loginRes.isNotEmpty || true;
  }

  Future<void> disconnect() => close();

  /// Connects to MikroTik RouterOS on Port 8728 and logs in using admin credentials.
  /// Compatible with RouterOS v6.43+ and RouterOS v7 standard login.
  Future<bool> connectAndLogin(String username, String password) async {
    final ok = await connect();
    if (!ok) return false;
    return login(username, password);
  }

  /// Sends a sentence to RouterOS and awaits all response sentences until !done or !trap.
  Future<List<Map<String, String>>> executeSentence(List<String> words) async {
    if (!isConnected || _socket == null) {
      throw StateError('MikrotikApiClient is not connected');
    }

    final completer = Completer<List<Map<String, String>>>();
    final results = <Map<String, String>>[];
    String? trapMessage;
    String? trapCategory;

    late StreamSubscription<MikrotikSentence> sub;
    sub = _sentenceStream.stream.listen(
      (sentence) {
        if (sentence.type == '!re') {
          results.add(Map<String, String>.from(sentence.attributes));
        } else if (sentence.type == '!trap') {
          trapMessage = sentence.attributes['message'] ?? 'Unknown RouterOS error';
          trapCategory = sentence.attributes['category'];
        } else if (sentence.type == '!done') {
          if (sentence.attributes.isNotEmpty) {
            results.add(Map<String, String>.from(sentence.attributes));
          }
          if (trapMessage != null) {
            sub.cancel();
            if (trapMessage!.toLowerCase().contains('cannot log in') ||
                trapMessage!.toLowerCase().contains('invalid user') ||
                trapMessage!.toLowerCase().contains('password')) {
              completer.completeError(MikrotikAuthException(trapMessage!));
            } else {
              completer.completeError(MikrotikCommandException(trapMessage!, category: trapCategory));
            }
          } else {
            sub.cancel();
            completer.complete(results);
          }
        } else if (sentence.type == '!fatal') {
          sub.cancel();
          _isConnected = false;
          completer.completeError(MikrotikCommandException(sentence.attributes['message'] ?? 'Connection closed by router'));
        }
      },
      onError: (err) {
        sub.cancel();
        if (!completer.isCompleted) completer.completeError(err);
      },
    );

    try {
      _writeSentence(words);
      return await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Queries system resource attributes (/system/resource/print).
  Future<Map<String, String>> getSystemResource() async {
    final res = await executeSentence(['/system/resource/print']);
    if (res.isNotEmpty) {
      return res.first;
    }
    return {};
  }

  /// Queries system identity (/system/identity/print).
  Future<String?> getSystemIdentity() async {
    try {
      final res = await executeSentence(['/system/identity/print']);
      if (res.isNotEmpty && res.first.containsKey('name')) {
        return res.first['name'];
      }
    } catch (_) {}
    return null;
  }

  /// Adds a HotSpot user directly onto the router hardware via RouterOS API (/ip/hotspot/user/add).
  Future<bool> createHotspotUser({
    required String code,
    String? pass,
    String profile = 'default',
    int? sessionTimeoutSeconds,
    int? limitBytesTotal,
    int? sharedUsers,
    String comment = 'wavepass-provisioned',
  }) async {
    final uptimeStr = sessionTimeoutSeconds != null && sessionTimeoutSeconds > 0
        ? RouterDiscoveryService.formatRouterOsDuration(sessionTimeoutSeconds)
        : null;

    final words = <String>[
      '/ip/hotspot/user/add',
      '=name=$code',
      '=password=${pass ?? code}',
      '=profile=$profile',
      if (uptimeStr != null)
        '=limit-uptime=$uptimeStr',
      if (limitBytesTotal != null && limitBytesTotal > 0)
        '=limit-bytes-total=$limitBytesTotal',
      if (sharedUsers != null && sharedUsers > 0)
        '=shared-users=$sharedUsers',
      '=comment=$comment',
    ];

    try {
      await executeSentence(words);
      return true;
    } on MikrotikCommandException catch (e) {
      final msg = e.message.toLowerCase();
      // If user already exists, update credentials and limits gracefully & reset uptime
      if (msg.contains('already have') || msg.contains('duplicate')) {
        try {
          final existing = await executeSentence([
            '/ip/hotspot/user/print',
            '?name=$code',
          ]);
          if (existing.isNotEmpty) {
            final id = existing.first['.id'];
            if (id != null) {
              await executeSentence([
                '/ip/hotspot/user/set',
                '=.id=$id',
                '=password=${pass ?? code}',
                '=profile=$profile',
                if (uptimeStr != null)
                  '=limit-uptime=$uptimeStr',
                '=uptime=0s', // Reset spent uptime for re-provisioned pass
                if (limitBytesTotal != null && limitBytesTotal > 0)
                  '=limit-bytes-total=$limitBytesTotal',
                if (sharedUsers != null && sharedUsers > 0)
                  '=shared-users=$sharedUsers',
                '=comment=$comment',
              ]);
              return true;
            }
          }
        } catch (_) {}
      }

      // If custom profile returned error, retry with 'default' profile
      if (profile != 'default' && msg.contains('profile')) {
        words[3] = '=profile=default';
        try {
          await executeSentence(words);
          return true;
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns all currently logged-in active HotSpot users on the router.
  Future<List<Map<String, String>>> getHotspotActiveUsers() async {
    try {
      final sentences = await executeSentence(['/ip/hotspot/active/print']);
      return sentences;
    } catch (_) {
      return [];
    }
  }

  /// Returns all hotspot user accounts provisioned on the router.
  Future<List<Map<String, String>>> getHotspotUsers() async {
    try {
      final sentences = await executeSentence(['/ip/hotspot/user/print']);
      return sentences;
    } catch (_) {
      return [];
    }
  }

  /// Removes a hotspot user account (voucher) from RouterOS.
  Future<bool> removeHotspotUser(String username) async {
    try {
      final existing = await executeSentence([
        '/ip/hotspot/user/print',
        '?name=$username',
      ]);
      for (final u in existing) {
        final id = u['.id'];
        if (id != null) {
          await executeSentence([
            '/ip/hotspot/user/remove',
            '=.id=$id',
          ]);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnects an active hotspot session on RouterOS.
  Future<bool> disconnectActiveUser(String username) async {
    try {
      final active = await executeSentence([
        '/ip/hotspot/active/print',
        '?user=$username',
      ]);
      for (final a in active) {
        final id = a['.id'];
        if (id != null) {
          await executeSentence([
            '/ip/hotspot/active/remove',
            '=.id=$id',
          ]);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Configures HotSpot profile, captive portal DNS, walled garden, and user profiles
  /// directly over RouterOS API on Port 8728 (Mikhmon / Micro Voucher parity).
  Future<Map<String, dynamic>> installHotspotConfig({
    required String slug,
    required String venueName,
    String? localIp,
  }) async {
    final results = <String, dynamic>{
      'identity': false,
      'profile': false,
      'walledGarden': false,
      'hotspot': false,
      'userProfiles': false,
      'cleanupScheduler': false,
      'antiTethering': false,
      'errors': <String>[],
    };

    // 1. System Identity: WavePass-$slug
    try {
      await executeSentence([
        '/system/identity/set',
        '=name=WavePass-$slug',
      ]);
      results['identity'] = true;
    } catch (e) {
      (results['errors'] as List<String>).add('Identity: $e');
    }

    // 2. Hotspot Profile: wavepass-profile (local DNS hostname to prevent SSL warnings and allow cloud portal access)
    try {
      await executeSentence([
        '/ip/hotspot/profile/add',
        '=name=wavepass-profile',
        '=dns-name=wavepass.local',
        '=html-directory=hotspot',
        '=login-by=http-pap,http-chap,mac-cookie,trial',
        '=trial-user-profile=wp-payment-trial',
        '=trial-uptime-limit=2m',
        '=trial-uptime-reset=24h',
        '=addresses-per-mac=1',
        '=mac-cookie=no',
        if (localIp != null && localIp.isNotEmpty)
          '=hotspot-address=$localIp',
      ]);
      results['profile'] = true;
    } catch (e) {
      // Profile might already exist; update it with dns-name
      try {
        final existing = await executeSentence([
          '/ip/hotspot/profile/print',
          '?name=wavepass-profile',
        ]);
        if (existing.isNotEmpty) {
          final id = existing.first['.id'];
          if (id != null) {
            await executeSentence([
              '/ip/hotspot/profile/set',
              '=.id=$id',
              '=dns-name=wavepass.local',
              '=html-directory=hotspot',
              '=login-by=http-pap,http-chap,mac-cookie,trial',
              '=trial-user-profile=wp-payment-trial',
              '=trial-uptime-limit=2m',
              '=trial-uptime-reset=24h',
              '=addresses-per-mac=1',
              '=mac-cookie=no',
            ]);
            results['profile'] = true;
          }
        }
      } catch (_) {
        (results['errors'] as List<String>).add('Profile: $e');
      }
    }

    // 3. Walled Garden Domains (Captive Portal & Payment Checkout: HTTP & IP/HTTPS)
    final domains = [
      'nexawavepass.com',
      '*.nexawavepass.com',
      'api.nexawavepass.com',
      '*.paystack.co',
      'api.paystack.co',
      'checkout.paystack.com',
      'standard.paystack.co',
      '*.supabase.co',
    ];
    int wgSuccess = 0;
    for (final domain in domains) {
      try {
        await executeSentence([
          '/ip/hotspot/walled-garden/add',
          '=dst-host=$domain',
          '=comment=WavePass Walled Garden',
        ]);
        wgSuccess++;
      } catch (_) {}
      try {
        await executeSentence([
          '/ip/hotspot/walled-garden/ip/add',
          '=dst-host=$domain',
          '=action=accept',
          '=comment=WavePass Walled Garden IP',
        ]);
      } catch (_) {}
    }
    results['walledGarden'] = wgSuccess > 0;

    // 4. HotSpot Server on wlan1 or default interface
    try {
      await executeSentence([
        '/ip/hotspot/add',
        '=name=wavepass-hotspot',
        '=interface=wlan1',
        '=profile=wavepass-profile',
        '=disabled=no',
      ]);
      results['hotspot'] = true;
    } catch (e) {
      // Might already exist or wlan1 is bridged (common in MikroTik)
      try {
        final existing = await executeSentence([
          '/ip/hotspot/print',
        ]);
        if (existing.isNotEmpty) {
          results['hotspot'] = true; // HotSpot is already installed and active
        }
      } catch (_) {
        (results['errors'] as List<String>).add('HotSpot: $e');
      }
    }

    // 5. Standard Duration User Profiles (with hard session-timeout & keepalives)
    int tierSuccess = 0;
    for (final tier in RouterDiscoveryService.standardDurationProfiles) {
      try {
        await executeSentence([
          '/ip/hotspot/user/profile/add',
          '=name=${tier['name']}',
          '=rate-limit=${tier['rate-limit']}',
          '=shared-users=${tier['shared-users']}',
          '=session-timeout=${tier['session-timeout']}',
          '=keepalive-timeout=${tier['keepalive-timeout']}',
          '=idle-timeout=${tier['idle-timeout']}',
          '=status-autorefresh=${tier['status-autorefresh']}',
          '=comment=${tier['comment']}',
        ]);
        tierSuccess++;
      } catch (e) {
        // Fallback: If profile already exists, update it to ensure correct rate-limits and timeouts
        try {
          final existing = await executeSentence([
            '/ip/hotspot/user/profile/print',
            '?name=${tier['name']}',
          ]);
          if (existing.isNotEmpty) {
            final id = existing.first['.id'];
            if (id != null) {
              await executeSentence([
                '/ip/hotspot/user/profile/set',
                '=.id=$id',
                '=rate-limit=${tier['rate-limit']}',
                '=shared-users=${tier['shared-users']}',
                '=session-timeout=${tier['session-timeout']}',
                '=keepalive-timeout=${tier['keepalive-timeout']}',
                '=idle-timeout=${tier['idle-timeout']}',
                '=status-autorefresh=${tier['status-autorefresh']}',
              ]);
              tierSuccess++;
            }
          }
        } catch (_) {}
      }
    }
    // Enforce shared-users=1, keepalives, and idle timeout on 'default' user profile as well
    try {
      final defProfiles = await executeSentence([
        '/ip/hotspot/user/profile/print',
        '?name=default',
      ]);
      if (defProfiles.isNotEmpty) {
        final defId = defProfiles.first['.id'];
        if (defId != null) {
          await executeSentence([
            '/ip/hotspot/user/profile/set',
            '=.id=$defId',
            '=shared-users=1',
            '=keepalive-timeout=2m',
            '=idle-timeout=5m',
            '=status-autorefresh=1m',
          ]);
        }
      }
    } catch (_) {}
    results['userProfiles'] = tierSuccess > 0;

    // 6. User limit enforcer & auto-cleanup script & scheduler (1m interval)
    const cleanupSource = ':foreach a in=[/ip hotspot active find] do={ :local stl [/ip hotspot active get \$a session-time-left]; :if ([:len \$stl] > 0 && \$stl = 0s) do={ /ip hotspot active remove \$a; } }; :foreach u in=[/ip hotspot user find] do={ :local lup [/ip hotspot user get \$u limit-uptime]; :local upt [/ip hotspot user get \$u uptime]; :if ([:len \$lup] > 0 && \$lup != 0s && \$upt >= \$lup) do={ :local un [/ip hotspot user get \$u name]; /ip hotspot active remove [find user=\$un]; /ip hotspot user remove \$u; } }; /ip hotspot user remove [find comment~"expired"]';

    try {
      await executeSentence([
        '/system/script/add',
        '=name=wavepass-cleanup',
        '=source=$cleanupSource',
        '=comment=WavePass user limit enforcer',
      ]);
      results['cleanupScheduler'] = true;
    } catch (_) {
      // If already exists, update source
      try {
        final existingScript = await executeSentence([
          '/system/script/print',
          '?name=wavepass-cleanup',
        ]);
        if (existingScript.isNotEmpty) {
          final sId = existingScript.first['.id'];
          if (sId != null) {
            await executeSentence([
              '/system/script/set',
              '=.id=$sId',
              '=source=$cleanupSource',
            ]);
          }
        }
      } catch (_) {}
      results['cleanupScheduler'] = true;
    }

    try {
      await executeSentence([
        '/system/scheduler/add',
        '=name=wavepass-cleanup',
        '=interval=1m',
        '=on-event=wavepass-cleanup',
        '=comment=WavePass 1-minute user limit enforcer',
      ]);
    } catch (_) {
      // If scheduler already exists, ensure interval is 1m
      try {
        final existingSched = await executeSentence([
          '/system/scheduler/print',
          '?name=wavepass-cleanup',
        ]);
        if (existingSched.isNotEmpty) {
          final scId = existingSched.first['.id'];
          if (scId != null) {
            await executeSentence([
              '/system/scheduler/set',
              '=.id=$scId',
              '=interval=1m',
              '=on-event=wavepass-cleanup',
            ]);
          }
        }
      } catch (_) {}
    }

    // 7. Clean up any legacy postrouting TTL mangle rule that breaks WAN routing
    // (Single-device enforcement is safely and accurately handled via shared-users=1 on profiles)
    try {
      final existingMangle = await executeSentence([
        '/ip/firewall/mangle/print',
        '?comment=WavePass Anti-Tethering',
      ]);
      for (final m in existingMangle) {
        final id = m['.id'];
        if (id != null) {
          await executeSentence([
            '/ip/firewall/mangle/remove',
            '=.id=$id',
          ]);
        }
      }
      results['antiTethering'] = true;
    } catch (_) {}

    // 8. Enforce No Sharing (Client Isolation, 1 Device/Voucher, Safe Anti-Tethering filter)
    try {
      final noShareRes = await enforceNoHotspotSharing();
      results['noSharingEnforced'] = noShareRes['success'] == true;
    } catch (_) {}

    final anySuccess = results['identity'] == true ||
        results['profile'] == true ||
        results['walledGarden'] == true ||
        results['hotspot'] == true;
    results['success'] = anySuccess;

    return results;
  }

  /// Enforces no sharing of hotspot on MikroTik RouterOS:
  /// 1. shared-users=1 on all hotspot user profiles (1 device per voucher)
  /// 2. addresses-per-mac=1 and mac-cookie=no on hotspot server profiles
  /// 3. default-forwarding=no on wireless interfaces (Wi-Fi client isolation)
  /// 4. horizon=1 on bridge ports (bridge client isolation)
  /// 5. drops tethered packets (TTL=63 and TTL=127) in forward chain without affecting WAN
  Future<Map<String, dynamic>> enforceNoHotspotSharing() async {
    final results = <String, dynamic>{
      'profiles': false,
      'serverProfiles': false,
      'isolation': false,
      'firewallFilter': false,
      'success': false,
    };

    try {
      // 1. Hotspot User Profiles: shared-users=1 and ensure wp-payment-trial exists
      try {
        final profiles = await executeSentence(['/ip/hotspot/user/profile/print']);
        for (final p in profiles) {
          final id = p['.id'];
          if (id != null) {
            await executeSentence([
              '/ip/hotspot/user/profile/set',
              '=.id=$id',
              '=shared-users=1',
            ]);
          }
        }
        final trialExists = profiles.any((p) => p['name'] == 'wp-payment-trial');
        if (!trialExists) {
          try {
            await executeSentence([
              '/ip/hotspot/user/profile/add',
              '=name=wp-payment-trial',
              '=rate-limit=2M/2M',
              '=shared-users=1',
              '=session-timeout=2m',
              '=keepalive-timeout=2m',
              '=idle-timeout=1m',
              '=status-autorefresh=1m',
              '=transparent-proxy=yes',
              '=comment=WavePass 2-Minute Payment Trial',
            ]);
          } catch (_) {}
        }
        results['profiles'] = true;
      } catch (e) {
        debugPrint('[MikrotikApiClient] enforceNoSharing profiles error: $e');
      }

      // 2. Hotspot Server Profiles: addresses-per-mac=1, mac-cookie=no, login-by, trial
      try {
        final srvProfiles = await executeSentence(['/ip/hotspot/profile/print']);
        for (final sp in srvProfiles) {
          final id = sp['.id'];
          if (id != null) {
            await executeSentence([
              '/ip/hotspot/profile/set',
              '=.id=$id',
              '=addresses-per-mac=1',
              '=mac-cookie=no',
              '=login-by=http-pap,http-chap,mac-cookie,trial',
              '=trial-user-profile=wp-payment-trial',
              '=trial-uptime-limit=2m',
              '=trial-uptime-reset=24h',
            ]);
          }
        }
        results['serverProfiles'] = true;
      } catch (e) {
        debugPrint('[MikrotikApiClient] enforceNoSharing server profiles error: $e');
      }

      // 3. Wireless client isolation (default-forwarding=no)
      try {
        final wlanList = await executeSentence(['/interface/wireless/print']);
        for (final w in wlanList) {
          final id = w['.id'];
          if (id != null) {
            await executeSentence([
              '/interface/wireless/set',
              '=.id=$id',
              '=default-forwarding=no',
            ]);
          }
        }
        results['isolation'] = true;
      } catch (_) {}

      // Bridge port isolation (horizon=1)
      try {
        final ports = await executeSentence(['/interface/bridge/port/print']);
        for (final bp in ports) {
          final id = bp['.id'];
          if (id != null) {
            await executeSentence([
              '/interface/bridge/port/set',
              '=.id=$id',
              '=horizon=1',
            ]);
          }
        }
      } catch (_) {}

      // 4. Mangle Postrouting: Change TTL to 1 for all outbound client traffic (excluding WAN ether1)
      // This is the universal, industry-standard anti-tethering technique.
      // CRITICAL: out-interface=!ether1 prevents altering TTL on outgoing WAN traffic to the ISP.
      // When a client (iOS, Windows, Android, Linux) receives a packet with TTL=1,
      // the device itself functions 100% normally. But if it attempts to tether/share,
      // the OS decrements TTL to 0 (1 - 1 = 0) and drops the packet.
      try {
        final existingMangle = await executeSentence([
          '/ip/firewall/mangle/print',
          '?comment~WavePass Anti-Tethering',
        ]);
        for (final m in existingMangle) {
          final id = m['.id'];
          if (id != null) {
            try {
              await executeSentence(['/ip/firewall/mangle/remove', '=.id=$id']);
            } catch (_) {}
          }
        }
        await executeSentence([
          '/ip/firewall/mangle/add',
          '=chain=postrouting',
          '=out-interface=!ether1',
          '=action=change-ttl',
          '=new-ttl=set:1',
          '=passthrough=yes',
          '=comment=WavePass Anti-Tethering: set TTL=1 (blocks iOS, Windows, Android, Linux sharing)',
        ]);
        results['mangleTtl'] = true;
      } catch (e) {
        debugPrint('[MikrotikApiClient] enforceNoSharing mangle change-ttl error: $e');
      }

      // 5. Firewall Filter Drop tethered packets (TTL 63, 62, 127, 126) on ALL interfaces
      // Removed in-interface restriction so bridged interfaces, Ethernet, and all Wi-Fi bands are covered.
      try {
        final ttlsToDrop = [
          {'ttl': 'equal:63', 'comment': 'WavePass Anti-Tethering: drop secondary 64-ttl hop 1 (Android/iOS/Linux)'},
          {'ttl': 'equal:62', 'comment': 'WavePass Anti-Tethering: drop secondary 64-ttl hop 2 (Android/iOS/Linux)'},
          {'ttl': 'equal:127', 'comment': 'WavePass Anti-Tethering: drop secondary 128-ttl hop 1 (Windows)'},
          {'ttl': 'equal:126', 'comment': 'WavePass Anti-Tethering: drop secondary 128-ttl hop 2 (Windows)'},
        ];

        for (final rule in ttlsToDrop) {
          final existing = await executeSentence([
            '/ip/firewall/filter/print',
            '?comment=${rule['comment']}',
          ]);
          if (existing.isEmpty) {
            await executeSentence([
              '/ip/firewall/filter/add',
              '=chain=forward',
              '=action=drop',
              '=ttl=${rule['ttl']}',
              '=comment=${rule['comment']}',
            ]);
          }
        }
        results['firewallFilter'] = true;
      } catch (e) {
        debugPrint('[MikrotikApiClient] enforceNoSharing firewall filter error: $e');
      }

      results['success'] = results['profiles'] == true ||
          results['serverProfiles'] == true ||
          results['isolation'] == true ||
          results['mangleTtl'] == true ||
          results['firewallFilter'] == true;
    } catch (e) {
      debugPrint('[MikrotikApiClient] enforceNoHotspotSharing failed: $e');
    }

    return results;
  }

  /// Reboots the MikroTik router hardware via RouterOS API.
  Future<bool> rebootRouter() async {
    try {
      await executeSentence(['/system/reboot']);
      return true;
    } catch (e) {
      // Reboots disconnect the socket immediately, which is normal behavior
      return true;
    }
  }

  /// Closes the socket connection and releases resources.
  Future<void> close() async {
    _isConnected = false;
    try {
      await _socketSub?.cancel();
      await _socket?.close();
      _socket?.destroy();
    } catch (_) {}
  }

  // --- Low-Level Protocol Encoding & Decoding ---

  void _writeSentence(List<String> words) {
    final out = <int>[];
    for (final word in words) {
      out.addAll(encodeWord(word));
    }
    out.add(0); // 0x00 marks end of sentence
    _socket!.add(out);
  }

  static List<int> encodeWord(String word) {
    final bytes = utf8.encode(word);
    final len = bytes.length;
    final out = <int>[];
    if (len < 0x80) {
      out.add(len);
    } else if (len < 0x4000) {
      out.add((len >> 8) | 0x80);
      out.add(len & 0xFF);
    } else if (len < 0x200000) {
      out.add((len >> 16) | 0xC0);
      out.add((len >> 8) & 0xFF);
      out.add(len & 0xFF);
    } else if (len < 0x10000000) {
      out.add((len >> 24) | 0xE0);
      out.add((len >> 16) & 0xFF);
      out.add((len >> 8) & 0xFF);
      out.add(len & 0xFF);
    } else {
      out.add(0xF0);
      out.add((len >> 24) & 0xFF);
      out.add((len >> 16) & 0xFF);
      out.add((len >> 8) & 0xFF);
      out.add(len & 0xFF);
    }
    out.addAll(bytes);
    return out;
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);

    while (_buffer.isNotEmpty) {
      final b0 = _buffer[0];

      // Empty word (0x00) -> Sentence boundary!
      if (b0 == 0) {
        _buffer.removeAt(0);
        if (_currentWords.isNotEmpty) {
          final sentence = _parseSentence(List<String>.from(_currentWords));
          _currentWords.clear();
          if (!_sentenceStream.isClosed) {
            _sentenceStream.add(sentence);
          }
        }
        continue;
      }

      // Word length decoding
      int len;
      int headerSize;

      if ((b0 & 0x80) == 0) {
        len = b0;
        headerSize = 1;
      } else if ((b0 & 0xC0) == 0x80) {
        if (_buffer.length < 2) return; // Need more bytes
        len = ((b0 & 0x3F) << 8) | _buffer[1];
        headerSize = 2;
      } else if ((b0 & 0xE0) == 0xC0) {
        if (_buffer.length < 3) return; // Need more bytes
        len = ((b0 & 0x1F) << 16) | (_buffer[1] << 8) | _buffer[2];
        headerSize = 3;
      } else if ((b0 & 0xF0) == 0xE0) {
        if (_buffer.length < 4) return; // Need more bytes
        len = ((b0 & 0x0F) << 24) | (_buffer[1] << 16) | (_buffer[2] << 8) | _buffer[3];
        headerSize = 4;
      } else if (b0 == 0xF0) {
        if (_buffer.length < 5) return; // Need more bytes
        len = (_buffer[1] << 24) | (_buffer[2] << 16) | (_buffer[3] << 8) | _buffer[4];
        headerSize = 5;
      } else {
        // Unknown length byte, discard
        _buffer.removeAt(0);
        continue;
      }

      if (_buffer.length < headerSize + len) {
        // Incomplete word, wait for next chunk
        return;
      }

      _buffer.removeRange(0, headerSize);
      final wordBytes = _buffer.sublist(0, len);
      _buffer.removeRange(0, len);

      final word = utf8.decode(wordBytes, allowMalformed: true);
      _currentWords.add(word);
    }
  }

  static MikrotikSentence _parseSentence(List<String> words) {
    if (words.isEmpty) return MikrotikSentence('!done', {});
    final type = words[0];
    final attributes = <String, String>{};

    for (int i = 1; i < words.length; i++) {
      var w = words[i];
      if (w.startsWith('=')) {
        w = w.substring(1);
        final eqIdx = w.indexOf('=');
        if (eqIdx != -1) {
          attributes[w.substring(0, eqIdx)] = w.substring(eqIdx + 1);
        } else {
          attributes[w] = '';
        }
      } else if (w.startsWith('.')) {
        // Control tag, e.g. .tag=1
        final eqIdx = w.indexOf('=');
        if (eqIdx != -1) {
          attributes[w.substring(0, eqIdx)] = w.substring(eqIdx + 1);
        }
      }
    }

    return MikrotikSentence(type, attributes);
  }
}
