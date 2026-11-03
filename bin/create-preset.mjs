#!/usr/bin/env node

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generatePreset } from '../lib/generator.mjs';
import { validateTemplate } from '../lib/validator.mjs';
import { measureTokens, formatMeasureReport } from '../lib/measure.mjs';
import { loadConfig } from '../lib/profiles.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const templateRoot = path.resolve(__dirname, '..');

function printHelp() {
  console.log(`
AI Project Structure Template Preset CLI

Usage:
  create-preset <provider> [options]
  create-preset sync [options]
  create-preset validate [options]
  create-preset measure [options]

Providers:
  cursor        Cursor IDE rules (.cursor/rules/*.mdc) and skills (.cursor/skills/)
  antigravity   Antigravity & Gemini instructions (AGENTS.md, GEMINI.md)
  claude        Claude Code agents (.claude/agents/*.md), skills, and CLAUDE.md
  codex         Codex agent manifests (.codex/agents/*.toml) and AGENTS.md
  opencode      OpenCode subagents (.opencode/agents/*.md) and opencode.json

Profiles:
  fullstack     (default) Software Engineer, Frontend, Backend, Architect, SQA, Docs
  general       General Software Engineer & System Architect with coding/review skills
  qa            SQA Engineer with test creation, automation, execution, and RCA
  architecture  System Architect & Security Engineer with planning and investigation
  docs          Technical Documentation Specialist with documentation workflows
  all           All 9 roles, all 13 skills, all overlays, and all SDLC workflows

Options:
  --profile <name>   Select capability profile (default: fullstack)
  --into <dir>       Target installation directory (default: current directory)
  --target <name>    Target provider for sync (default: all)
  --task <name>      Check if context is fulfilled for a specific task (api, database, deployment, testing)
  --dry-run          Preview file operations without modifying disk
  --clean            Remove stale unmanaged skills/rules during generation
  --force            Force overwrite non-managed files
  --help, -h         Show this help message

Examples:
  node bin/create-preset.mjs cursor --profile fullstack
  node bin/create-preset.mjs claude --profile qa --into ../my-repo
  node bin/create-preset.mjs codex --profile all
  node bin/create-preset.mjs sync --target all
  node bin/create-preset.mjs validate --task database
  node bin/create-preset.mjs measure
`);
}

function parseArgs(args) {
  const parsed = {
    command: null,
    provider: null,
    profile: 'fullstack',
    into: process.cwd(),
    target: 'all',
    task: null,
    dryRun: false,
    clean: false,
    force: false,
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
    } else if (arg === '--dry-run') {
      parsed.dryRun = true;
    } else if (arg === '--clean') {
      parsed.clean = true;
    } else if (arg === '--force') {
      parsed.force = true;
    } else if (arg === '--profile' && i + 1 < args.length) {
      parsed.profile = args[++i];
    } else if (arg === '--into' && i + 1 < args.length) {
      parsed.into = path.resolve(args[++i]);
    } else if (arg === '--target' && i + 1 < args.length) {
      parsed.target = args[++i];
    } else if (arg === '--task' && i + 1 < args.length) {
      parsed.task = args[++i];
    } else if (!parsed.command) {
      parsed.command = arg;
    }
  }

  return parsed;
}

async function main() {
  const rawArgs = process.argv.slice(2);
  if (rawArgs.length === 0) {
    printHelp();
    process.exit(0);
  }

  const args = parseArgs(rawArgs);

  if (args.help) {
    printHelp();
    process.exit(0);
  }

  const config = loadConfig(templateRoot);
  const knownProviders = config.providers;

  // If command is a known provider, treat as create-preset <provider>
  if (knownProviders.includes(args.command)) {
    args.provider = args.command;
    args.command = 'create-preset';
  }

  try {
    switch (args.command) {
      case 'create-preset': {
        if (!args.provider) {
          console.error('Error: Please specify a provider (cursor, antigravity, claude, codex, opencode)');
          process.exit(1);
        }

        console.log(`\n🚀 Generating preset for ${args.provider.toUpperCase()} [profile: ${args.profile}]...`);
        if (args.dryRun) console.log('🔍 DRY RUN: No files will be modified.');

        const result = generatePreset({
          templateRoot,
          targetDir: args.into,
          provider: args.provider,
          profile: args.profile,
          dryRun: args.dryRun,
          force: args.force,
          clean: args.clean
        });

        console.log(`\nGenerated ${result.results.length} item(s):`);
        for (const item of result.results) {
          const rel = path.relative(args.into, item.path);
          console.log(`  [${item.status}] ${rel}`);
        }
        console.log(`\n✨ Preset successfully configured for ${args.provider} in ${args.into}\n`);
        break;
      }

      case 'sync': {
        console.log(`\n🔄 Syncing adapters [target: ${args.target}]...`);
        const targets = args.target === 'all' ? knownProviders : [args.target];

        for (const t of targets) {
          console.log(`\n--- Syncing ${t} ---`);
          const result = generatePreset({
            templateRoot,
            targetDir: args.into,
            provider: t,
            profile: args.profile,
            dryRun: args.dryRun,
            force: args.force,
            clean: args.clean
          });
          for (const item of result.results) {
            const rel = path.relative(args.into, item.path);
            console.log(`  [${item.status}] ${rel}`);
          }
        }
        console.log('\n✨ Adapter synchronization complete.\n');
        break;
      }

      case 'validate': {
        console.log(`\n🔎 Validating AI project structure and context in ${args.into}...`);
        const validation = validateTemplate(args.into, { task: args.task });

        if (validation.passed.length > 0) {
          console.log(`\n✅ ${validation.passed.length} check(s) passed:`);
          for (const p of validation.passed.slice(0, 15)) {
            console.log(`  ✔ ${p}`);
          }
          if (validation.passed.length > 15) {
            console.log(`  ... and ${validation.passed.length - 15} more checks.`);
          }
        }

        if (validation.warnings.length > 0) {
          console.log(`\n⚠️  ${validation.warnings.length} warning(s):`);
          for (const w of validation.warnings) {
            console.log(`  ⚠ ${w}`);
          }
        }

        if (validation.errors.length > 0) {
          console.error(`\n❌ Validation FAILED with ${validation.errors.length} error(s):`);
          for (const err of validation.errors) {
            console.error(`  ✖ ${err}`);
          }
          process.exit(1);
        } else {
          console.log('\n✨ Validation PASSED successfully!\n');
        }
        break;
      }

      case 'measure': {
        const report = measureTokens(args.into, { profile: args.profile });
        console.log(formatMeasureReport(report));
        break;
      }

      default:
        console.error(`Unknown command: '${args.command}'`);
        printHelp();
        process.exit(1);
    }
  } catch (err) {
    console.error(`\n❌ Error: ${err.message}\n`);
    process.exit(1);
  }
}

main();
