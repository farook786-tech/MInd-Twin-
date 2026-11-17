// Clinical-safety evaluation of the offline crisis fallback
// (lib/services/ml_sentiment_service.dart). Uses the shared eval sets in
// ml_service/eval and the shared lexicon ml_service/crisis_lexicon.json.
// Report: docs/ML_SAFETY_EVALUATION.md
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/ml_sentiment_service.dart';

const _siCategories = {
  'explicit_si', 'passive_si', 'self_harm', 'method_plan', 'negated_si', 'slang_si', 'hinglish_si',
};

List<Map<String, dynamic>> _load(String file) => File('ml_service/eval/$file')
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => jsonDecode(l) as Map<String, dynamic>)
    .toList();

void main() {
  final service = MlSentimentService();

  test('embedded lexicon is in sync with ml_service/crisis_lexicon.json', () {
    final src = jsonDecode(File('ml_service/crisis_lexicon.json').readAsStringSync()) as Map<String, dynamic>;
    expect(kCrisisLexiconVersion, src['version']);
    expect(kCrisisModelThreshold, (src['model_threshold'] as num).toDouble());
    expect(kCrisisNegationCues, src['negation_cues']);
    expect(kCrisisExtraSeparators, src['extra_separators']);
    List<String> res(List<dynamic> l) => l.map((e) => '${e['id']}|${e['re']}').toList();
    List<String> mine(List<Map<String, String>> l) => l.map((e) => '${e['id']}|${e['re']}').toList();
    expect(mine(kCrisisHardPatterns), res(src['hard'] as List));
    expect(mine(kCrisisSoftPatterns), res(src['soft'] as List));
    expect(mine(kCrisisIdiomPatterns), res(src['idiom'] as List));
  });

  for (final file in ['crisis_eval_set.jsonl', 'crisis_challenge_set.jsonl', 'crisis_blind_set.jsonl']) {
    test('offline fallback on $file: no false negatives, precision >= 0.9', () async {
      final items = _load(file);
      var tp = 0, fp = 0, fn = 0, tn = 0;
      final misses = <String>[];
      final weakIdeation = <String>[];
      for (final it in items) {
        final text = it['t'] as String;
        final r = await service.detectCrisis(text, 'test-patient', const []);
        final y = it['y'] == 1;
        if (r.crisisDetected && y) {
          tp++;
        } else if (r.crisisDetected) {
          fp++;
        } else if (y) {
          fn++;
          misses.add('[${it['c']}] $text');
        } else {
          tn++;
        }
        if ((it['c'] == 'explicit_si' || it['c'] == 'passive_si') && r.triggerLayer != 'phrase_hard') {
          weakIdeation.add(text);
        }
      }
      final recall = tp / (tp + fn);
      final precision = tp / (tp + fp == 0 ? 1 : tp + fp);
      // ignore: avoid_print
      print('$file n=${items.length} recall=${recall.toStringAsFixed(3)} '
          'precision=${precision.toStringAsFixed(3)} TP=$tp FN=$fn FP=$fp TN=$tn');
      expect(misses, isEmpty, reason: 'Crisis phrases must never be missed');
      expect(weakIdeation, isEmpty, reason: 'Explicit/passive ideation must hit a hard phrase');
      expect(precision, greaterThanOrEqualTo(0.9));
    });
  }

  test('idioms never suppress explicit ideation; negation never suppresses', () {
    final crisis = _load('crisis_eval_set.jsonl').where((i) => _siCategories.contains(i['c']));
    for (final it in crisis) {
      for (final suffix in [' this exam is killing me', ' lol dying laughing', ' to die for']) {
        for (final p in [null, 0.0, 0.99]) {
          final d = MlSentimentService.evaluateCrisisText('${it['t']}$suffix', modelProbability: p);
          expect(d.escalate, isTrue, reason: '${it['t']}$suffix @ $p');
        }
      }
    }
    final neg = MlSentimentService.evaluateCrisisText("I'm not going to kill myself, just tired");
    expect(neg.escalate, isTrue);
    expect(neg.negationPresent, isTrue);
  });

  test('idiom suppresses only model-only escalations', () {
    expect(MlSentimentService.evaluateCrisisText('This exam is killing me', modelProbability: 0.95).escalate, isFalse);
    expect(MlSentimentService.evaluateCrisisText('This exam is killing me').escalate, isFalse);
    expect(MlSentimentService.evaluateCrisisText('everything is grey', modelProbability: 0.8).escalate, isTrue);
  });

  test('crisis disclosed earlier in the conversation is not lost', () async {
    final r = await service.detectCrisis('ok', 'p', const ['I want to kill myself']);
    expect(r.crisisDetected, isTrue);
    expect(r.triggerLayer, 'history');
  });

  test('method/plan is critical; null/empty input is safe', () async {
    expect((await service.detectCrisis('I bought a rope', 'p', const [])).severity, 'critical');
    expect(MlSentimentService.evaluateCrisisText(null).escalate, isFalse);
    expect((await service.detectCrisis('', 'p', const [])).crisisDetected, isFalse);
  });

  test('normalization matches the backend contract', () {
    expect(MlSentimentService.normalizeForCrisis("I DON'T want to live"), 'i dont want to live');
    expect(MlSentimentService.normalizeForCrisis('Want. To. Die.'), 'want to die');
    expect(MlSentimentService.normalizeForCrisis('i’m   suicidal!!!'), 'im suicidal');
    expect(MlSentimentService.normalizeForCrisis('जीने का मन नहीं है।'), 'जीने का मन नहीं है');
  });

  test('sentiment flags self-harm language and hopelessness', () async {
    final s = await service.analyzeSentiment('I feel hopeless and want to hurt myself');
    expect(s.clinicalFlags, containsAll(['hopelessness', 'self_harm_language', 'crisis_review_required']));
    expect(s.sentiment, 'negative');
    final pos = await service.analyzeSentiment('feeling grateful and calm today');
    expect(pos.sentiment, 'positive');
    expect(pos.clinicalFlags, isNot(contains('crisis_review_required')));
  });
}
