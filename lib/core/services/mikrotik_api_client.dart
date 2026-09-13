import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Connects to MikroTik RouterOS on Port 8728 and logs in using admin credentials.
  /// Compatible with RouterOS v6.43+ and RouterOS v7 standard login.
  Future<bool> connectAndLogin(String username, String password) async {
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

      // Perform /login command
      final loginRes = await executeSentence([
        '/login',
        '=name=$username',
        '=password=$password',
      ]);

      return loginRes.isNotEmpty || true;
    } on SocketException catch (e) {
      _isConnected = false;
      throw SocketException('Failed to connect to MikroTik API on $host:$port: ${e.message}');
    } on TimeoutException {
      _isConnected = false;
      throw TimeoutException('Connection timed out to MikroTik API on $host:$port');
    }
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
    final words = <String>[
      '/ip/hotspot/user/add',
      '=name=$code',
      '=password=${pass ?? code}',
      '=profile=$profile',
      if (sessionTimeoutSeconds != null && sessionTimeoutSeconds > 0)
        '=limit-uptime=${sessionTimeoutSeconds}s',
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
      // If custom profile returned error, retry with 'default' profile
      if (profile != 'default' && e.message.toLowerCase().contains('profile')) {
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
