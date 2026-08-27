# prims-paste-desktop

GitHub: https://github.com/primfoundation/prims-paste-desktop

App: `~/Applications/Prims Paste.app`  
Identifier: `sh.prims.paste`

Encrypted sticky board for this Mac. Touch ID to open. Not SafePaste; no CLI broker, no 24h TTL, no shared store.

```bash
./scripts/build.sh
```

Signed `Developer ID Application: Eidos AGI LLC (Y6CQ4SWPWM)`.

Store: `~/.prims-paste/notebook/` (AES-GCM, key in login keychain).  
Convert: Docket via `docket-prim task-create` into `~/.prims-paste/docket/`; Paseo via `paseo run`.

CLI (same store as the app):

```bash
prims-paste help
prims-paste open
prims-paste tabs
prims-paste add --tab bugs --title "…" --body "…"
prims-paste list --tab bugs
prims-paste convert <id> docket
prims-paste bugs file
prims-paste bugs tasks
```
