import fs from 'node:fs';
import path from 'node:path';

export function loadConfig(rootDir) {
  const configPath = path.join(rootDir, 'preset.config.json');
  if (!fs.existsSync(configPath)) {
    throw new Error(`preset.config.json not found in ${rootDir}`);
  }
  return JSON.parse(fs.readFileSync(configPath, 'utf8'));
}

export function getProfile(config, profileName = 'fullstack') {
  const profile = config.profiles[profileName];
  if (!profile) {
    const available = Object.keys(config.profiles).join(', ');
    throw new Error(`Unknown profile '${profileName}'. Available profiles: ${available}`);
  }
  return {
    name: profileName,
    ...profile
  };
}

export function parseRoleMetadata(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const nameMatch = content.match(/^- \*\*Name:\*\*\s*(.+?)\s*$/m);
  const roleMatch = content.match(/^- \*\*Role:\*\*\s*(.+?)\s*$/m);
  const descMatch = content.match(/^- \*\*Description:\*\*\s*(.+?)\s*$/m);

  if (!nameMatch || !descMatch) {
    throw new Error(`Missing metadata in role file: ${filePath}`);
  }

  const name = nameMatch[1].trim();
  const title = roleMatch ? roleMatch[1].trim() : name;
  const description = descMatch[1].trim();
  const fileName = path.basename(filePath);

  return {
    name,
    title,
    description,
    fileName,
    content: content.trim()
  };
}

export function parseSkillMetadata(skillDir) {
  const skillFile = path.join(skillDir, 'SKILL.md');
  if (!fs.existsSync(skillFile)) {
    throw new Error(`SKILL.md missing in ${skillDir}`);
  }
  const content = fs.readFileSync(skillFile, 'utf8');
  const fmMatch = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---/);
  if (!fmMatch) {
    throw new Error(`Frontmatter missing in ${skillFile}`);
  }

  const metadata = {};
  for (const line of fmMatch[1].split(/\r?\n/)) {
    const m = line.match(/^\s*([^:#]+):\s*(.*?)\s*$/);
    if (m) {
      metadata[m[1].trim()] = m[2].trim().replace(/^['"]|['"]$/g, '');
    }
  }

  if (!metadata.name) {
    metadata.name = path.basename(skillDir);
  }
  if (!metadata.description) {
    throw new Error(`Description missing in ${skillFile}`);
  }

  return {
    name: metadata.name,
    description: metadata.description,
    directory: skillDir,
    content: content.trim()
  };
}

export function parseOverlayMetadata(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const fileName = path.basename(filePath);
  const name = path.basename(filePath, path.extname(filePath));
  const headingMatch = content.match(/^#\s+(.+)$/m);
  const title = headingMatch ? headingMatch[1].trim() : name;

  return {
    name,
    title,
    description: `Overlay: ${name}. Changes response style, not work ownership.`,
    fileName,
    content: content.trim()
  };
}
