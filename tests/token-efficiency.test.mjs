import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { measureTokens, estimateTokens } from '../lib/measure.mjs';

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const templateRoot = path.resolve(currentDir, '..');

describe('Token Efficiency & Budgets', () => {
  test('compact roles remain within target token budget (< 1500 tokens for core)', () => {
    const report = measureTokens(templateRoot);

    // Software engineer core role
    assert.ok(report.roles['software-engineer.md']);
    assert.ok(
      report.roles['software-engineer.md'].tokens < 1200,
      `software-engineer tokens (${report.roles['software-engineer.md'].tokens}) must be < 1200`
    );

    // Refactored backend role
    assert.ok(report.roles['backend-database-engineer.md']);
    assert.ok(
      report.roles['backend-database-engineer.md'].tokens < 1600,
      `backend-database-engineer tokens (${report.roles['backend-database-engineer.md'].tokens}) must be < 1600`
    );

    // Refactored devops role
    assert.ok(report.roles['devops-engineer.md']);
    assert.ok(
      report.roles['devops-engineer.md'].tokens < 1400,
      `devops-engineer tokens (${report.roles['devops-engineer.md'].tokens}) must be < 1400`
    );
  });

  test('reference playbooks exist and are properly modularized', () => {
    const report = measureTokens(templateRoot);
    assert.ok(report.playbooks.backend);
    assert.ok(report.playbooks.backend['api-design-and-contracts.md']);
    assert.ok(report.playbooks.backend['database-schema-and-migrations.md']);
    assert.ok(report.playbooks.devops);
    assert.ok(report.playbooks.devops['ci-cd-pipelines.md']);
    assert.ok(report.playbooks.devops['deployment-and-rollouts.md']);
  });

  test('Cursor rules in .cursor/rules/ do not contain wildcard globs', () => {
    const cursorRulesDir = path.join(templateRoot, '.cursor', 'rules');
    if (!fs.existsSync(cursorRulesDir)) return;

    const files = fs.readdirSync(cursorRulesDir).filter(f => f.endsWith('.mdc'));
    for (const f of files) {
      const content = fs.readFileSync(path.join(cursorRulesDir, f), 'utf8');
      assert.ok(
        !content.includes("globs: '**/*'"),
        `Cursor rule ${f} must not contain globs: '**/*'`
      );
    }
  });
});
