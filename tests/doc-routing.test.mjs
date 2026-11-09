import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateTemplate } from '../lib/validator.mjs';

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const templateRoot = path.resolve(currentDir, '..');

describe('Documentation Routing & Context Integrity', () => {
  test('zero active markdown files contain obsolete wiki/ paths', () => {
    const result = validateTemplate(templateRoot);
    const wikiErrors = result.errors.filter(e => e.includes("obsolete 'wiki/' path"));
    assert.deepEqual(wikiErrors, [], 'Found files referencing obsolete wiki/');
  });

  test('all canonical roles and skills pass structural validation', () => {
    const result = validateTemplate(templateRoot);
    assert.equal(result.errors.length, 0, `Validation errors: ${result.errors.join('; ')}`);
    assert.ok(result.passed.length >= 20, 'Expected at least 20 passed checks');
  });

  test('task-based context check passes when required docs are initialized', () => {
    const result = validateTemplate(templateRoot, { task: 'database' });
    assert.equal(result.valid, true, 'Validation should pass when task docs are initialized');
    assert.deepEqual(result.errors, [], `Unexpected task validation errors: ${result.errors.join('; ')}`);
    assert.ok(result.passed.some(e => e.includes("Task context verified for 'database'")));
  });

  test('general validation passes for repository docs', () => {
    const result = validateTemplate(templateRoot);
    assert.equal(result.valid, true, 'General validation should pass');
    assert.ok(Array.isArray(result.warnings), 'Warnings should be returned as an array');
  });
});
