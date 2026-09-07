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
2. **Index confidentiality.** Payload blobs are encrypted, but the current index can contain captions, tab names, timestamps, key classification and conversion refs. Define and test a versioned encrypted-index migration before describing the whole notebook as metadata-private.
3. **Concurrent writers.** App and CLI share one store. Replace uncoordinated read-modify-write with interprocess transaction/lock semantics and stale-writer tests.
4. **Crash consistency.** Prove replacement of index/blob state cannot expose a missing-current-file window; preserve recoverable prior state where necessary.
5. **Backup/recovery.** Add encrypted export/restore, integrity checks, corruption UX and explicit lost-key behavior.
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
