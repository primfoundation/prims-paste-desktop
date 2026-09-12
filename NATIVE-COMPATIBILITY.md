# Native notebook compatibility reconciliation

Requirements: HUM-002/004, RELENG-002/003, SEC-001; delivery package D95-05.

The September 12 existing-store attempt proved that the signed clean-main app
could not read a newer development notebook. The prior app/CLI were restored;
no original notebook file bytes changed. This increment reconciles the storage
semantics recovered from the preserved development source:

- `file` and `video` keep their original encrypted body bytes.
- `captionSource` retains typed/heard provenance; missing legacy values follow
  the observed audio/video caption rule. Explicit values are never inferred over.
- `lane` retains its exact spelling, including empty and future column names.
- `workers` retains job records and status as data; opening does not resume work.
- `fillDefaultID` and string/object `conversion.lastComment` survive round trips.

The current journal, revision checks, encrypted index, exact encrypted migration
backup, missing-key protection and same-key backup/restore stay in force. Unknown
fields/types still fail closed. Existing secret conversion links are retained as
data, excluded from creation menus, and refused by create/revert operations before
any external process is invoked. Unknown worker fields remain unsupported; this
does not authorize running copied job records or external tools.

The current GUI shows honest retained-file/video cards without decoding their
binary payload as text. Playback, recording, kanban/worker controls and the broader
development UI still need reconciliation. This storage increment is not approval
to replace the richer installed app or a signed installed-release claim.

Synthetic regression tests cover migration, encrypted binary/metadata backup and
restore, caption defaults, exact column spelling and unsupported future fields.
An additional opt-in integration test reads only an explicitly supplied private
snapshot, obtains the existing key without creating/exporting one, copies the
snapshot into a new private temporary folder, migrates/backs up/restores there,
and checks metadata and encrypted payload identity without logging contents.
Default CI skips that private integration. The active notebook is refused as its
input; no live migration or installation is performed by this test.

Native complete-pack attachments remain a separate implementation obligation.
