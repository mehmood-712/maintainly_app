# Maintainly developer tools

## Install Drift Web assets (Windows PowerShell)

Drift Web needs a matching `sqlite3.wasm` file and web worker in the `web/`
folder. The setup script downloads both files from the pinned Drift 2.35.4
release and verifies their SHA-256 checksums.

Run from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup_drift_web_assets.ps1
```

The download requires internet access once. The resulting files are local
project assets and are served with the Flutter Web build; the app does not
fetch them at runtime from GitHub.
