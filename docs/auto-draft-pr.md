# Reusable workflow: `auto-draft-pr.yaml`

Opens a draft pull request when a feature branch is pushed. Reproduces the GitLab "auto-MR" pattern for repositories that migrated from GitLab to GitHub.

## Usage

The caller controls only the `on:` trigger. The reusable workflow declares its own permissions, default-branch guard, runner, and Bash implementation; the caller does not pass inputs or secrets.

```yaml
# .github/workflows/auto-draft-pr.yaml in the consumer repo
name: Auto draft PR

on:
  push:
    branches-ignore:
      - main
      - master
      - '**/gh-readonly-queue/**'
    tags-ignore:
      - '**'

jobs:
  draft-pr:
    uses: jtl-software/actions/.github/workflows/auto-draft-pr.yaml@v1
```

Pin to a SHA in production callers; let dependabot bump the pin.

## Behaviour

| Aspect | Detail |
|---|---|
| Trigger | Caller-defined; the reusable workflow runs as a single job in `draft-pr` |
| Default branch guard | Job has `if: github.ref_name != github.event.repository.default_branch`. A push that lands on the default branch results in a skipped job, no PR. |
| Protected branch guard | The script queries `gh api repos/<repo>/branches/<branch>` and exits 0 if `.protected` is `true`, mirroring the GitLab `CI_COMMIT_REF_PROTECTED` rule. |
| PR title | If the head commit's first line matches `^(title\|titel):\s*(.+)$` (case-insensitive), the captured remainder becomes the title. Otherwise: `Draft: <branch-name>`. |
| Idempotency | The script queries `gh pr list --head <branch> --base <default> --state open` first. If a matching PR exists, it skips with a log line — re-pushes don't create duplicates. |
| Assignee | The PR is assigned to `${{ github.actor }}` (the user who pushed the commit). |
| Body | Rendered as `_Auto-drafted on push to ` `` `<branch>` `` `. Replace this body with details before requesting review._` |

## Permissions

Declared at job level inside the reusable workflow; the caller does not need to set anything:

- `contents: read`
- `pull-requests: write` (open the PR)
- `issues: write` (required by `gh pr create --assignee`)

## Runner

`ubuntu-latest` with Bash.

## Testing

`.github/workflows/_test-auto-draft-pr.yaml` exercises four cases against a mocked `gh` CLI:

- Protected branch → skip
- Existing PR for the same head/base → skip
- `Titel:` prefix in commit subject → title is the trimmed remainder
- No prefix → title is `Draft: <branch>`

The mock `gh` binary is set up by `.github/scripts/auto-draft-pr/ghmock.sh`. The tests call `.github/scripts/auto-draft-pr/open-draft-pr.sh` directly, which is the same script the reusable workflow calls in production — there is no mirror file or drift-detection job.
