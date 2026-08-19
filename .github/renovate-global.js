/**
 * Self-hosted Renovate runner config (GitHub Actions in this repo).
 *
 * Target repos keep extending github>dudziakm/dep-automation(:js|:jvm|:mixed|:automerge).
 * This file only controls which repositories the runner discovers and processes.
 *
 * HARD EXCLUSION (owner policy 2026-08-18 — do not weaken without explicit re-permit):
 *   ai-concept-compass, ai-concept-compass-greenfield, 10xCardsAstro,
 *   my10xCards, ai-rules-builder
 * Plus belt-and-suspenders globs for *10x* / *cards* / *concept* / *rules*.
 * Keep in sync with EXCLUDED-REPOS.txt and docs/OWNER-RENOVATE-CHECKLIST.md.
 */

const FROZEN_REPOS = [
  'dudziakm/ai-concept-compass',
  'dudziakm/ai-concept-compass-greenfield',
  'dudziakm/10xCardsAstro',
  'dudziakm/my10xCards',
  'dudziakm/ai-rules-builder',
];

/** @type {import('renovate/dist/config/types').AllConfig} */
module.exports = {
  platform: 'github',
  onboarding: false,
  requireConfig: 'required',
  persistRepoData: false,
  gitAuthor: 'Renovate Bot <renovate@whitesourcesoftware.com>',

  autodiscover: true,
  // Positive match + exact deny + name-token deny. Negatives are ANDed with positives
  // (Renovate >= 40). A filter mistake alone must not reach the frozen repos —
  // packageRules below is the second belt.
  autodiscoverFilter: [
    'dudziakm/*',
    ...FROZEN_REPOS.map((r) => `!${r}`),
    '!dudziakm/*10x*',
    '!dudziakm/*cards*',
    '!dudziakm/*concept*',
    '!dudziakm/*rules*',
  ],

  forkProcessing: 'disabled',
  dependencyDashboard: true,

  // Belt-and-suspenders: if a frozen repo ever slipped past autodiscoverFilter,
  // disable every update there.
  packageRules: [
    {
      description:
        'Hard deny frozen repos (owner policy 2026-08-18). Do not remove.',
      matchRepositories: FROZEN_REPOS,
      enabled: false,
    },
  ],
};

// Optional dry-run from the workflow (RENOVATE_WORKFLOW_DRY_RUN=true).
// Left unset for scheduled / live runs so Renovate creates PRs and dashboards.
if (process.env.RENOVATE_WORKFLOW_DRY_RUN === 'true') {
  module.exports.dryRun = 'full';
}
