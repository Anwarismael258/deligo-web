import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServerClockService {
  ServerClockService._internal();

  static final ServerClockService instance = ServerClockService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Duration _serverOffset = Duration.zero;
  DateTime? _lastSyncAtUtc;
  Future<void>? _pendingSync;

  DateTime now() => DateTime.now().toUtc().add(_serverOffset);

  DateTime nowInMozambique() => now().toUtc().add(const Duration(hours: 2));

  String nowIso8601Utc() => now().toIso8601String();

  Future<void> sync({
    bool force = false,
    Duration maxAge = const Duration(minutes: 1),
  }) {
    final lastSyncAtUtc = _lastSyncAtUtc;
    if (!force &&
        lastSyncAtUtc != null &&
        DateTime.now().toUtc().difference(lastSyncAtUtc) < maxAge) {
      return Future.value();
    }

    final pending = _pendingSync;
    if (pending != null) return pending;

    final future = _syncInternal();
    _pendingSync = future;
    return future.whenComplete(() {
      if (identical(_pendingSync, future)) {
        _pendingSync = null;
      }
    });
  }

  Future<void> _syncInternal() async {
    try {
      final sentAtUtc = DateTime.now().toUtc();
      final response = await _supabase.rpc('get_server_time');
      final receivedAtUtc = DateTime.now().toUtc();

      final serverTimeUtc = _parseServerTime(response);
      if (serverTimeUtc == null) return;

      final roundTrip = receivedAtUtc.difference(sentAtUtc);
      final midpointUtc = sentAtUtc.add(
        Duration(microseconds: roundTrip.inMicroseconds ~/ 2),
      );

      _serverOffset = serverTimeUtc.difference(midpointUtc);
      _lastSyncAtUtc = receivedAtUtc;
    } catch (error) {
      debugPrint('ServerClockService: falha ao sincronizar hora: $error');
    }
  }

  DateTime? _parseServerTime(dynamic response) {
    DateTime? parseServerUtcString(String raw) {
      final normalized = raw.trim();
      if (normalized.isEmpty) return null;
      final hasTimezone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(normalized);
      final candidate = hasTimezone ? normalized : '${normalized}Z';
      return DateTime.tryParse(candidate)?.toUtc();
    }

    if (response is Map) {
      final raw = response['server_time_utc']?.toString();
      if (raw != null && raw.isNotEmpty) {
        return parseServerUtcString(raw);
      }
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      final first = Map<String, dynamic>.from(response.first as Map);
      final raw = first['server_time_utc']?.toString();
      if (raw != null && raw.isNotEmpty) {
        return parseServerUtcString(raw);
      }
    }

    if (response is String && response.isNotEmpty) {
      return parseServerUtcString(response);
    }

    return null;
  }
}
