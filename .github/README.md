# CI

Core CI uses two Forgejo Actions workflows.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `workflows/integrate.yaml` | pull requests, merge queue, manual | Analysis, tests, and debug builds for the platforms a change can affect |
| `workflows/release.yaml` | `v*` tags, manual | Signed APKs, Linux tarballs and AppImages, web bundle, and the Forgejo release. Tag pushes build the full spread (every Android ABI, amd64 Linux, JS web); manual runs pick presets |

## Layout

Workflows stay thin. Everything they do lives in one of two places:

- `.github/actions/*/action.yml` — composite actions for shared setup and the
  platform builds themselves (`build-android-apk`, `build-linux-app`,
  `build-web-app`, plus their `setup-*` dependencies). Each third-party action
  version is pinned in exactly one of these files.
- `scripts/ci/*.sh` — the actual logic, runnable outside CI.

## One-shot / temporary Actions

All one-shot CI work uses **one workflow identity only**:

- workflow file: `.github/workflows/temp-action.yaml`
- workflow name: `Temporary Action`
- task body: `scripts/ci/temp-action.sh`

Do not add files such as `tmp-*.yaml`, `temporary-*.yaml`, `refresh-*.yaml`,
`*-patch.yaml`, or any other workflow for a single migration, formatter run,
lockfile refresh, patch, or verification. Reusing the same workflow path keeps
the Actions sidebar stable instead of permanently accumulating obsolete
workflow entries.

Each run is distinguished by its process metadata rather than by creating a new
workflow. `workflow_dispatch` records:

- `action_type` — `patch`, `format`, `dependency`, `migration`, `verification`,
  `maintenance`, or `other`;
- `purpose` — a short human-readable explanation of this particular run;
- `target_branch` — the branch that contains the temporary task body;
- whether the result should be committed and pushed.

The run title is always rendered as
`TEMP · <type> · <purpose> · <target branch>`, so task type and purpose remain
visible in the Actions run history while the workflow itself keeps the same
name.

### Temporary task procedure

1. Create or use the target work branch.
2. Replace only the task block between `TEMP ACTION BEGIN` and
   `TEMP ACTION END` in `scripts/ci/temp-action.sh`. Do not rename the script.
3. Commit that temporary script change to the target branch.
4. Dispatch **Temporary Action** and select the task type, purpose, target
   branch, and whether generated changes should be committed.
5. The workflow runs the fixed script path, validates the resulting diff, and
   refuses any modification under `.github/workflows`.
6. When `commit_changes` is enabled, the workflow restores
   `scripts/ci/temp-action.sh` from the default branch before committing the
   generated result. Task-specific CI code therefore does not survive in the
   branch's final tree.

Direct writes to the default branch are blocked unless
`allow_default_branch_write` is explicitly enabled. Concurrent temporary runs
are serialized per target branch. The baseline script is intentionally a no-op,
so accidentally dispatching the shared workflow without configuring a task does
not change the repository.

The Flutter version is pinned in `.tool_versions.yaml`, which
`subosito/flutter-action` reads directly. The JDK and yq versions live in
`workflows/versions.env` and are sourced into `$GITHUB_ENV` by the composite
actions.

No Android API level appears anywhere in CI. `compileSdk` follows
`flutter.compileSdkVersion`, so the Gradle plugin downloads the platform and
build-tools that the pinned Flutter asks for; CI only accepts the licences and
preinstalls the NDK revision it reads from `android/app/build.gradle.kts`. The
Android SDK cache is keyed on the Flutter and NDK versions, so bumping Flutter
rebuilds it. Android APK jobs use a matrix so each release contains one
ABI-specific APK: `android-arm` (armv7), `android-arm64` (armv8), and
`android-x64` (x86_64). Gradle, pub, Rust, JDK, and Android SDK caches include
the runner architecture; Gradle caches are additionally scoped per Android ABI
so a warm armv7 build does not overwrite the cache used by armv8 or x86_64.

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

### Manual release options

The manual trigger accepts three presets in addition to the toggles:

| Input | Choices (default first) |
| --- | --- |
| `android_arch` | `armv8`; `armv7 & armv8`; `arm & x86_64` |
| `linux_arch` | `amd64`; `arm64`; `amd64 & arm64` |
| `web_target` | `js`; `wasm` |

- The `android_arch` presets map onto the same ABI labels as a tag push
  (`arm` is the 32-bit ABI published as `android-armv7`).
- `linux_arch=arm64` requires the same opt-in infrastructure as CI: a
  registered self-hosted Linux arm64 runner with `ENABLE_ARM64_RUNNER=true`.
  Without it the job skips silently, so check the run before publishing.
  There is no prebuilt Flutter archive for Linux arm64; the SDK is cloned at
  the pinned version instead.
- `web_target=wasm` builds dart2wasm plus the automatic JS fallback and ships
  COOP/COEP headers (`_headers`) inside the bundle, since dart2wasm needs
  cross-origin isolation.
