# CI

Two workflows, both written for Forgejo Actions.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `workflows/integrate.yaml` | pull requests, merge queue, manual | Analysis, tests, and debug builds for the platforms a change can affect |
| `workflows/release.yaml` | `v*` tags, manual | Signed APK, Linux tarball, AppImage, web bundle, and the Forgejo release |

## Layout

Workflows stay thin. Everything they do lives in one of two places:

- `.github/actions/*/action.yml` — composite actions for shared setup. Each
  third-party action version is pinned in exactly one of these files.
- `scripts/ci/*.sh` — the actual logic, runnable outside CI.

The Flutter version is pinned in `.tool_versions.yaml`, which
`subosito/flutter-action` reads directly. Everything else is pinned in
`workflows/versions.env` and sourced into `$GITHUB_ENV` by the composite
actions.

Every job starts with a small inline step that installs Node 24 if the runner
image only ships Node 20. It cannot be a script, because it has to run before
`actions/checkout`. Recent versions of the actions used here declare
`runs.using: node24`; if a runner rejects that outright, pin
`actions/checkout` back to `v4` and the other actions to their last Node 20
release.

Actions are pinned to their newest major with one exception:
`actions/download-artifact` stays on `v7`. Its `v8` errors on any artifact
digest mismatch and inspects `Content-Type` before unzipping, and Forgejo's
artifact server is not guaranteed to satisfy either.

## Secrets

Only the release workflow reads secrets. All of them are optional except when
building a release APK.

| Secret | Purpose |
| --- | --- |
| `KEYSTORE_FILE` | Base64-encoded release keystore |
| `KEYSTORE_PASS` | Keystore password |
| `KEY_PASS` | Key password |
| `KEY_ALIAS` | Key alias, defaults to `key` |
| `RELEASE_TOKEN` | Forgejo token used to create the release and upload assets |

## Variables

Jobs that need a runner not present in every installation are opt-in, so a
missing runner skips the job instead of blocking a pull request.

| Variable | Set to `true` when you have |
| --- | --- |
| `ENABLE_ARM64_RUNNER` | A self-hosted Linux arm64 runner |
| `ENABLE_MACOS_RUNNER` | A macOS runner for the iOS build |

## Releases

Pushing a `v*` tag builds everything and publishes it. A tag with a suffix
(`v1.2.3-rc1`) is marked as a prerelease; a plain `v1.2.3` must match the
version in `pubspec.yaml` or the run fails early.

The release body comes from the matching `CHANGELOG.md` section. Assets are
uploaded to a draft, which is only published once every upload succeeded, and
`SHA256SUMS.txt` is generated alongside them.

Use the manual trigger to rehearse: it builds artifacts without publishing
unless `publish` is checked, and `draft` keeps the result unpublished.
