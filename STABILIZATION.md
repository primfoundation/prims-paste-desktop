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

## Quality policy

Mac CI proves source build/tests/selftest and guards compatibility strings. It does not prove Developer ID signing, TCC grants, existing-user migration, UI usability or runtime integration with external Docket/Paseo/Library services.

The repository can be renamed to `primboard` only after external URL/clone references, automation and release paths are inventoried and a fresh clone under the new slug builds and opens the same existing store without changing the locked runtime identities.
