/**
 * Self-hosted Renovate runner config (GitHub Actions in this repo).
 *
 * Target repos keep extending github>dudziakm/dep-automation(:js|:jvm|:mixed|:automerge).
 * This file only controls which repositories the runner discovers and processes.
 *
 * 2026-09-01: owner re-permitted 10xdevs / compass / cards / rules. Discover
 * every dudziakm/* repo that has renovate.json (requireConfig: required).
 */

/** @type {import('renovate/dist/config/types').AllConfig} */
module.exports = {
  platform: 'github',
  onboarding: false,
  requireConfig: 'required',
  persistRepoData: false,
  gitAuthor: 'Renovate Bot <renovate@whitesourcesoftware.com>',

  autodiscover: true,
  autodiscoverFilter: ['dudziakm/*'],

  forkProcessing: 'disabled',
  dependencyDashboard: true,
};

// Optional dry-run from the workflow (RENOVATE_WORKFLOW_DRY_RUN=true).
// Left unset for scheduled / live runs so Renovate creates PRs and dashboards.
if (process.env.RENOVATE_WORKFLOW_DRY_RUN === 'true') {
  module.exports.dryRun = 'full';
}
