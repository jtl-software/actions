# jtl-software/actions

Shared GitHub Actions composite actions and reusable workflows for JTL repositories that must be callable from **public** consumer repositories.

This is the public-visibility counterpart to the internal `jtl-software/jtl-platform-gh-workflows`. GitHub only allows reusable workflows and composite actions to be referenced across repositories when the source repository is `public` or `internal`. Public consumers (e.g. `jtl-software/connector-prestashop`, `jtl-software/connector-woocommerce3`) cannot pull from `internal` sources, so anything they need lives here.

Consumers reference public artefacts via:

- `uses: jtl-software/actions/.github/actions/<name>@<ref>` (composite actions)
- `uses: jtl-software/actions/.github/workflows/<name>.yaml@<ref>` (reusable workflows)

## Naming conventions

- **No prefix** - public API, safe to reference from any external repository
- **Underscore prefix (`_`)** - internal to this repository (e.g. `_lint.yaml`, `_test-auto-draft-pr.yaml`); not part of the public API

## Repository structure

```
.github/
  actions/<name>/       # Composite actions - public API
    action.yaml
    *.sh / *.ps1        # Helper scripts called by the action
  workflows/
    <name>.yaml         # Public reusable workflows
    _lint.yaml          # Internal: actionlint
    _test-*.yaml        # Internal: integration tests per public artefact
docs/
  <name>.md             # Full documentation per public action/workflow
workflow-templates/
  <name>.yaml           # Example consumer workflows
```

## Languages and idioms

Helper scripts in this repository may be **bash** or **PowerShell**. Choose per artefact based on what the workflow already needs and what runs cleanest on the target runners.

- Bash: enforce `set -euo pipefail`, must pass shellcheck via `_lint.yaml`.
- PowerShell: target `pwsh` (PowerShell 7+, preinstalled on GitHub-hosted runners). Always set:
  ```powershell
  $ErrorActionPreference = 'Stop'
  $PSNativeCommandUseErrorActionPreference = $true
  ```
  Use built-in cmdlets and operators (`[uri]::EscapeDataString`, `-match`, `$Matches`, `Write-Host`) over external tools where possible. No `Read-Host`, no interactive prompts.

## How the auto-draft-pr reusable workflow works

`.github/workflows/auto-draft-pr.yaml` - reusable workflow (`on: workflow_call`). Opens a draft PR when a feature branch is pushed (GitLab auto-MR parity). The caller controls the `on: push` filters; the reusable workflow declares its own permissions, `if:` guard against the default branch, and the full PowerShell logic inline.

Key behaviour:

- **Idempotent:** checks `gh pr list` first; re-pushes to the same branch do not create duplicate PRs.
- **Protected branches:** skipped via `gh api repos/<repo>/branches/<branch> --jq '.protected'` (GitLab parity for the `CI_COMMIT_REF_PROTECTED == "true"` rule).
- **PR title:** if the head commit subject matches `^(title|titel):\s*.+` (case-insensitive), the part after the prefix becomes the title; otherwise the title is `Draft: <branch-name>`.
- **Permissions fixed in the workflow:** `contents: read`, `pull-requests: write`, `issues: write`. Caller does not need to set them.

## Adding a new reusable workflow

1. Create `.github/workflows/<name>.yaml` (no underscore prefix for public workflows).
2. Add an integration test workflow `.github/workflows/_test-<name>.yaml`.
3. Add documentation to `docs/<name>.md`.
4. Mention the new workflow in `README.md`.

## Adding a new composite action

1. Create `.github/actions/<name>/action.yaml`.
2. Add helper scripts in the same directory (shellcheck for `.sh`, syntax-clean pwsh for `.ps1`).
3. Add an integration test workflow `.github/workflows/_test-<name>.yaml`.
4. Add documentation to `docs/<name>.md`.
5. Mention the new action in `README.md`.

## Versioning

Public artefacts are referenced by `@main` (latest), `@v1` / `@v2` (rolling major-version tags), or `@<sha>` (exact pin). Production callers should pin to `@<sha>` and let dependabot bump the pin.

## Releases

Tag-driven via `.github/workflows/_release.yaml`. Pushing a `v*` tag triggers `softprops/action-gh-release` with `generate_release_notes: true` (PRs since the previous release, grouped by label according to `.github/release.yml`) and force-updates the rolling major tag (`v1`, `v2`, ...) for strict SemVer tags. Pre-release tags (`vX.Y.Z-rc.N`, `vX.Y.Z-beta.N`) are detected by the hyphen, marked as pre-release, and do not roll the major tag.

Tag bump and Push are manual:

```bash
git tag v1.2.3
git push origin v1.2.3
```

PRs should carry one of the changelog labels (`enhancement`, `bug`, `breaking-change`, `documentation`, `chore`, `dependencies`, ...) so the auto-generated notes group them correctly. PRs without a recognised label fall into the "Other Changes" section.
