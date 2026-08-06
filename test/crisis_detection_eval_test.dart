import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/ml_sentiment_service.dart';

// Labeled test set: true = should be flagged crisisDetected
final List<Map<String, dynamic>> testSet = [
  {'text': "I want to kill myself", 'label': true},
  {'text': "I've been thinking about ending my life", 'label': true},
  {'text': "sometimes I just want to hurt myself", 'label': true},
  {'text': "I don't want to be here anymore, thinking about suicide", 'label': true},
  {'text': "nothing matters, I feel completely hopeless", 'label': true},
  {'text': "I can not do this anymore, everything feels pointless", 'label': true},
  {'text': "I've been having thoughts of self-harm lately", 'label': true},
  {'text': "I feel hopeless and keep thinking about hurting myself", 'label': true},
  {'text': "I just want it all to end", 'label': false},
  {'text': "I'm so angry and hopeless about everything", 'label': true},
  {'text': "I had a pretty good day today, feeling okay", 'label': false},
  {'text': "I'm a bit anxious about my exam tomorrow", 'label': false},
  {'text': "feeling grateful for my friends this week", 'label': false},
  {'text': "I'm frustrated with my job but managing okay", 'label': false},
  {'text': "I didn't sleep well last night, feeling tired", 'label': false},
  {'text': "I feel calm and grounded after my walk", 'label': false},
  {'text': "things are improving slowly, I have hope", 'label': false},
  {'text': "I'm sad about the news but I'm okay", 'label': false},
  {'text': "just a normal day, nothing much happened", 'label': false},
  {'text': "I'm worried about money but I'll figure it out", 'label': false},
  {'text': "feeling down today but I know it'll pass", 'label': false},
  {'text': "had an argument with my friend, feeling mad", 'label': false},
  {'text': "I'm glad the weekend is here, feeling happy", 'label': false},
  {'text': "panic set in before my presentation, but I got through it", 'label': false},
  {'text': "I feel fine, just a regular check-in", 'label': false},
];

void main() {
  test('Crisis Detection — Precision/Recall/F1 Evaluation', () async {
    final service = MlSentimentService();
    int tp = 0, fp = 0, tn = 0, fn = 0;

    for (final example in testSet) {
      final result = await service.detectCrisis(
        example['text'] as String,
        'test-patient-id',
        [],
      );
      final predicted = result.crisisDetected;
      final actual = example['label'] as bool;

      if (predicted && actual) tp++;
      else if (predicted && !actual) fp++;
      else if (!predicted && !actual) tn++;
      else if (!predicted && actual) fn++;

      print('${actual ? "CRISIS" : "SAFE  "} | predicted=${predicted ? "CRISIS" : "SAFE  "} | "${example['text']}"');
    }

    final accuracy = (tp + tn) / testSet.length;
    final precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
    final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
    final f1 = (precision + recall) == 0 ? 0.0 : 2 * (precision * recall) / (precision + recall);

    print('\n--- Crisis Detection Evaluation Results ---');
    print('TP=$tp  FP=$fp  TN=$tn  FN=$fn');
    print('Accuracy:  ${(accuracy * 100).toStringAsFixed(2)}%');
    print('Precision: ${(precision * 100).toStringAsFixed(2)}%');
    print('Recall:    ${(recall * 100).toStringAsFixed(2)}%');
    print('F1-Score:  ${(f1 * 100).toStringAsFixed(2)}%');
  });
}
