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
`subosito/flutter-action` reads directly. The JDK and yq versions live in
`workflows/versions.env` and are sourced into `$GITHUB_ENV` by the composite
actions.

No Android API level appears anywhere in CI. `compileSdk` follows
`flutter.compileSdkVersion`, so the Gradle plugin downloads the platform and
build-tools that the pinned Flutter asks for; CI only accepts the licences and
preinstalls the NDK revision it reads from `android/app/build.gradle.kts`. The
Android SDK cache is keyed on the Flutter and NDK versions, so bumping Flutter
rebuilds it.

Every job starts with a small inline step that installs Node 24 if the runner
image only ships Node 20. It cannot be a script, because it has to run before
`actions/checkout`. Recent versions of the actions used here declare
`runs.using: node24`; if a runner rejects that outright, pin
`actions/checkout` back to `v4` and the other actions to their last Node 20
release.

## Forgejo specifics

**Artifacts must come from Forgejo's fork.** `actions/upload-artifact` and
`actions/download-artifact` v4+ abort on a hard "not running against
GitHub.com" check with no fallback, so both are taken from
`data.forgejo.org/forgejo/…@v4`, which is that check removed and nothing else.
Cross-run downloads (`run-id` / `github-token`) fall back to a REST API Forgejo
does not implement, so those inputs must stay unused.

**`actions/cache` needs no fork.** It resolves the cache service by treating a
non-GitHub `GITHUB_SERVER_URL` as GHES and falling back to the legacy API,
which is exactly what the Forgejo runner serves, so the newest major works.

**The runner tool cache does not survive a job.** Since runner 5.0.1 the
`/opt/hostedtoolcache` directory is per-job by design, so `setup-java` would
re-download the JDK every run. The Android setup action caches that directory
itself. Baking the tools into a custom runner image is the alternative.

**Verifying the cache actually works.** A disabled or unreachable cache server
only produces a warning, and the build carries on rebuilding everything. Every
job therefore runs `scripts/ci/check-cache.sh`, which reports both cases; set
`CACHE_REQUIRED=true` to make them fail instead. If it warns, the runner needs
`cache.enabled`, and containerised runners also need `cache.host` and
`cache.proxy_port` pointing at an address the job container can reach.

## Secrets

Only the release workflow reads secrets.

| Secret | Purpose |
| --- | --- |
| `KEYSTORE_FILE` | Base64-encoded release keystore |
| `KEYSTORE_PASS` | Keystore password |
| `KEY_PASS` | Key password |
| `KEY_ALIAS` | Key alias, defaults to `key` |
| `RELEASE_TOKEN` | Forgejo token used to create the release and upload assets |

If Android signing secrets are all missing, CI falls back to the repository
fixture `scripts/ci/debug-signing-keystore.p12.base64` (`androiddebugkey` /
`android`) so release-flavor APK builds still run for test workflows with a
stable certificate across runs. If any one of `KEYSTORE_FILE`,
`KEYSTORE_PASS`, `KEY_PASS` is set, all three must be set.

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
