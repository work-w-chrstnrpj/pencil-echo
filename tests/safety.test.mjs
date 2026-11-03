import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { writeFileSafe, copyDirectorySafe, safeMergeJson, isManagedFile } from '../lib/safety.mjs';

describe('Safety & Non-Destructive File Operations', () => {
  let tempDir;

  before(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'safety-test-'));
  });

  after(() => {
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('does not overwrite user files without generator signature unless force is true', () => {
    const userFile = path.join(tempDir, 'user-custom-rule.md');
    fs.writeFileSync(userFile, 'My hand-written custom rule content', 'utf8');

    assert.equal(isManagedFile(userFile), false);

    // Attempt overwrite without force
    const res1 = writeFileSafe(userFile, 'New generated content', { force: false });
    assert.equal(res1.status, 'skipped_user_file');
    assert.equal(fs.readFileSync(userFile, 'utf8'), 'My hand-written custom rule content');

    // Attempt overwrite with force
    const res2 = writeFileSafe(userFile, 'New generated content', { force: true });
    assert.equal(res2.status, 'updated');
    assert.equal(fs.readFileSync(userFile, 'utf8'), 'New generated content');
  });

  test('safeMergeJson preserves custom user properties and merges arrays', () => {
    const jsonFile = path.join(tempDir, 'custom-config.json');
    const initialConfig = {
      model: 'custom-model-4',
      plugins: ['plugin-a'],
      instructions: ['custom-instruction.md']
    };
    fs.writeFileSync(jsonFile, JSON.stringify(initialConfig, null, 2), 'utf8');

    safeMergeJson(jsonFile, {
      instructions: ['AGENTS.md', 'custom-instruction.md'],
      newEngineProp: true
    });

    const updated = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
    assert.equal(updated.model, 'custom-model-4', 'Must preserve existing custom scalar properties');
    assert.deepEqual(updated.plugins, ['plugin-a'], 'Must preserve existing custom arrays');
    assert.ok(updated.instructions.includes('custom-instruction.md'), 'Must keep existing array item');
    assert.ok(updated.instructions.includes('AGENTS.md'), 'Must append new array item without duplicates');
    assert.equal(updated.instructions.filter(i => i === 'custom-instruction.md').length, 1, 'No duplicate array elements');
    assert.equal(updated.newEngineProp, true);
  });

  test('directory copies preserve custom files unless force is true', () => {
    const source = path.join(tempDir, 'copy-source');
    const destination = path.join(tempDir, 'copy-destination');
    fs.mkdirSync(source, { recursive: true });
    fs.mkdirSync(destination, { recursive: true });
    fs.writeFileSync(path.join(source, 'SKILL.md'), 'generated skill', 'utf8');
    fs.writeFileSync(path.join(destination, 'SKILL.md'), 'custom skill', 'utf8');

    const skipped = copyDirectorySafe(source, destination);
    assert.equal(skipped[0].status, 'skipped_user_file');
    assert.equal(fs.readFileSync(path.join(destination, 'SKILL.md'), 'utf8'), 'custom skill');

    copyDirectorySafe(source, destination, { force: true });
    assert.equal(fs.readFileSync(path.join(destination, 'SKILL.md'), 'utf8'), 'generated skill');
  });

  test('directory copies can update files marked as generator-managed', () => {
    const source = path.join(tempDir, 'managed-source');
    const destination = path.join(tempDir, 'managed-destination');
    fs.mkdirSync(source, { recursive: true });
    fs.writeFileSync(path.join(source, 'SKILL.md'), '---\nname: demo\ndescription: demo\n---\n\nVersion one', 'utf8');

    copyDirectorySafe(source, destination, { managed: true });
    const installed = path.join(destination, 'SKILL.md');
    assert.equal(isManagedFile(installed), true);

    fs.writeFileSync(path.join(source, 'SKILL.md'), '---\nname: demo\ndescription: demo\n---\n\nVersion two', 'utf8');
    const updated = copyDirectorySafe(source, destination, { managed: true });
    assert.equal(updated[0].status, 'updated');
    assert.match(fs.readFileSync(installed, 'utf8'), /Version two/);
  });

  test('safeMergeJson rejects invalid JSON without changing the file', () => {
    const jsonFile = path.join(tempDir, 'invalid-config.json');
    const invalidJson = '{"model":"user-model",}';
    fs.writeFileSync(jsonFile, invalidJson, 'utf8');

    assert.throws(
      () => safeMergeJson(jsonFile, { instructions: ['AGENTS.md'] }),
      /existing JSON is invalid/
    );
    assert.equal(fs.readFileSync(jsonFile, 'utf8'), invalidJson);
  });
});
