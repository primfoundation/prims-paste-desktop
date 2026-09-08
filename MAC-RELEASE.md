# Primboard Mac release work order

Status: candidate tooling implemented; a company-signed, notarized, installed
release has **not** been demonstrated by the cloud test run. The current app's
minimum OS is macOS 14. Cloud CI builds and tests Swift, but does not have the
company signing key or access to Daniel's notebook and macOS permissions.

## Give this work order to the local Mac agent

Daniel can paste this into his existing local agent:

> Follow `MAC-RELEASE.md` in `primfoundation/prims-paste-desktop` on current main.
> Preserve my existing app, notebook, Keychain identity, and uncommitted work.
> Perform the build, notarization, backup, installation, and acceptance work
> yourself using the existing authorized Eidos company identity. Ask me only for
> macOS consent that requires a person, or a specific missing credential/access
> decision. Do not request secret keys in chat. Also locate the original
> `prim-sim` / `PrimSimCore` checkout needed by Prims Desktop; report its origin,
> full revision, license, and whether changes are unpushed. Do not invent a stub
> or publish private source to unblock the build. Return source/artifact hashes,
> release evidence, and exact unresolved blockers without private notebook data.

## Local agent procedure

1. Inspect the existing checkout and preserve local work. Fetch current main into
   an isolated clean checkout rather than resetting a working checkout. Read
   `STABILIZATION.md` and the shared
   [Mac release lifecycle](https://github.com/eidos-agi/eidos-desktop-app-builder/blob/main/docs/workflows/release-lifecycle.md).
   Inventory the installed app and CLI targets without replacing them.
2. Run `python3 scripts/mac_release.py preflight`. It checks macOS 14+, required
   command availability, a clean source revision, and exactly one usable
   `Developer ID Application: Eidos AGI LLC (Y6CQ4SWPWM)` identity. This checks a
   signing identity, not merely a certificate. A usable private key can still
   require Keychain approval when signing. Do not substitute ad-hoc, personal,
   or development signing. If Xcode/Command Line Tools are missing, install the
   supported toolchain using the local approved setup and record its version.
3. Run `./scripts/build.sh`. It tests and builds an immutable Git archive of the
   full source commit in `.build/release-candidates/`, assembles resources and
   licenses, runs the synthetic selftest, signs nested code before the app, and
   verifies team, Developer ID authority, runtime, timestamp, and absence of the
   debug entitlement. It neither quits nor replaces any installed app, changes
   the CLI link, nor opens the real notebook. It prints the candidate directory.
4. Use an existing authorized notary Keychain profile. The profile name is local
   configuration; this repository does not assume a profile exists or supply
   account credentials. Run the following with the actual path and profile:

   ```sh
   python3 scripts/mac_release.py notarize /absolute/candidate/directory --notary-profile EXISTING_PROFILE
   ```

   This submits once and records its ID. Exit 3 means Apple is still processing;
   rerun the same command later. Exit 1 is a blocker, not a release. An interrupted
   upload without a recorded ID requires the agent to recover the ID using
   `xcrun notarytool history --keychain-profile EXISTING_PROFILE --output-format json`
   and pass `--submission-id ID`; do not upload again automatically. The helper
   verifies Apple's accepted log against the exact submission ZIP SHA-256 before
   stapling a separate copy, checking Gatekeeper, archiving it, unpacking the final
   ZIP, and repeating verification/selftest. Keep `release.json`, status, log,
   final ZIP, and hash together. Raw candidate workspaces are private build
   outputs, not public evidence uploads.
5. Before first launch of the new app or CLI against user data, gracefully stop
   Primboard and confirm all notebook writers have exited. Preserve the old app,
   old CLI/link target, and a complete consistent **pre-migration** snapshot of
   `~/.prims-paste/` with existing permissions. Keep backups in protected local
   storage, record their paths privately, and verify the copy. Do not run the new
   `backup` command as a substitute for this pre-migration snapshot: opening a
   legacy store with the new CLI can migrate its index.
6. Install the verified candidate at `~/Applications/Primboard.app` with a
   rollback copy retained; update the CLI link to the matching bundled CLI only
   after the candidate passes its gates. Do not quit unrelated SafePaste or
   other apps. Preserve bundle ID `sh.prims.paste`, executable `PrimsPaste`, store
   location, and Keychain service/account. Record exact old/new app paths and
   hashes. Installation remains an agent-operated step, not an implicit side
   effect of the build script.
7. Use matching journal-aware app and CLI binaries. Never delete an unresolved
   `.transaction.enc` to bypass recovery, and preserve it with the complete store
   if recovery is blocked. A failed save may have committed; reload and reconcile
   before repeating an add. Perform installed acceptance locally: reopen the existing notebook using its
   original key; confirm item/tab preservation and encrypted-index migration;
   exercise a disposable local test card through GUI and matching CLI; create an
   encrypted backup to a new file and restore it into a separate new directory;
   verify the restored data without replacing the active notebook. Check actual
   Touch ID/Keychain behavior and relevant Accessibility, Screen Recording,
   camera/microphone, and screen-sharing protection flows. Only request OS
   consent that actually blocks an intended feature. Record absent optional
   integrations as untested, not passing. Never include notebook contents or
   encryption keys in GitHub logs or evidence.
8. Record what was observed and what remains open. The notarization helper's
   `notarized-candidate` status is not an assertion of installed acceptance.
   Publication additionally needs an intentional release version/build number,
   retained artifact and checksum, release notes, and a fresh downloaded-app
   acceptance run preserving quarantine metadata. Verify only the architecture
   actually built; a local host build is not a universal binary claim.

If rollback is required after migration, stop every notebook writer and restore
the matched old app **and** its pre-migration store snapshot as a pair. An old app
cannot read the new encrypted index. Do not point an old executable at the
migrated store, reset permissions, delete a Keychain key, or overwrite new user
data to make a test pass. Preserve both states and stop for a recovery decision
if user data changed after the snapshot.

## What Daniel actually needs to do

- Run the local agent on the Mac holding the authorized signing identity, or
  grant an already configured local agent access to this work order. This chat
  currently has no connected Mac execution endpoint.
- Respond to legitimate macOS Keychain/Touch ID/permission dialogs. The agent
  should perform the technical checks and report only specific blockers.
- If the missing `prim-sim` source is only in another private account or local
  checkout, identify that location or authorize appropriate repository access.

No key export is required for the existing-Mac route. If no usable identity or
notary profile exists, report that exact blocker and follow the shared
[signing custody plan](https://github.com/eidos-agi/eidos-infra/blob/main/docs/apple-cloud-signing.md).
Never paste a `.p12`, `.p8`, password, or notebook key into chat or a repository.

## Engineering work that remains ours

| Area | Remaining work | Mac or access dependency |
| --- | --- | --- |
| Primboard storage | Encrypted process-crash journal and fault injection implemented; physical power-loss/device and large-store performance validation remain; guided recovery, lost-key/portable recovery, and generic Convert to Prim remain | Coding and CI can proceed remotely; actual store/Keychain acceptance is local |
| Primboard release | Intentional version/build, artifact publication and fresh-download acceptance; installed GUI/CLI and permission evidence | Company signing/notary access and local OS consent |
| Shared Apple build system | Builder dispatch, hosted signed-release workflow, credential custody integration, durable logs/artifacts, first end-to-end release, Mac-offline proof | The infrastructure checkpoint is `planned_not_activated`; one-time authorized credential setup comes after the workflow is prepared |
| Foundation Hub | Confirm real browser downloads, mobile/accessibility acceptance, production route/registry compatibility, operational ownership/budgets/alerts | Existing preview is live; production/account access must match the actual service |
| Browser containers | Real Apple login/session/cookie-domain acceptance and production route evidence | Appropriate authenticated browser/account context |
| Prims Desktop | Recover/pin the original `PrimSimCore` dependency, then run reproducible build and runtime proof | Original source/revision/license is unavailable in connected repositories |
| Foundation standards | Independent implementation/review evidence, remaining profile/source/privacy/consumer audits, operator reporting and recovery evidence | Mostly engineering/review work; retirement requires migration proof |

The authoritative broader roadmap remains
[`prim/program/plan.json`](https://github.com/primfoundation/prim/blob/main/program/plan.json).
The live Cloudflare preview is verified separately. The legacy Railway workflow's
`Service not found` failure remains unresolved; the current Railway connection
does not expose the Foundation/Eidos project. Do not change unrelated projects
or hide that failure while production ownership is unresolved.

## Evidence scope

`python3 -m unittest discover -s tests/release -v` exercises failure boundaries and
notary state handling with mocked signing/Apple responses. On macOS, it also
assembles the real CI-built Swift binaries and runs the app's synthetic selftest
inside the resulting `.app`. CI still cannot prove real Developer ID signing,
Apple acceptance, existing-store migration, or TCC. These remain explicit gates.

Implementation follows Apple's guidance for
[nested code signatures](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
and [notarization workflows](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
