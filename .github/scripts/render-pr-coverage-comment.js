'use strict';

const LIMITS = Object.freeze({
  files: 500,
  linesPerFile: 10_000,
  linesTotal: 50_000,
  lineNumber: 10_000_000,
  sourceFiles: 10,
  sourceAttempts: 20,
  sourceBytesPerFile: 64 * 1024,
  sourceBytesTotal: 512 * 1024,
  excerptTargets: 40,
  excerptLines: 200,
  lineCharacters: 400,
  commentCharacters: 50_000,
});

function invalid(message) { throw new Error(`invalid report: ${message}`); }

function validPath(value) {
  return typeof value === 'string' && Buffer.byteLength(value, 'utf8') <= 500
    && value.length > 0 && !/[\\\u0000-\u001f\u007f]/.test(value) && !value.startsWith('/')
    && value.split('/').every((part) => part && part !== '.' && part !== '..');
}

function validLines(lines, label) {
  if (!Array.isArray(lines) || lines.length > LIMITS.linesPerFile) invalid(label);
  let previous = 0;
  for (const line of lines) {
    if (!Number.isSafeInteger(line) || line <= previous || line > LIMITS.lineNumber) invalid(label);
    previous = line;
  }
}

function validateCounts(counts, label) {
  if (!counts || !['covered', 'uncovered', 'executable'].every((key) => Number.isSafeInteger(counts[key]) && counts[key] >= 0)
    || counts.covered + counts.uncovered !== counts.executable) invalid(label);
}

function validateReport(report, headSHA) {
  if (!report || report.schemaVersion !== 1 || report.coverageInput?.kind !== 'llvm'
    || report.comparison?.resolvedHead !== headSHA || !Array.isArray(report.files)
    || report.files.length > LIMITS.files || !['passed', 'failed', 'notApplicable'].includes(report.policy?.status)) invalid('contract');
  validateCounts(report.totals, 'totals');
  const paths = new Set();
  let covered = 0; let uncovered = 0; let executable = 0; let lineTotal = 0;
  for (const file of report.files) {
    if (!validPath(file?.path) || paths.has(file.path)) invalid('path');
    paths.add(file.path);
    validateCounts(file.counts, 'file counts');
    validLines(file.coveredLines, 'covered lines');
    validLines(file.uncoveredLines, 'uncovered lines');
    if (file.coveredLines.length !== file.counts.covered || file.uncoveredLines.length !== file.counts.uncovered) invalid('line counts');
    const coveredSet = new Set(file.coveredLines);
    if (file.uncoveredLines.some((line) => coveredSet.has(line))) invalid('overlapping lines');
    covered += file.counts.covered; uncovered += file.counts.uncovered; executable += file.counts.executable;
    lineTotal += file.counts.executable;
    if (lineTotal > LIMITS.linesTotal) invalid('too many lines');
  }
  if (covered !== report.totals.covered || uncovered !== report.totals.uncovered || executable !== report.totals.executable) invalid('aggregate counts');
  return report;
}

function escapeText(value) { return String(value).replace(/[&<>|]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '|': '&#124;' })[character]); }
function truncate(value) { return value.length > LIMITS.lineCharacters ? `${value.slice(0, LIMITS.lineCharacters - 1)}…` : value; }
function safeSource(value) {
  if (typeof value !== 'string' || Buffer.byteLength(value, 'utf8') > LIMITS.sourceBytesPerFile || /\u0000/.test(value)) return null;
  return value.replace(/\r\n?/g, '\n').split('\n').map((line) => truncate(line.replace(/[\u202a-\u202e\u2066-\u2069]/g, '�')));
}

function render(report, sources = {}) {
  const percent = report.totals.executable === 0 ? 'Not applicable' : `${(report.totals.covered * 100 / report.totals.executable).toFixed(2)}%`;
  const status = report.policy.status === 'failed' ? '❌ Below the configured threshold' : '✅ Coverage check passed';
  const excerpts = [];
  let targets = 0; let renderedLines = 0; let unavailable = 0;
  for (const file of report.files) {
    if (!file.uncoveredLines.length) continue;
    const source = safeSource(sources[file.path]);
    if (!source || excerpts.length >= LIMITS.sourceFiles) { unavailable += file.uncoveredLines.length; continue; }
    const selected = file.uncoveredLines.slice(0, Math.max(0, LIMITS.excerptTargets - targets));
    if (!selected.length) { unavailable += file.uncoveredLines.length; continue; }
    const wanted = new Set(selected);
    const shown = new Set();
    for (const line of selected) for (let index = Math.max(1, line - 2); index <= Math.min(source.length, line + 2); index += 1) shown.add(index);
    const lines = [...shown].sort((a, b) => a - b).slice(0, LIMITS.excerptLines - renderedLines);
    if (!lines.length) { unavailable += file.uncoveredLines.length; continue; }
    const body = lines.map((line) => `${wanted.has(line) ? '▶' : ' '} ${String(line).padStart(4)} │ ${source[line - 1]}`).join('\n');
    const fence = '~'.repeat(Math.max(3, ...(body.match(/~+/g) || []).map((match) => match.length + 1)));
    excerpts.push(`**${escapeText(file.path)}**\n${fence}text\n${body}\n${fence}`);
    targets += selected.length; renderedLines += lines.length;
    unavailable += file.uncoveredLines.length - selected.length;
  }
  const rows = report.files.slice(0, 80).map((file) => `| ${escapeText(file.path)} | ${file.counts.executable === 0 ? 'Not applicable' : `${(file.counts.covered * 100 / file.counts.executable).toFixed(2)}%`} | ${file.counts.covered} | ${file.counts.uncovered} |`);
  const omittedFiles = report.files.length - rows.length;
  const sourceSection = excerpts.length ? ['<details>', `<summary>Uncovered source (${Math.min(targets, LIMITS.excerptTargets)} lines)</summary>`, '', ...excerpts, unavailable ? `\n_${unavailable} uncovered lines omitted or source unavailable._` : '', '</details>'] : [];
  const table = report.files.length ? ['| File | Coverage | Covered | Uncovered |', '| --- | ---: | ---: | ---: |', ...rows, ...(omittedFiles ? [`\n_${omittedFiles} additional files omitted._`] : [])] : ['No changed executable lines were found.'];
  const body = ['<!-- whatcoverage:pr-report:v1 -->', '## WhatCoverage', '', status, '', `**Diff coverage:** ${percent} (${report.totals.covered}/${report.totals.executable} executable lines)`, '', ...sourceSection, ...(sourceSection.length ? [''] : []), '<details>', '<summary>Verbose coverage report</summary>', '', ...table, '', '[View the workflow run](RUN_URL)', '</details>'].join('\n');
  if (body.length > LIMITS.commentCharacters) throw new Error('rendered comment is too large');
  return body;
}

module.exports = { LIMITS, render, safeSource, validateReport };
