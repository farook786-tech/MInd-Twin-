const ClinicalService = require('../src/services/ClinicalService');

// Official PHQ-9 clinical cutoffs (Kroenke, Spitzer & Williams, 2001)
const OFFICIAL_CUTOFFS = [
  { min: 0, max: 4, expected: 'minimal' },
  { min: 5, max: 9, expected: 'mild' },
  { min: 10, max: 14, expected: 'moderate' },
  { min: 15, max: 19, expected: 'moderately_severe' },
  { min: 20, max: 27, expected: 'severe' },
];

function scoreToResponses(score) {
  const responses = new Array(9).fill(0);
  let remaining = score;
  for (let i = 0; i < 9 && remaining > 0; i++) {
    const val = Math.min(3, remaining);
    responses[i] = val;
    remaining -= val;
  }
  return responses;
}

describe('PHQ-9 Severity Mapping — Clinical Validation', () => {
  let total = 0;
  let correct = 0;

  for (let score = 0; score <= 27; score++) {
    const expectedBand = OFFICIAL_CUTOFFS.find(c => score >= c.min && score <= c.max);
    test(`score=${score} should map to "${expectedBand.expected}"`, () => {
      const responses = scoreToResponses(score);
      const result = ClinicalService.prototype.scorePHQ9.call(
        Object.create(ClinicalService.prototype),
        responses
      );
      total++;
      if (result.severity === expectedBand.expected) correct++;
      expect(result.score).toBe(score);
      expect(result.severity).toBe(expectedBand.expected);
    });
  }

  afterAll(() => {
    const accuracy = ((correct / total) * 100).toFixed(2);
    console.log(`\nPHQ-9 Severity Mapping Concordance: ${correct}/${total} (${accuracy}%)`);
  });
});
