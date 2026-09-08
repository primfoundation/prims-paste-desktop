# Primboard stabilization

Product name: **Primboard**. This document distinguishes user-facing naming from runtime identities that protect existing access, keys and data.

## Compatibility locks

Do not change these in a cosmetic rename:

- bundle identifier: `sh.prims.paste`
- executable/product target: `PrimsPaste`
- CLI: `prims-paste`
- store root: `~/.prims-paste`
- Keychain service: `sh.prims.paste`, account `notebook-aes-256`
- existing item IDs, tab IDs and decodable notebook versions

A future change to any of these needs a migration, rollback and real-Mac proof.

## P0 stabilization gates

1. **Development state is not user state.** Normal product unlock must not seed `FeaturesWanted`/`Bugs` into a new user notebook. Existing seeded cards are preserved; no migration deletes user data. Developer/demo fixtures must use an explicit mode and isolated notebook root.
2. **Index confidentiality.** The encrypted-index migration below protects captions, tab names, timestamps, key classification and conversion refs in the current index. Signed existing-store migration acceptance and independent security review remain required.
3. **Concurrent writers.** App and CLI share the interprocess lock/revision contract described below. Keep both executables on the same journal-aware version; installed multi-process acceptance remains a release gate.
4. **Crash consistency.** The encrypted redo journal below coordinates referenced index/blob changes and replays interrupted operations. Physical power-loss/storage-device validation and independent review remain open.
5. **Backup/recovery.** The CLI export/restore below adds authenticated recovery to a separate directory. A guided GUI recovery flow and real-Mac recovery acceptance remain open.
6. **Security boundary.** Document Touch ID as the app opening gate and Keychain accessibility as the storage-key boundary used by both GUI and CLI. Test what the CLI can do while the app is closed/locked.
7. **Generic conversion.** Add `Convert to Prim…` using a pinned Foundation Library definition, local schema/template population and a backlink. Never copy a secret payload by default.
8. **Signed Mac acceptance.** Build/sign/install, existing-store reopen, Keychain reuse, Accessibility, Screen Recording, camera/microphone, screen-sharing protection and CLI access must be proven on a real Mac before stable release.

## Implemented stabilization checkpoint

- macOS CI now builds/tests with the contemporary Swift toolchain and guards compatibility-sensitive IDs;
- Swift 6 calendar-placement ambiguity is fixed explicitly rather than relying on older numeric inference;
- local Docket/Paseo paths are portable and overrideable instead of containing one developer's home directory;
- Docket contract tests are hermetic, while optional installed-tool integration skips honestly when the local tool is absent;
- normal startup no longer seeds Primboard's own `features-wanted` backlog. `PRIMBOARD_DEVELOPER_SEEDS=1` is the explicit developer-only opt-in;
- existing feature/bug tabs and cards are retained if already present; startup prefers today's existing tab rather than deleting or rewriting user state;
- a one-shot repair reconstructed `Board.swift` from exact base commit `25d2641443c1e9d4b55b2651c18188a378a3b166` and applied only the intended startup block change after an intermediate edit touched too much code. The temporary repair workflow removed itself. The current PR diff is the review authority, not that intermediate state.

A subsequent human-authored checkpoint intentionally triggers the normal macOS verification again; GitHub's `action_required` status on bot-authored repair commits is not treated as passing evidence.

## Quality policy

Mac CI proves source build/tests/selftest and guards compatibility strings. It does not prove Developer ID signing, TCC grants, existing-user migration, UI usability or runtime integration with external Docket/Paseo/Library services.

The repository can be renamed to `primboard` only after external URL/clone references, automation and release paths are inventoried and a fresh clone under the new slug builds and opens the same existing store without changing the locked runtime identities.

## Store transaction foundation — G3

The updated app and CLI share an advisory file lock spanning each complete store
operation. A recursive thread lock serializes one instance; `flock` coordinates
independent instances/processes through a persistent, private `.store.lock` file.
The lock file must never be removed while a store is open.

Whole-index saves compare a monotonic revision and reject stale snapshots.
Historical indexes without a revision read as revision zero; existing item IDs,
store paths, Keychain identity and payload encryption remain unchanged. Run the
updated app and CLI together: older binaries do not honor the new lock/revision
contract and must not write concurrently with this version.

File replacement writes a uniquely named private temporary file, flushes it,
renames over the target without a remove gap, then flushes the containing directory.
Tests cover independent writers, lost-update rejection, legacy index reads,
old-reader validity, permissions, temporary-file cleanup and lock symlink rejection.
Mac CI is the build/test gate for these Swift changes.

This checkpoint established file-level atomicity and cooperative transaction
locking. The subsequent journal checkpoint below adds recovery across blob/index
updates. Physical power-loss and signed-Mac/TCC acceptance remain open G3 gates.

## Encrypted index and recovery checkpoint — 2026-09-08

The existing `index.json` path now contains a `PPI3` binary envelope around an
authenticated AES-GCM payload. The decrypted model still reads notebook versions
1 and 2. No bundle, CLI, store, item, tab, or Keychain identity changes. Old JSON-only
readers fail on this envelope; update the app and CLI together before using this
store format. Do not run an older binary against a migrated notebook.

On first successful legacy read, the store validates the model and authenticates
its referenced payloads with the existing key. It then saves the exact original
index bytes, encrypted, as `index.migration.enc` before replacing the active index.
An existing different migration backup is retained and another uniquely named
encrypted copy is written. Corrupt indexes, wrong keys, missing referenced legacy
payloads, unsafe IDs and ambiguous body/image filenames fail without rewriting the
index. A missing active index after migration is an error, not an empty board.
This protects current files; it does not promise secure erasure of historical
plaintext disk blocks, snapshots or external backups. File names, counts, sizes
and filesystem timestamps remain observable.

```sh
prims-paste backup /path/to/new-backup.pboard
prims-paste restore /path/to/new-backup.pboard --to /path/to/new-notebook
```

Export holds the shared store lock, authenticates all referenced text/image blobs,
checks payload sizes, and writes a private authenticated archive exclusively. It
will not replace an existing file. The snapshot includes the encrypted index and
referenced encrypted blobs; unrelated files and migration history are excluded.
The archive contains no key. Restore requires the original `sh.prims.paste` /
`notebook-aes-256` Keychain key and will not create a replacement key if it is
missing. A lost key means this backup cannot be decrypted; this is not a portable
key-recovery system or a cross-Mac transfer feature.

Restore authenticates and validates the entire snapshot, rejects missing or extra
blobs, then writes a private staging directory and publishes it to a new directory.
The active notebook is never replaced by this command. Inspect the restored copy
before any separately planned store cutover. Export supports up to 128 MiB of
sealed source files; restore accepts archives up to 256 MiB. Larger stores need a
future streaming archive design. The operation is a locked consistent snapshot,
not a repair mechanism for historical corruption or unrelated missing files.
Export first replays a valid pending journal before capturing the snapshot.

Recovery tests cover metadata confidentiality, exact legacy migration preservation,
wrong keys, tampering, old-reader failure, payload/image round trips, private
permissions, non-overwrite behavior, missing/extra data and unsafe path collisions.
Mac CI verifies the implementation. Signing, TCC, actual Keychain reuse and
existing-user acceptance still require the signed real-Mac release gate.

## Safe Mac candidate preparation — 2026-09-08

`scripts/build.sh` now checks a usable company signing identity before building
and produces a candidate from an isolated archive of the committed source. It
does not quit apps, overwrite the installed bundle, update the CLI link, or open
the real notebook. Nested code is signed first; candidate verification requires
the existing Developer ID/team, hardened runtime, timestamp, and no debug
entitlement. The font license is included in the bundle.

`scripts/mac_release.py notarize` records one Apple submission, resumes checks by
ID, matches Apple's accepted log to the submitted ZIP hash, then staples a copy
and verifies the final unpacked artifact. `MAC-RELEASE.md` assigns the remaining
local-agent work and preserves the matched pre-migration app/store rollback
boundary. Mocked failure tests and macOS CI bundle selftest verify the tooling;
they do not close live signing, notarization, installed-store, or TCC gates.

## Encrypted crash journal — 2026-09-08

Referenced changes now publish a private authenticated `.transaction.enc` record
before replacing any blob or index. The `PPJ1` record contains the exact sealed
previous and next indexes, sealed changed blobs, and precise obsolete-file names;
the entire record is encrypted again with the existing notebook key. Publication
is the commit point. A save that subsequently fails may have committed: reopen
and reconcile the board before repeating an add or another user operation.

Every index read, direct blob/image read, and mutation checks for recovery while
holding the same interprocess store lock. Replay validates the entire record and
affected paths before changing files, writes all changed blobs, publishes the
matching index, removes only obsolete referenced blobs, then clears the journal.
Replaying a partially completed replay is safe and does not advance the revision
twice. A wrong key, tampered record, unexpected primary revision, unsafe path,
symlink destination, inconsistent byte count/fingerprint, or ambiguous filename
blocks recovery without deleting the record.

Adds, payload edits, image attachment/replacement, removals, whole-index saves,
and feature/bug seed batches use this protocol. Public `writeBlob` and `deleteBlob`
calls on indexed items now update/remove the matching index transactionally;
unreferenced raw blobs remain available for import assembly, with alias checks.
`writeImage` requires an existing item. Case-only/Unicode-equivalent path renames
are rejected, and removing one item cannot delete another item's image-shaped
body filename. Product, bundle, CLI, Keychain, store, item and tab identities stay
unchanged; the current index still uses `PPI3` and model versions 1/2.

The journal supports up to 64 MiB of changed sealed blob data and 128 MiB of
encoded journal data per transaction. Larger changes fail before journal
publication; a streaming protocol is future work. Files/directories retain
0600/0700 permissions. File data and directory entries are synced, and macOS
`F_FULLFSYNC` is required before advancing durability boundaries; unsupported
filesystems fail instead of silently weakening the barrier. This follows Apple's
[fsync guidance](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html).

`NotebookJournalTests` injects interruption at commit and cleanup boundaries and
launches isolated XCTest subprocesses that exit abruptly without cleanup. The
suite covers first-add recovery, payload/image/removal/batch replay, repeated
recovery interruption, backup-after-recovery, stale writers, confidentiality,
private permissions, malformed/authentication/path failures, oversize rejection,
and filename collisions. These are process-crash and software fault tests, not
physical power-loss proof, a signed release, real-notebook acceptance, or a
substitute for independent security review. Disk exhaustion, device/filesystem
failure matrices, large-store latency and GUI recovery presentation remain open.

The recovery tests also exposed nondeterministic tab metadata: legacy indexes
without explicit tabs generated a new tab creation time on every read. Derived
tabs now use timestamps from their source items (epoch for an empty legacy
notebook), and new commits persist their derived tabs. Explicit existing tabs
and their creation dates are preserved.

Older binaries do not understand this journal. Update app and CLI together; do
not mix versions or delete `.transaction.enc` to bypass an error. Preserve the
complete store (including an unresolved journal) for diagnosis. Pre-journal
corruption, lost keys and arbitrary external file changes are not auto-repaired.
