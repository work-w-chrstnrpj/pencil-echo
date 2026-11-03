import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { generatePreset } from '../lib/generator.mjs';
import { validateTemplate } from '../lib/validator.mjs';
import { loadConfig } from '../lib/profiles.mjs';

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const templateRoot = path.resolve(currentDir, '..');

describe('CLI & Generator Engine', () => {
  let tempDir;

  before(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'preset-test-'));
  });

  after(() => {
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('loads valid preset.config.json', () => {
    const config = loadConfig(templateRoot);
    assert.ok(config.name);
    assert.deepEqual(config.providers, ['cursor', 'antigravity', 'claude', 'codex', 'opencode']);
    assert.ok(config.profiles.fullstack);
    assert.ok(config.profiles.general);
    assert.ok(config.profiles.qa);
    assert.ok(config.profiles.architecture);
    assert.ok(config.profiles.docs);
    assert.ok(config.profiles.all);
  });

  test('generates Cursor preset with proper rules and skills', () => {
    const target = path.join(tempDir, 'cursor-project');
    const result = generatePreset({
      templateRoot,
      targetDir: target,
      provider: 'cursor',
      profile: 'general'
    });

    assert.equal(result.provider, 'cursor');
    assert.equal(result.profile, 'general');

    const rulesDir = path.join(target, '.cursor', 'rules');
    assert.ok(fs.existsSync(path.join(rulesDir, 'software-engineer.mdc')));
    assert.ok(fs.existsSync(path.join(rulesDir, 'system-architect.mdc')));

    // Should NOT have backend or frontend in 'general' profile
    assert.ok(!fs.existsSync(path.join(rulesDir, 'backend-database-engineer.mdc')));
    assert.ok(!fs.existsSync(path.join(target, '.agents', 'roles', 'backend-database-engineer.md')));
    assert.ok(!fs.existsSync(path.join(target, '.agents', 'roles', 'playbooks', 'backend')));

    const content = fs.readFileSync(path.join(rulesDir, 'software-engineer.mdc'), 'utf8');
    assert.ok(content.includes('alwaysApply: false'));
    assert.ok(!content.includes("globs: '**/*'"), 'Cursor rules must not use wildcard globs');
  });

  test('generates Claude Code preset with CLAUDE.md and agents', () => {
    const target = path.join(tempDir, 'claude-project');
    const result = generatePreset({
      templateRoot,
      targetDir: target,
      provider: 'claude',
      profile: 'qa'
    });

    assert.equal(result.provider, 'claude');
    const agentsDir = path.join(target, '.claude', 'agents');
    assert.ok(fs.existsSync(path.join(agentsDir, 'sqa-engineer.md')));
    assert.ok(fs.existsSync(path.join(target, 'CLAUDE.md')));

    const agentContent = fs.readFileSync(path.join(agentsDir, 'sqa-engineer.md'), 'utf8');
    assert.ok(agentContent.includes('tools:'));
    assert.ok(agentContent.includes('- Read'));
  });

  test('generates Codex preset with TOML agent manifests', () => {
    const target = path.join(tempDir, 'codex-project');
    const result = generatePreset({
      templateRoot,
      targetDir: target,
      provider: 'codex',
      profile: 'architecture'
    });

    assert.equal(result.provider, 'codex');
    const agentsDir = path.join(target, '.codex', 'agents');
    assert.ok(fs.existsSync(path.join(agentsDir, 'system-architect.toml')));
    assert.ok(fs.existsSync(path.join(agentsDir, 'security-engineer.toml')));

    const tomlContent = fs.readFileSync(path.join(agentsDir, 'system-architect.toml'), 'utf8');
    assert.ok(tomlContent.includes('developer_instructions = \'\'\''));
  });

  test('generates OpenCode preset with merged opencode.json', () => {
    const target = path.join(tempDir, 'opencode-project');
    // Pre-create opencode.json with custom user fields
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'opencode.json'), JSON.stringify({
      customSetting: 'my-custom-val',
      instructions: ['custom-rule.md']
    }, null, 2));

    generatePreset({
      templateRoot,
      targetDir: target,
      provider: 'opencode',
      profile: 'fullstack'
    });

    const parsedJson = JSON.parse(fs.readFileSync(path.join(target, 'opencode.json'), 'utf8'));
    assert.equal(parsedJson.customSetting, 'my-custom-val', 'Must preserve custom user fields');
    assert.ok(parsedJson.instructions.includes('custom-rule.md'), 'Must preserve user instructions');
    assert.ok(parsedJson.instructions.includes('AGENTS.md'), 'Must include template instructions');
  });

  test('dryRun does not write any files to disk', () => {
    const target = path.join(tempDir, 'dryrun-project');
    const result = generatePreset({
      templateRoot,
      targetDir: target,
      provider: 'cursor',
      profile: 'fullstack',
      dryRun: true
    });

    assert.ok(!fs.existsSync(target), 'Directory must not be created during dry run');
  });

  test('external presets include the canonical context they reference', () => {
    for (const provider of ['cursor', 'antigravity', 'claude', 'codex', 'opencode']) {
      const target = path.join(tempDir, `complete-${provider}`);
      generatePreset({ templateRoot, targetDir: target, provider, profile: 'fullstack' });

      for (const required of [
        'AGENTS.md',
        'preset.config.json',
        '.ai/context-routing.md',
        '.agents/skills/execute-code-change/SKILL.md',
        '.agents/roles/software-engineer.md',
        '.agents/roles/playbooks/backend/api-design-and-contracts.md'
      ]) {
        assert.ok(fs.existsSync(path.join(target, required)), `${provider} must install ${required}`);
      }

      const validation = validateTemplate(target);
      assert.equal(validation.errors.length, 0, `${provider}: ${validation.errors.join('; ')}`);
    }
  });
});
