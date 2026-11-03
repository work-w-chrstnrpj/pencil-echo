import fs from 'node:fs';
import path from 'node:path';
import { loadConfig } from './profiles.mjs';

export function validateTemplate(rootDir, options = {}) {
  const { task = null } = options;
  const config = loadConfig(rootDir);
  const errors = [];
  const warnings = [];
  const passed = [];

  // 1. Validate canonical roles
  const rolesDir = path.join(rootDir, '.agents', 'roles');
  if (!fs.existsSync(rolesDir)) {
    errors.push(`Missing .agents/roles directory in ${rootDir}`);
  } else {
    const roleFiles = fs.readdirSync(rolesDir).filter(f => f.endsWith('.md') && f !== 'README.md');
    for (const f of roleFiles) {
      const p = path.join(rolesDir, f);
      const content = fs.readFileSync(p, 'utf8');
      if (!content.match(/^- \*\*Name:\*\*\s*(.+?)\s*$/m)) {
        errors.push(`.agents/roles/${f}: missing '- **Name:**' metadata`);
      }
      if (!content.match(/^- \*\*Description:\*\*\s*(.+?)\s*$/m)) {
        errors.push(`.agents/roles/${f}: missing '- **Description:**' metadata`);
      }
      if (!content.match(/^## Reusable Skills/m)) {
        errors.push(`.agents/roles/${f}: missing '## Reusable Skills' section`);
      }
      passed.push(`.agents/roles/${f}: metadata valid`);
    }
  }

  // 2. Validate canonical skills
  const skillsDir = path.join(rootDir, '.agents', 'skills');
  if (!fs.existsSync(skillsDir)) {
    errors.push(`Missing .agents/skills directory in ${rootDir}`);
  } else {
    const skillDirs = fs.readdirSync(skillsDir, { withFileTypes: true }).filter(d => d.isDirectory());
    for (const d of skillDirs) {
      const skillFile = path.join(skillsDir, d.name, 'SKILL.md');
      if (!fs.existsSync(skillFile)) {
        errors.push(`.agents/skills/${d.name}: missing SKILL.md`);
        continue;
      }
      const content = fs.readFileSync(skillFile, 'utf8');
      const fmMatch = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---/);
      if (!fmMatch) {
        errors.push(`.agents/skills/${d.name}/SKILL.md: missing frontmatter`);
      } else {
        if (!fmMatch[1].match(/^name:\s*\S+/m)) {
          errors.push(`.agents/skills/${d.name}/SKILL.md: frontmatter missing name`);
        }
        if (!fmMatch[1].match(/^description:\s*\S+/m)) {
          errors.push(`.agents/skills/${d.name}/SKILL.md: frontmatter missing description`);
        }
        passed.push(`.agents/skills/${d.name}: valid frontmatter`);
      }
    }
  }

  // 3. Scan for any broken wiki/ paths across Markdown files
  function scanMarkdownFiles(dir) {
    const mdFiles = [];
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name === '.git' || entry.name === 'node_modules') continue;
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        mdFiles.push(...scanMarkdownFiles(fullPath));
      } else if (entry.isFile() && entry.name.endsWith('.md')) {
        mdFiles.push(fullPath);
      }
    }
    return mdFiles;
  }

  const allMarkdownFiles = scanMarkdownFiles(rootDir);
  for (const file of allMarkdownFiles) {
    const rel = path.relative(rootDir, file);
    if (rel === 'CHANGELOG.md') continue; // Historical changelog can mention old wiki
    const content = fs.readFileSync(file, 'utf8');
    if (content.match(/\bwiki\//)) {
      errors.push(`${rel}: contains obsolete 'wiki/' path reference. Use 'docs/' instead.`);
    }
  }

  // 4. Validate context rules (core checks -> warnings; task checks -> blocking errors)
  if (config.contextRules) {
    // Core required context
    for (const rule of config.contextRules.requiredCore || []) {
      const filePath = path.join(rootDir, rule.file);
      if (!fs.existsSync(filePath)) {
        warnings.push(`Core doc missing: ${rule.file}`);
        continue;
      }
      const content = fs.readFileSync(filePath, 'utf8');
      for (const check of rule.checks) {
        const regex = new RegExp(check.pattern);
        const matches = regex.test(content);
        if (check.invert ? matches : !matches) {
          warnings.push(`[Context Warning] ${rule.file}: ${check.message}`);
        }
      }
    }

    // Task-specific context checks
    if (task) {
      const cond = config.contextRules.conditionalTasks[task];
      if (!cond) {
        errors.push(`Unknown task '${task}'. Available conditional tasks: ${Object.keys(config.contextRules.conditionalTasks).join(', ')}`);
      } else {
        const condPath = path.join(rootDir, cond.file);
        if (!fs.existsSync(condPath)) {
          errors.push(`[Task Blocked] Task '${task}' requires ${cond.name} at ${cond.file}, but the file is missing.`);
        } else {
          const content = fs.readFileSync(condPath, 'utf8');
          if (content.includes('Status: NOT_STARTED') || content.includes('[State the') || content.includes('[Project Name]')) {
            errors.push(`[Task Blocked] Task '${task}' requires ${cond.name} at ${cond.file}, but it is marked NOT_STARTED or has unfulfilled placeholders.`);
          } else {
            passed.push(`Task context verified for '${task}': ${cond.file}`);
          }
        }
      }
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    passed
  };
}
