# ![JTL logo](https://avatars.githubusercontent.com/u/31404730?s=25&v=4) JTL Public GitHub Workflows

Shared GitHub Actions composite actions and reusable workflows for JTL repositories that need to be referenced from **public** repositories.

This repository is the public-visibility counterpart to the internal `jtl-software/jtl-platform-gh-workflows`. GitHub only allows public repositories to consume reusable workflows and composite actions from `public` or `internal` source repositories. Anything that must be callable from a public repo (for example `connector-prestashop`, `connector-woocommerce3`) lives here.

## Naming Convention

- **No prefix** - public API, safe to reference from any repository
- **Underscore prefix (`_`)** - internal to this repository (CI, integration tests), not part of the public API and may change without notice

## Repository Structure

```
.github/
  actions/<name>/             # Composite actions - public API
    action.yaml
    *.sh / *.ps1              # Helper scripts called by the action
  workflows/
    <name>.yaml               # Public reusable workflows
    _lint.yaml                # Internal: actionlint on PRs
    _test-<name>.yaml         # Internal: integration tests for each public artefact
docs/
  <name>.md                   # Full documentation per public action or workflow
workflow-templates/
  <name>.yaml                 # Example consumer workflows
```

## Reusable Workflows

### Auto draft PR

Opens a draft pull request when a feature branch is pushed (GitLab auto-MR parity for repositories that migrated from GitLab to GitHub). Idempotent: re-pushes to the same branch do not create duplicates.

**Usage:**

```yaml
name: Auto draft PR
on:
  push:
    branches-ignore:
      - master
      - main
      - '**/gh-readonly-queue/**'
    tags-ignore:
      - '**'

jobs:
  draft-pr:
    uses: jtl-software/jtl-public-gh-workflows/.github/workflows/auto-draft-pr.yaml@v1
```

The reusable workflow declares its own `permissions:`, `if:` guard against the default branch, and `runs-on:`. The caller only supplies the trigger.

## Versioning

Actions and workflows are referenced by:

- `@main` - latest version (not recommended for production)
- `@v1` / `@v2` - rolling major-version tags (auto-updated to the latest compatible release)
- `@<commit-sha>` - exact pin (recommended for production callers; let dependabot bump the pin)

Recommended consumer pattern:

```yaml
uses: jtl-software/jtl-public-gh-workflows/.github/workflows/auto-draft-pr.yaml@<sha> # v1.0.0
```

## Releasing

Releases are tag-driven. Pushing a tag matching `v*` triggers
`.github/workflows/release.yaml`, which creates the GitHub Release with
auto-generated notes (PRs since the previous release, grouped by label
according to `.github/release.yml`) and force-updates the rolling major
tag (`v1`, `v2`, ...) for strict SemVer releases.

Steps:

```bash
# Bump the version in your head, then:
git tag v1.2.3
git push origin v1.2.3
```

Or, if you also want the GitHub Release created from the local CLI rather than
waiting for the workflow:

```bash
gh release create v1.2.3 --generate-notes
```

(The workflow runs idempotently in either case.)

Pre-release tags (`v1.0.0-rc.1`, `v2.0.0-beta.3`, ...) are detected by the
hyphen, marked as pre-release, and do **not** roll the major tag.

PRs should carry one of the labels listed in `.github/release.yml`
(`enhancement`, `bug`, `breaking-change`, `documentation`, `chore`,
`dependencies`, ...) so the auto-generated notes group them under the right
heading.

## Testing

- **`_lint.yaml`** runs actionlint (and shellcheck when `.sh` files exist) on every push and PR.
- **`_test-<name>.yaml`** integration tests cover each public action/workflow with mocked CLIs where appropriate.

## Contributing

### Adding a Reusable Workflow

1. Create `.github/workflows/<name>.yaml` (no underscore prefix for public workflows).
2. Add an integration test workflow `.github/workflows/_test-<name>.yaml`.
3. Add documentation to `docs/<name>.md`.
4. Mention the new workflow in this README.

### Adding a Composite Action

1. Create `.github/actions/<name>/action.yaml`.
2. Add helper scripts in the same directory (shell scripts must pass shellcheck; PowerShell scripts must pass PSScriptAnalyzer where applicable).
3. Add an integration test workflow `.github/workflows/_test-<name>.yaml`.
4. Add documentation to `docs/<name>.md`.
5. Mention the new action in this README.
