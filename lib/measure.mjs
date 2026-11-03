import fs from 'node:fs';
import path from 'node:path';
import { loadConfig, getProfile } from './profiles.mjs';

// Standard approximation: ~4 characters per token for source/markdown
export function estimateTokens(text) {
  if (!text) return 0;
  return Math.ceil(text.length / 4);
}

export function measureTokens(rootDir, options = {}) {
  const { provider = 'all', profile: profileName = 'all' } = options;
  const config = loadConfig(rootDir);
  const rolesDir = path.join(rootDir, '.agents', 'roles');
  const playbooksDir = path.join(rootDir, '.agents', 'roles', 'playbooks');

  const report = {
    roles: {},
    playbooks: {},
    profiles: {},
    cursorRuleOverhead: {}
  };

  // 1. Measure canonical roles
  const roleFiles = fs.readdirSync(rolesDir).filter(f => f.endsWith('.md') && f !== 'README.md');
  for (const file of roleFiles) {
    const rolePath = path.join(rolesDir, file);
    const content = fs.readFileSync(rolePath, 'utf8');
    const lines = content.split('\n').length;
    const tokens = estimateTokens(content);
    report.roles[file] = { lines, tokens };
  }

  // 2. Measure reference playbooks
  if (fs.existsSync(playbooksDir)) {
    const categories = fs.readdirSync(playbooksDir, { withFileTypes: true }).filter(d => d.isDirectory());
    for (const cat of categories) {
      const catDir = path.join(playbooksDir, cat.name);
      const pbFiles = fs.readdirSync(catDir).filter(f => f.endsWith('.md'));
      report.playbooks[cat.name] = {};
      for (const pb of pbFiles) {
        const pbContent = fs.readFileSync(path.join(catDir, pb), 'utf8');
        report.playbooks[cat.name][pb] = {
          lines: pbContent.split('\n').length,
          tokens: estimateTokens(pbContent)
        };
      }
    }
  }

  // 3. Measure profiles
  for (const [pName, pConfig] of Object.entries(config.profiles)) {
    let profileRoleTokens = 0;
    for (const rName of pConfig.roles) {
      const rFile = `${rName}.md`;
      if (report.roles[rFile]) {
        profileRoleTokens += report.roles[rFile].tokens;
      }
    }
    report.profiles[pName] = {
      roleCount: pConfig.roles.length,
      skillCount: pConfig.skills.length,
      baseTokens: profileRoleTokens
    };
  }

  // 4. Measure Cursor Rule Scoping Savings
  // Old style had globs: '**/*' which attached all rules (~100% of roles).
  // New style has alwaysApply: false without wildcard globs, saving auto-attached tokens.
  const cursorRulesDir = path.join(rootDir, '.cursor', 'rules');
  if (fs.existsSync(cursorRulesDir)) {
    const ruleFiles = fs.readdirSync(cursorRulesDir).filter(f => f.endsWith('.mdc'));
    let totalRuleTokens = 0;
    for (const rf of ruleFiles) {
      const rContent = fs.readFileSync(path.join(cursorRulesDir, rf), 'utf8');
      totalRuleTokens += estimateTokens(rContent);
    }
    report.cursorRuleOverhead = {
      totalRuleTokens,
      legacyAutoAttachedTokens: totalRuleTokens,
      optimizedAutoAttachedTokens: 0,
      savedPerFileEditTokens: totalRuleTokens
    };
  }

  return report;
}

export function formatMeasureReport(report) {
  const lines = [];
  lines.push('\n================ Token Efficiency & Budget Analysis ================\n');

  lines.push('### Role Context Footprint (Compact Cores):');
  lines.push('----------------------------------------------------------------------');
  lines.push('Role File                               Lines     Est. Tokens');
  lines.push('----------------------------------------------------------------------');
  for (const [file, data] of Object.entries(report.roles)) {
    const padFile = file.padEnd(38);
    const padLines = String(data.lines).padStart(6);
    const padTokens = String(data.tokens).padStart(14);
    lines.push(`${padFile}${padLines}${padTokens}`);
  }

  lines.push('\n### On-Demand Reference Playbooks (Loaded Only When Needed):');
  lines.push('----------------------------------------------------------------------');
  for (const [cat, pbs] of Object.entries(report.playbooks)) {
    lines.push(` [${cat}]`);
    for (const [pb, data] of Object.entries(pbs)) {
      const padFile = `  ${pb}`.padEnd(38);
      const padLines = String(data.lines).padStart(6);
      const padTokens = String(data.tokens).padStart(14);
      lines.push(`${padFile}${padLines}${padTokens}`);
    }
  }

  lines.push('\n### Profile Context Budgets:');
  lines.push('----------------------------------------------------------------------');
  lines.push('Profile       Roles   Skills    Combined Role Tokens');
  lines.push('----------------------------------------------------------------------');
  for (const [name, data] of Object.entries(report.profiles)) {
    const padName = name.padEnd(14);
    const padRoles = String(data.roleCount).padStart(5);
    const padSkills = String(data.skillCount).padStart(8);
    const padTokens = String(data.baseTokens).padStart(21);
    lines.push(`${padName}${padRoles}${padSkills}${padTokens}`);
  }

  if (report.cursorRuleOverhead.totalRuleTokens) {
    lines.push('\n### Cursor Rule Context Optimization:');
    lines.push('----------------------------------------------------------------------');
    lines.push(`- Legacy behavior with 'globs: **/*': ~${report.cursorRuleOverhead.legacyAutoAttachedTokens} tokens auto-attached per file edit.`);
    lines.push(`- Scoped behavior (on-demand):        ~${report.cursorRuleOverhead.optimizedAutoAttachedTokens} auto-attached tokens.`);
    lines.push(`- Context saved per chat interaction:  ~${report.cursorRuleOverhead.savedPerFileEditTokens} tokens saved!`);
  }

  lines.push('\n=====================================================================\n');
  return lines.join('\n');
}
