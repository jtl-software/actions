# _release.yaml

Internal workflow that runs on every `v*` tag push. Not callable from external repositories.

## What it does

Two sequential jobs:

1. **`create-release`** - Creates a GitHub Release for the pushed tag using [`softprops/action-gh-release`](https://github.com/softprops/action-gh-release). Release notes are auto-generated from merged PRs since the previous release, grouped by label according to `.github/release.yml`.

2. **`update-major-tag`** - Force-moves the rolling major-version tag (`v1`, `v2`, ...) to the same commit as the release tag, so consumers pinned to `@v1` automatically receive every compatible release without updating their reference. Skipped for pre-release tags (any tag containing a hyphen, e.g. `v1.0.0-rc.1`).

## Trigger

```yaml
on:
  push:
    tags:
      - 'v*'
```

Both full releases (`v1.2.3`) and pre-releases (`v1.2.3-rc.1`) trigger the workflow. The `create-release` job runs for all tags; `update-major-tag` runs only for strict SemVer tags without a hyphen.

## Release process

```bash
git tag v1.2.3
git push origin v1.2.3
```

Or via the `gh` CLI, which also creates the release directly:

```bash
gh release create v1.2.3 --generate-notes
```

When `gh release create` is used, the workflow fires a second time and idempotently overwrites the release notes - which is harmless.

## Pre-release tags

Any tag containing a hyphen is treated as a pre-release: it gets a GitHub Release marked as pre-release and excluded from "latest release" promotion. The rolling major tag is not moved.

Examples: `v1.0.0-rc.1`, `v2.0.0-beta.3`.

## Changelog labels

PRs are grouped in the auto-generated release notes by their labels. See `.github/release.yml` for the category configuration.

| Label | Category |
|---|---|
| `breaking-change`, `semver-major` | Breaking Changes |
| `enhancement`, `feature`, `semver-minor` | Features |
| `bug`, `bugfix`, `semver-patch` | Bug Fixes |
| `documentation`, `docs` | Documentation |
| `chore`, `dependencies`, `github-actions` | Maintenance |
| `skip-changelog` | Excluded |
| (no matching label) | Other Changes |

## Implementation notes

The `update-major-tag` job delegates to `.github/scripts/_release/update-major-tag.sh`. The script uses the GitHub REST API (`gh api`) rather than `git push --force`, which avoids the need for a full repository checkout with credentials and eliminates the git identity configuration boilerplate.

Tags created by `gh release create` are annotated tag objects; the script peels the object to find the underlying commit SHA before writing the major tag.
