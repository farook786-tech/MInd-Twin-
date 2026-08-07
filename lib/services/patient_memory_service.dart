import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'wearable_sync_service.dart';

/// Retrieves a patient's historical context from Firestore and formats it
/// into a bounded prompt block that grounds Ally's replies in real data:
/// profile, recent check-ins, clinical assessments, crisis history, and
/// live wearable vitals. Recent check-in text is ranked against the user's
/// current message so the most relevant past entries are surfaced.
class PatientMemoryService {
  static const int _maxContextChars = 4200;
  static const int _recentLogsCount = 7;
  static const int _retrievalPoolCount = 14;
  static const int _topRelevantCount = 3;

  static const Set<String> _stopwords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'been', 'but', 'by', 'can',
    'could', 'did', 'do', 'does', 'for', 'from', 'had', 'has', 'have', 'he',
    'her', 'his', 'how', 'i', 'if', 'in', 'is', 'it', 'its', 'just', 'me',
    'my', 'no', 'not', 'now', 'of', 'on', 'or', 'our', 'she', 'so', 'that',
    'the', 'their', 'them', 'there', 'they', 'this', 'to', 'too', 'up', 'us',
    'was', 'we', 'were', 'what', 'when', 'where', 'which', 'who', 'why', 'will',
    'with', 'you', 'your', 'feel', 'feeling', 'today', 'day', 'really', 'like',
    'about', 'think', 'get', 'got', 'im', 'ive', 'dont', 'cant', 'wont',
    'would', 'should', 'going', 'want',
  };

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('MMM d');

  /// Builds the full context block. Returns an empty string if no data exists.
  Future<String> buildContext({
    required String patientId,
    required String currentMessage,
  }) async {
    final results = await Future.wait([
      _loadProfile(patientId),
      _loadLogs(patientId),
      _loadAssessments(patientId),
      _loadCrisis(patientId),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final logs = results[1] as List<Map<String, dynamic>>;
    final assessments = results[2] as List<Map<String, dynamic>>;
    final crisis = results[3] as List<Map<String, dynamic>>;

    final sections = <String>[];

    if (profile != null) {
      sections.add('Profile: ${profile['text']}');
    }

    if (logs.isNotEmpty) {
      final recentLines = logs
          .take(_recentLogsCount)
          .map((d) => _compactLog(d))
          .join('\n- ');
      sections.add('Recent check-ins (newest first):\n- $recentLines');

      final trend = _buildTrend(logs);
      if (trend != null) sections.add(trend);

      final relevant = _rankRelevantLogs(logs, currentMessage);
      if (relevant.isNotEmpty) {
        sections.add('Most relevant past entries:\n- ${relevant.join('\n- ')}');
      }
    }

    if (assessments.isNotEmpty) {
      sections.add(
        'Recent clinical assessments:\n- '
        '${assessments.map((a) => a['line']).join('\n- ')}',
      );
    }

    if (crisis.isNotEmpty) {
      sections.add(
        'Past crisis signals (be extra supportive if relevant):\n- '
        '${crisis.map((c) => c['line']).join('\n- ')}',
      );
    }

    if (sections.isEmpty) return '';

    var joined = sections.join('\n\n');
    if (joined.length > _maxContextChars) {
      joined = '${joined.substring(0, _maxContextChars)}…';
    }

    return '\n\n[PATIENT CONTEXT retrieved from their records. '
        'Use it to personalize and empathize. Do not quote raw scores '
        'verbatim and never diagnose.]\n$joined';
  }

  Future<Map<String, dynamic>?> _loadProfile(String patientId) async {
    try {
      final doc = await _firestore.collection('users').doc(patientId).get();
      final d = doc.data();
      if (d == null) return null;

      final bits = <String>[];
      final name = d['name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        bits.add('name: $name');
      }
      final age = d['age'];
      if (age != null) bits.add('age $age');
      if (d['latestPhq9Score'] is num) {
        final s = (d['latestPhq9Score'] as num).toInt();
        bits.add('latest PHQ-9 $s/27 (${_phqLabel(s)})');
      }
      if (d['latestGad7Score'] is num) {
        final s = (d['latestGad7Score'] as num).toInt();
        bits.add('GAD-7 $s/21 (${_gadLabel(s)})');
      }
      if (d['latestRiskLevel'] != null) {
        bits.add('risk ${d['latestRiskLevel']}');
      }
      final vitals = WearableSyncService().lastReceivedVitals;
      if (vitals != null && vitals['bpm'] != null) {
        bits.add('live heart rate ${vitals['bpm']} bpm');
      }

      if (bits.isEmpty) return null;
      return {'text': '${bits.join(', ')}.'};
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadLogs(String patientId) async {
    try {
      final snap = await _firestore
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .orderBy('timestamp', descending: true)
          .limit(_retrievalPoolCount)
          .get();
      return snap.docs.map((e) => e.data()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadAssessments(String patientId) async {
    try {
      final snap = await _firestore
          .collection('clinical_assessments')
          .where('patientId', isEqualTo: patientId)
          .orderBy('timestamp', descending: true)
          .limit(2)
          .get();
      final lines = <Map<String, dynamic>>[];
      for (final e in snap.docs) {
        final d = e.data();
        final phq = d['phq9Score'];
        final gad = d['gad7Score'];
        final date = _fmtDate(_toDate(d['timestamp']));
        final line = '$date: PHQ-9 ${phq ?? 'n/a'}/27'
            '${phq is num ? ' (${_phqLabel(phq.toInt())})' : ''}, '
            'GAD-7 ${gad ?? 'n/a'}/21'
            '${gad is num ? ' (${_gadLabel(gad.toInt())})' : ''}';
        lines.add({'line': line});
      }
      return lines;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadCrisis(String patientId) async {
    try {
      final snap = await _firestore
          .collection('crisis_events')
          .where('patientId', isEqualTo: patientId)
          .orderBy('timestamp', descending: true)
          .limit(3)
          .get();
      final lines = <Map<String, dynamic>>[];
      for (final e in snap.docs) {
        final d = e.data();
        final msg = (d['message'] ?? '').toString().trim();
        final line = '${_fmtDate(_toDate(d['timestamp']))}: '
            '${d['severity'] ?? 'n/a'}'
            '${msg.isNotEmpty ? ' - ${_clip(msg, 100)}' : ''}';
        lines.add({'line': line});
      }
      return lines;
    } catch (_) {
      return [];
    }
  }

  String _compactLog(Map<String, dynamic> d) {
    final date = _fmtDate(_toDate(d['timestamp']));
    final mood = d['mood'] ?? d['moodKey'] ?? '?';
    final sleep = d['sleep'] ?? '?';
    final energy = d['energy'] ?? '?';
    final wb = d['wellbeingScore'];
    final risk = d['riskScore'];
    final worries = d['worries'] is List ? (d['worries'] as List).join(', ') : '';
    final positives = d['positives'] is List ? (d['positives'] as List).join(', ') : '';
    final dump = d['thoughtDump'];
    final note = d['optionalNote'];

    final bits = <String>['$date: mood $mood, sleep $sleep, energy $energy'];
    if (wb != null) bits.add('wellbeing $wb/100');
    if (risk != null) bits.add('risk $risk');
    if (worries.isNotEmpty) bits.add('worried about: $worries');
    if (positives.isNotEmpty) bits.add('positives: $positives');
    if (dump != null && dump.toString().trim().isNotEmpty) {
      bits.add('note: ${_clip(dump.toString(), 120)}');
    }
    if (note != null && note.toString().trim().isNotEmpty) {
      bits.add('grateful: ${_clip(note.toString(), 80)}');
    }
    return bits.join('; ');
  }

  String? _buildTrend(List<Map<String, dynamic>> logs) {
    final wbs = <double>[];
    final sleeps = <double>[];
    for (final d in logs) {
      final wb = d['wellbeingScore'];
      if (wb is num) wbs.add(wb.toDouble());
      final sl = d['sleepScore'];
      if (sl is num) sleeps.add(sl.toDouble());
    }
    if (wbs.length < 2) return null;

    final count = logs.length;
    final avgWb = wbs.reduce((a, b) => a + b) / wbs.length;
    final half = (wbs.length / 2).ceil();
    final recentSlice = wbs.take(half).toList();
    final olderSlice = wbs.skip(half).toList();
    final recentAvg = recentSlice.reduce((a, b) => a + b) / recentSlice.length;
    final olderAvg = olderSlice.isEmpty ? recentAvg : olderSlice.reduce((a, b) => a + b) / olderSlice.length;
    final delta = recentAvg - olderAvg;

    final direction = delta >= 5
        ? 'improving'
        : (delta <= -5 ? 'declining' : 'stable');

    var text = 'Trend: over the last $count check-ins, wellbeing averages '
        '${avgWb.round()}/100 and is $direction';
    if (sleeps.isNotEmpty) {
      final avgSleep = sleeps.reduce((a, b) => a + b) / sleeps.length;
      text += ', sleep averaging ${avgSleep.toStringAsFixed(1)}/4';
    }
    return '$text.';
  }

  String _logText(Map<String, dynamic> d) {
    return <String>[
      if (d['worries'] is List) (d['worries'] as List).join(' '),
      if (d['positives'] is List) (d['positives'] as List).join(' '),
      d['summaryText']?.toString() ?? '',
      d['thoughtDump']?.toString() ?? '',
      d['optionalNote']?.toString() ?? '',
    ].join(' ');
  }

  List<String> _rankRelevantLogs(
    List<Map<String, dynamic>> logs,
    String message,
  ) {
    final queryTerms = _tokens(message).toList();
    if (queryTerms.isEmpty) return [];

    final docTexts = logs.map(_logText).toList();
    final docTermSets = <Set<String>>[];
    final df = <String, int>{};
    for (final text in docTexts) {
      final terms = _tokens(text);
      docTermSets.add(terms);
      for (final term in terms) {
        df[term] = (df[term] ?? 0) + 1;
      }
    }

    final n = docTexts.length;
    final scored = <(double, String)>[];
    for (var i = 0; i < docTexts.length; i++) {
      final terms = docTermSets[i];
      if (terms.isEmpty) continue;

      var score = 0.0;
      for (final term in queryTerms) {
        if (!terms.contains(term)) continue;
        final idf = math.log(n / (1 + (df[term] ?? 0)));
        score += idf;
      }
      if (score > 0) scored.add((score, _compactLog(logs[i])));
    }

    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(_topRelevantCount).map((e) => e.$2).toList();
  }

  Set<String> _tokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 2 && !_stopwords.contains(t))
        .toSet();
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _fmtDate(DateTime? dt) => dt == null ? 'unknown date' : _dateFmt.format(dt);

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String _phqLabel(int score) {
    if (score >= 20) return 'severe';
    if (score >= 15) return 'moderately severe';
    if (score >= 10) return 'moderate';
    if (score >= 5) return 'mild';
    return 'minimal';
  }

  String _gadLabel(int score) {
    if (score >= 15) return 'severe';
    if (score >= 10) return 'moderate';
    if (score >= 5) return 'mild';
    return 'minimal';
  }
}
