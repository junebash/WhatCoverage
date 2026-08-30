'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { render, validateReport } = require('./render-pr-coverage-comment');

function report(overrides = {}) {
  return { schemaVersion: 1, coverageInput: { kind: 'llvm' }, comparison: { resolvedHead: 'a'.repeat(40) }, policy: { status: 'failed', threshold: 60, actual: 100 / 3 }, totals: { covered: 1, uncovered: 2, executable: 3 }, files: [{ path: 'Sources/A.swift', counts: { covered: 1, uncovered: 2, executable: 3 }, coveredLines: [1], uncoveredLines: [3, 7] }], ...overrides };
}

test('renders compact escaped source excerpts with context', () => {
  const body = render(validateReport(report(), 'a'.repeat(40)), { 'Sources/A.swift': 'one\ntwo\nif a < b {\nfour\nfive\nsix\n~~~ secret\n' });
  assert.match(body, /<summary>Uncovered source \(2 lines\)<\/summary>/);
  assert.match(body, /▶    3 │ if a < b \{/);
  assert.match(body, /~~~~text/);
  assert.match(body, /Sources\/A\.swift/);
  assert.match(body, /Failed: 33\.33% is below the required 60\.00%/);
});

test('escapes Markdown table paths and uses a fence longer than source tildes', () => {
  const unusual = report({ files: [{ path: 'Sources/A|<B>.swift', counts: { covered: 1, uncovered: 2, executable: 3 }, coveredLines: [1], uncoveredLines: [3, 7] }] });
  const body = render(validateReport(unusual, 'a'.repeat(40)), { 'Sources/A|<B>.swift': 'one\ntwo\n~~~~~\nfour\nfive\nsix\nseven' });
  assert.match(body, /Sources\/A&#124;&lt;B&gt;\.swift/);
  assert.match(body, /~~~~~~text/);
});

test('rejects malformed paths and inconsistent line data', () => {
  assert.throws(() => validateReport(report({ files: [{ path: '../bad', counts: { covered: 1, uncovered: 2, executable: 3 }, coveredLines: [1], uncoveredLines: [1, 2] }] }), 'a'.repeat(40)));
  assert.throws(() => validateReport(report({ totals: { covered: 1, uncovered: 1, executable: 2 } }), 'a'.repeat(40)));
  assert.throws(() => validateReport(report({ policy: { status: 'failed', threshold: 20, actual: 100 / 3 } }), 'a'.repeat(40)));
});

test('renders passing and not-applicable policy outcomes clearly', () => {
  const passing = report({ policy: { status: 'passed', threshold: 100 / 3 } });
  assert.match(render(validateReport(passing, 'a'.repeat(40))), /Passed: 33\.33% meets the required 33\.33%/);
  const notApplicable = report({ policy: { status: 'notApplicable', threshold: 60 }, totals: { covered: 0, uncovered: 0, executable: 0 }, files: [] });
  assert.match(render(validateReport(notApplicable, 'a'.repeat(40))), /Not applicable: no changed executable lines/);
});

test('truncates source and omits unavailable excerpts', () => {
  const body = render(validateReport(report(), 'a'.repeat(40)), { 'Sources/A.swift': `${'x'.repeat(500)}\n`.repeat(8) });
  assert.match(body, /…/);
  const unavailable = render(validateReport(report(), 'a'.repeat(40)), { 'Sources/A.swift': '\0binary' });
  assert.doesNotMatch(unavailable, /Uncovered source/);
});
