# Local Prim records and recovery

Create a Prim from the toolbar or File menu. The four bundled development
definitions are Research, Person, Decision and Workbook. A selected sticky
supplies its caption as the draft title. Its payload is not copied automatically.
Saving creates a separate encrypted record and preserves the source sticky.

Open a Prim card to edit its declared fields. Collections and additional fields
can be edited under All fields as JSON. Unknown fields are preserved. Validation
checks the pinned schema and declared references; it does not verify facts,
approval, source independence or permission to act. A changed record rejects a
stale save. A missing definition remains an explicit failure without upgrading.

Export local files creates a new unencrypted Prim folder containing the authority
record, exact definition lock, face and log. The dialog names that privacy change.
Import Prim folder checks the exact pin and structure before offering to save a
copy into the encrypted notebook. This is record import, not a general attachment
or archive migration. Original folders remain intact. Native and SDK hosts reject
unsupported schema features, duplicate fields, oversized/deep JSON and unsafe
paths; macOS's standard temporary-directory aliases are handled explicitly.

CLI examples (no profile code or network requests):

```sh
prims-paste profiles
prims-paste prim create primfoundation/person --version 0.1.0-dev.1
prims-paste prim create primfoundation/research --version 0.3.0-dev.3 --from STICKY_ID --input local-record.json
prims-paste prim validate PRIM_ID
prims-paste prim export PRIM_ID --to new-record.prim
prims-paste prim import new-record.prim
```

For an operation that may have committed, reuse an explicit
`--operation prim_<32 lowercase hexadecimal characters>` with the same input.
The app holds this operation ID through a creation session. The exact existing
record is returned on an identical retry; conflicting content is not overwritten.

## Recovery

An unsuccessful notebook open keeps the board locked. Storage failures reload
any committed journal operation before subsequent writes. Recovery can retry the
load, export an authenticated same-key backup, or restore a backup to a separate
folder without replacing the active notebook. Restoring from a locked app first
requires local biometric authentication; a new key is never generated for restore.

Pending note edits are retained in memory during the current app session. Recovery
can retry them with compare-before-save protection or save them as separate
encrypted notes. It does not overwrite a concurrent writer's version. Keep the app
open until pending edits are saved: unsaved in-memory drafts do not survive process
termination. Key-loss recovery, physical power loss/device failure, independent
review, VoiceOver and signed installed acceptance remain separate gates.

Use matching updated app and CLI binaries. Older binaries can ignore new optional
Prim metadata and do not provide these validation/recovery protections. Follow
MAC-RELEASE.md for the safe candidate and installation process.

The bundled catalog is generated from Foundation's exact existing profile source
at `50d829d5019ed2f2754dfb4fc11843bcd9d25cc9`. Catalog SHA-256:
`9787ffa5bc6948f6d069990ed2b2d2096b9b23c4ed338b4c2fe444ceb3db02e3`.
The generation script is `scripts/sync-prim-library.py` and consumes Foundation's
host exporter. This provenance is not publisher authentication or a stable-standard
release. The native corpus uses 83 synthetic Python reference cases; independently
written implementations are not independent organizational review.
