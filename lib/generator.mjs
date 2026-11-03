import fs from 'node:fs';
import path from 'node:path';
import {
  GENERATOR_HEADER,
  writeFileSafe,
  writeManagedFileSafe,
  copyDirectorySafe,
  safeMergeJson,
} from './safety.mjs';
import {
  parseRoleMetadata,
  parseSkillMetadata,
  parseOverlayMetadata,
  getProfile
} from './profiles.mjs';

function escapeYamlString(val) {
  return `'${val.replace(/'/g, "''")}'`;
}

function escapeTomlString(val) {
  return JSON.stringify(val);
}

export function generatePreset(options) {
  const {
    templateRoot,
    targetDir = templateRoot,
    provider,
    profile: profileName = 'fullstack',
    dryRun = false,
    force = false,
    clean = false
  } = options;

  const configPath = path.join(templateRoot, 'preset.config.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const profile = getProfile(config, profileName);

  const rolesDir = path.join(templateRoot, '.agents', 'roles');
  const skillsDir = path.join(templateRoot, '.agents', 'skills');
  const overlaysDir = path.join(templateRoot, '.agents', 'overlays');

  // Collect active roles for profile
  const allRoleFiles = fs.readdirSync(rolesDir).filter(f => f.endsWith('.md') && f !== 'README.md');
  const roles = [];
  for (const f of allRoleFiles) {
    const roleMeta = parseRoleMetadata(path.join(rolesDir, f));
    if (profile.roles.includes(roleMeta.name)) {
      roles.push(roleMeta);
    }
  }

  // Collect active skills for profile
  const allSkillDirs = fs.readdirSync(skillsDir, { withFileTypes: true })
    .filter(d => d.isDirectory() && fs.existsSync(path.join(skillsDir, d.name, 'SKILL.md')));
  const skills = [];
  for (const d of allSkillDirs) {
    const skillMeta = parseSkillMetadata(path.join(skillsDir, d.name));
    if (profile.skills.includes(skillMeta.name)) {
      skills.push(skillMeta);
    }
  }

  // Collect overlays
  const overlays = [];
  if (fs.existsSync(overlaysDir) && profile.overlays) {
    const overlayFiles = fs.readdirSync(overlaysDir).filter(f => f.endsWith('.md') && f !== 'README.md');
    for (const f of overlayFiles) {
      const meta = parseOverlayMetadata(path.join(overlaysDir, f));
      if (profile.overlays.includes(meta.name)) {
        overlays.push(meta);
      }
    }
  }

  const results = [];

  if (path.resolve(targetDir) !== path.resolve(templateRoot)) {
    results.push(...installSharedAssets({
      templateRoot, targetDir, profile, roles, skills, overlays, dryRun, force
    }));
  }

  switch (provider.toLowerCase()) {
    case 'cursor':
      results.push(...generateCursor({ targetDir, roles, skills, overlays, dryRun, force, clean }));
      break;
    case 'antigravity':
      results.push(...generateAntigravity({ templateRoot, targetDir, profile, roles, skills, dryRun, force }));
      break;
    case 'claude':
      results.push(...generateClaude({ targetDir, roles, skills, overlays, dryRun, force, clean }));
      break;
    case 'codex':
      results.push(...generateCodex({ targetDir, roles, dryRun, force }));
      break;
    case 'opencode':
      results.push(...generateOpenCode({ targetDir, roles, skills, overlays, dryRun, force, clean }));
      break;
    default:
      throw new Error(`Unsupported provider: ${provider}. Supported providers: cursor, antigravity, claude, codex, opencode`);
  }

  return {
    provider,
    profile: profile.name,
    targetDir,
    results
  };
}

function generateCursor({ targetDir, roles, skills, overlays, dryRun, force, clean }) {
  const results = [];
  const rulesDir = path.join(targetDir, '.cursor', 'rules');
  const skillsDestDir = path.join(targetDir, '.cursor', 'skills');

  // 1. Generate roles as scoped rules (NO greedy globs: '**/*')
  for (const role of roles) {
    const filePath = path.join(rulesDir, `${role.name}.mdc`);
    const content = [
      '---',
      `description: ${escapeYamlString(role.description)}`,
      'alwaysApply: false',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      role.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  // 2. Generate overlays as on-demand rules (NO globs)
  for (const overlay of overlays) {
    const filePath = path.join(rulesDir, `${overlay.name}.mdc`);
    const content = [
      '---',
      `description: ${escapeYamlString(overlay.description)}`,
      'alwaysApply: false',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      overlay.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  // 3. Copy skills
  const activeSkillNames = skills.map(s => s.name);
  if (clean && fs.existsSync(skillsDestDir)) {
    for (const entry of fs.readdirSync(skillsDestDir, { withFileTypes: true })) {
      if (entry.isDirectory() && !activeSkillNames.includes(entry.name)) {
        const staleDir = path.join(skillsDestDir, entry.name);
        if (!dryRun) fs.rmSync(staleDir, { recursive: true, force: true });
        results.push({ status: 'removed_stale', path: staleDir });
      }
    }
  }

  for (const skill of skills) {
    const destSkill = path.join(skillsDestDir, skill.name);
    results.push(...copyDirectorySafe(skill.directory, destSkill, { dryRun, force, managed: true }));
  }

  return results;
}

function generateClaude({ targetDir, roles, skills, overlays, dryRun, force, clean }) {
  const results = [];
  const agentsDir = path.join(targetDir, '.claude', 'agents');
  const skillsDestDir = path.join(targetDir, '.claude', 'skills');

  for (const role of roles) {
    const filePath = path.join(agentsDir, `${role.name}.md`);
    const content = [
      '---',
      `name: ${role.name}`,
      `description: ${escapeYamlString(role.description)}`,
      'tools:',
      '  - Read',
      '  - Glob',
      '  - Grep',
      '  - Edit',
      '  - MultiEdit',
      '  - Bash',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      role.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  for (const overlay of overlays) {
    const filePath = path.join(agentsDir, `${overlay.name}.md`);
    const content = [
      '---',
      `name: ${overlay.name}`,
      `description: ${escapeYamlString(overlay.description)}`,
      'tools:',
      '  - Read',
      '  - Glob',
      '  - Grep',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      overlay.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  // CLAUDE.md summary
  const claudeMdPath = path.join(targetDir, 'CLAUDE.md');
  const claudeMdContent = [
    '# Claude Code Project Instructions',
    '',
    GENERATOR_HEADER,
    '',
    'Read `AGENTS.md` first for project intent and tech stack. Use roles from `.agents/roles/` or `.claude/agents/`. Reusable skills live in `.claude/skills/`.',
    '',
    'Regenerate adapters: `node bin/create-preset.mjs sync --target claude`',
    ''
  ].join('\n');
  results.push(writeFileSafe(claudeMdPath, claudeMdContent, { dryRun, force }));

  // Skills
  const activeSkillNames = skills.map(s => s.name);
  if (clean && fs.existsSync(skillsDestDir)) {
    for (const entry of fs.readdirSync(skillsDestDir, { withFileTypes: true })) {
      if (entry.isDirectory() && !activeSkillNames.includes(entry.name)) {
        const staleDir = path.join(skillsDestDir, entry.name);
        if (!dryRun) fs.rmSync(staleDir, { recursive: true, force: true });
        results.push({ status: 'removed_stale', path: staleDir });
      }
    }
  }

  for (const skill of skills) {
    const destSkill = path.join(skillsDestDir, skill.name);
    results.push(...copyDirectorySafe(skill.directory, destSkill, { dryRun, force, managed: true }));
  }

  return results;
}

function generateCodex({ targetDir, roles, dryRun, force }) {
  const results = [];
  const agentsDir = path.join(targetDir, '.codex', 'agents');

  for (const role of roles) {
    const filePath = path.join(agentsDir, `${role.name}.toml`);
    const instructions = [
      GENERATOR_HEADER,
      '',
      role.content
    ].join('\n');

    const content = [
      `name = ${escapeTomlString(role.name)}`,
      `description = ${escapeTomlString(role.description)}`,
      '',
      "developer_instructions = '''",
      instructions,
      "'''",
      ''
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  return results;
}

function generateOpenCode({ targetDir, roles, skills, overlays, dryRun, force, clean }) {
  const results = [];
  const agentsDir = path.join(targetDir, '.opencode', 'agents');
  const skillsDestDir = path.join(targetDir, '.opencode', 'skills');

  for (const role of roles) {
    const filePath = path.join(agentsDir, `${role.name}.md`);
    const content = [
      '---',
      `name: ${role.name}`,
      `description: ${escapeYamlString(role.description)}`,
      'mode: subagent',
      'permission:',
      '  edit: allow',
      '  bash: ask',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      role.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  for (const overlay of overlays) {
    const filePath = path.join(agentsDir, `${overlay.name}.md`);
    const content = [
      '---',
      `name: ${overlay.name}`,
      `description: ${escapeYamlString(overlay.description)}`,
      'mode: primary',
      'permission:',
      '  edit: deny',
      '  bash: ask',
      '---',
      '',
      GENERATOR_HEADER,
      '',
      overlay.content
    ].join('\n');
    results.push(writeFileSafe(filePath, content, { dryRun, force }));
  }

  // Safe merge of opencode.json without clobbering existing configuration
  const opencodeJsonPath = path.join(targetDir, 'opencode.json');
  const baseInstructions = [
    'AGENTS.md',
    '.agents/README.md',
    '.agents/overlays/README.md',
    '.agents/tools/context-policy.md',
    '.agents/tools/verification-policy.md'
  ];
  results.push(safeMergeJson(opencodeJsonPath, {
    $schema: 'https://opencode.ai/config.json',
    instructions: baseInstructions
  }, { dryRun }));

  // Skills
  const activeSkillNames = skills.map(s => s.name);
  if (clean && fs.existsSync(skillsDestDir)) {
    for (const entry of fs.readdirSync(skillsDestDir, { withFileTypes: true })) {
      if (entry.isDirectory() && !activeSkillNames.includes(entry.name)) {
        const staleDir = path.join(skillsDestDir, entry.name);
        if (!dryRun) fs.rmSync(staleDir, { recursive: true, force: true });
        results.push({ status: 'removed_stale', path: staleDir });
      }
    }
  }

  for (const skill of skills) {
    const destSkill = path.join(skillsDestDir, skill.name);
    results.push(...copyDirectorySafe(skill.directory, destSkill, { dryRun, force, managed: true }));
  }

  return results;
}

function generateAntigravity({ templateRoot, targetDir, profile, roles, skills, dryRun, force }) {
  const results = [];

  // Antigravity directly references canonical AGENTS.md, .agents/roles, and .agents/skills
  const geminiMdPath = path.join(targetDir, 'GEMINI.md');
  const geminiMdContent = [
    '# Google Gemini & Antigravity Project Instructions',
    '',
    GENERATOR_HEADER,
    '',
    'Read `AGENTS.md` first. Use roles from `.agents/roles/`. Use standalone skills from `.agents/skills/`. Overlays: Mentor and Coach in `.agents/overlays/`.',
    '',
    `Active Profile: ${profile.name} (${profile.description})`,
    '',
    'Regenerate adapters: `node bin/create-preset.mjs sync --target antigravity`',
    ''
  ].join('\n');
  results.push(writeFileSafe(geminiMdPath, geminiMdContent, { dryRun, force }));

  return results;
}

function installSharedAssets({ templateRoot, targetDir, profile, roles, skills, overlays, dryRun, force }) {
  const results = [];
  const copyFile = (relativePath, managed = false) => {
    const source = path.join(templateRoot, relativePath);
    if (!fs.existsSync(source)) return;
    const content = fs.readFileSync(source, 'utf8');
    const writer = managed ? writeManagedFileSafe : writeFileSafe;
    results.push(writer(path.join(targetDir, relativePath), content, { dryRun, force }));
  };
  const copyManagedDir = (sourceRelative, destRelative = sourceRelative) => {
    results.push(...copyDirectorySafe(
      path.join(templateRoot, sourceRelative),
      path.join(targetDir, destRelative),
      { dryRun, force, managed: true }
    ));
  };

  // Project-owned onboarding files are created once. Subsequent user edits are preserved.
  copyFile('AGENTS.md');
  copyFile('preset.config.json');
  copyManagedDir('.agents/tools');
  copyManagedDir('.ai/maps');
  copyFile('.ai/context-routing.md', true);
  results.push(...copyDirectorySafe(
    path.join(templateRoot, 'docs'),
    path.join(targetDir, 'docs'),
    { dryRun, force }
  ));

  for (const role of roles) {
    copyFile(path.join('.agents', 'roles', role.fileName), true);
  }
  if (profile.roles.includes('backend-database-engineer')) {
    copyManagedDir('.agents/roles/playbooks/backend');
  }
  if (profile.roles.includes('devops-engineer')) {
    copyManagedDir('.agents/roles/playbooks/devops');
  }
  for (const skill of skills) {
    copyManagedDir(
      path.relative(templateRoot, skill.directory),
      path.join('.agents', 'skills', skill.name)
    );
  }
  for (const overlay of overlays) {
    copyFile(path.join('.agents', 'overlays', overlay.fileName), true);
  }
  for (const workflow of profile.workflows || []) {
    copyFile(path.join('.agents', 'workflows', `${workflow}.md`), true);
  }

  return results;
}
