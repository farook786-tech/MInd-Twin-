import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend_api_service.dart';

/// Where a brief statement came from (`users`, `daily_logs`, ...).
class BriefSource {
  final String collection;
  final String? docId;
  final String? field;
  final DateTime? at;

  const BriefSource({required this.collection, this.docId, this.field, this.at});

  factory BriefSource.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final at = m['at'];
    return BriefSource(
      collection: m['collection'] is String ? m['collection'] as String : 'unknown',
      docId: m['docId'] is String ? m['docId'] as String : null,
      field: m['field'] is String ? m['field'] as String : null,
      at: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }

  /// Human-readable type of record, e.g. "Assessment".
  String get typeLabel {
    switch (collection) {
      case 'clinical_assessments':
        return 'Assessment';
      case 'daily_logs':
        return 'Daily check-in';
      case 'crisis_events':
        return 'Alert';
      case 'vitals_daily':
        return 'Daily vitals summary';
      case 'vitals':
        return 'Wearable reading';
      case 'journal_entries':
        return 'Journal entry';
      case 'appointments':
        return 'Appointment';
      case 'users':
        return 'Patient profile';
    }
    return collection;
  }
}

class BriefItem {
  final String text;
  final BriefSource source;

  const BriefItem({required this.text, required this.source});

  factory BriefItem.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return BriefItem(
      text: m['text'] is String ? m['text'] as String : '',
      source: BriefSource.fromJson(m['source']),
    );
  }
}

class BriefSection {
  final String title;
  final List<BriefItem> items;

  const BriefSection({required this.title, required this.items});
}

/// Response of `POST /api/brief/:patientId` (backend/src/routes/sessionBrief.js).
class SessionBrief {
  final DateTime? generatedAt;
  final DateTime? from;
  final DateTime? to;
  final String basis;
  final List<BriefSection> sections;
  final List<BriefItem> flags;
  final List<String> dataGaps;

  /// AI narrative (patient consented, de-identified input) or null.
  final String? narrative;
  final String? narrativeReason;

  const SessionBrief({
    required this.generatedAt,
    required this.from,
    required this.to,
    required this.basis,
    required this.sections,
    required this.flags,
    required this.dataGaps,
    required this.narrative,
    required this.narrativeReason,
  });

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static List<BriefItem> _items(Object? v) =>
      v is List ? v.map(BriefItem.fromJson).where((i) => i.text.isNotEmpty).toList() : const [];

  factory SessionBrief.fromJson(Map<String, dynamic> json) {
    final brief = json['brief'] is Map ? json['brief'] as Map : const {};
    final period = brief['period'] is Map ? brief['period'] as Map : const {};
    final rawSections = brief['sections'] is List ? brief['sections'] as List : const [];
    final narrative = json['narrative'];
    return SessionBrief(
      generatedAt: _date(brief['generatedAt']),
      from: _date(period['from']),
      to: _date(period['to']),
      basis: period['basis'] is String ? period['basis'] as String : '',
      sections: rawSections
          .whereType<Map>()
          .map((s) => BriefSection(
                title: s['title'] is String ? s['title'] as String : '',
                items: _items(s['items']),
              ))
          .toList(),
      flags: _items(brief['flags']),
      dataGaps: brief['dataGaps'] is List
          ? (brief['dataGaps'] as List).whereType<String>().toList()
          : const [],
      narrative: narrative is String && narrative.trim().isNotEmpty ? narrative.trim() : null,
      narrativeReason: json['narrativeReason'] is String ? json['narrativeReason'] as String : null,
    );
  }

  /// Plain-text version for the clipboard (no ids).
  String toPlainText({String? periodLabel}) {
    final b = StringBuffer('Pre-session brief');
    if (periodLabel != null) b.write(' ($periodLabel)');
    b.writeln();
    if (flags.isNotEmpty) {
      b.writeln('\nFlags');
      for (final f in flags) {
        b.writeln('- ${f.text}');
      }
    }
    for (final s in sections) {
      if (s.items.isEmpty) continue;
      b.writeln('\n${s.title}');
      for (final i in s.items) {
        b.writeln('- ${i.text}');
      }
    }
    if (dataGaps.isNotEmpty) {
      b.writeln('\nData gaps');
      for (final g in dataGaps) {
        b.writeln('- $g');
      }
    }
    if (narrative != null) {
      b.writeln('\nAI narrative (consented, de-identified; may contain errors)');
      b.writeln(narrative);
    }
    b.writeln('\nDecision support only. Not a diagnosis or prescription.');
    return b.toString();
  }
}

class SessionBriefResult {
  final SessionBrief? brief;
  final String? error;

  const SessionBriefResult.ok(SessionBrief this.brief) : error = null;
  const SessionBriefResult.fail(String this.error) : brief = null;
}

/// Calls the MindTwin server like RoleService does: resolved base URL,
/// Firebase ID token as Bearer, timeouts, readable offline messages.
class SessionBriefService {
  SessionBriefService({BackendApiService? backend}) : _backendOverride = backend;

  final BackendApiService? _backendOverride;
  BackendApiService? _backendLazy;
  BackendApiService get _backend => _backendOverride ?? (_backendLazy ??= BackendApiService());

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _coldStartTimeout = Duration(seconds: 75);
  static const String _buildTimeBaseUrl =
      String.fromEnvironment('MINDTWIN_API_BASE_URL', defaultValue: '');

  static const String offlineMessage =
      'MindTwin server is not reachable — check your connection and that the clinic server is running.';

  Future<SessionBriefResult> fetch(String patientId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SessionBriefResult.fail('Please sign in again.');

    String? base;
    var coldStart = false;
    try {
      base = await _backend.resolveBaseUrl();
    } catch (e) {
      debugPrint('[SessionBrief] server discovery failed: $e');
    }
    if (base == null || base.isEmpty) {
      final built = _buildTimeBaseUrl.trim();
      if (built.startsWith('https://')) {
        base = built.endsWith('/') ? built.substring(0, built.length - 1) : built;
        coldStart = true;
      }
    }
    if (base == null || base.isEmpty) return const SessionBriefResult.fail(offlineMessage);

    var outcome = await _post(user, base, patientId, forceRefresh: false, coldStart: coldStart);
    if (outcome.$1 == 401) {
      outcome = await _post(user, base, patientId, forceRefresh: true, coldStart: coldStart);
    }
    final (status, body, connectionError) = outcome;
    if (connectionError != null) return SessionBriefResult.fail(connectionError);
    if (status == 200 && body is Map<String, dynamic> && body['brief'] is Map) {
      return SessionBriefResult.ok(SessionBrief.fromJson(body));
    }
    final err = body is Map ? body['error'] : null;
    final code = err is Map ? err['code'] : null;
    final message = err is Map && err['message'] is String ? err['message'] as String : null;
    switch (code) {
      case 'permission-denied':
        return const SessionBriefResult.fail('This patient is not assigned to you.');
      case 'unauthenticated':
        return const SessionBriefResult.fail('Your session expired. Please sign in again.');
      case 'resource-exhausted':
        return const SessionBriefResult.fail('Too many brief requests. Please wait a few minutes.');
    }
    if (status == 404) {
      return const SessionBriefResult.fail(
          'The MindTwin server at the clinic needs to be updated to create briefs.');
    }
    return SessionBriefResult.fail(message ?? 'Could not create the brief. Please try again.');
  }

  /// Returns (status, decoded body, connection error message).
  Future<(int, Object?, String?)> _post(
    User user,
    String base,
    String patientId, {
    required bool forceRefresh,
    required bool coldStart,
  }) async {
    String? token;
    try {
      token = await user.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') return (0, null, offlineMessage);
      return (401, null, null);
    } catch (_) {
      return (0, null, offlineMessage);
    }
    if (token == null || token.isEmpty) return (401, null, null);

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$base/api/brief/${Uri.encodeComponent(patientId)}'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes}),
          )
          .timeout(coldStart ? _coldStartTimeout : _timeout);
    } on TimeoutException {
      return (0, null, 'The MindTwin server did not respond in time. Please try again.');
    } on SocketException {
      return (0, null, offlineMessage);
    } on http.ClientException {
      return (0, null, offlineMessage);
    }
    Object? body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    return (res.statusCode, body, null);
  }
}
