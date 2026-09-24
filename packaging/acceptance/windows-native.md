# Windows native acceptance

This record is a checklist for the Windows host gate. The local macOS
`cargo-xwin` build is only a candidate build and cannot complete this record.

The package must be built with the fixed target `x86_64-pc-windows-msvc` and
validated on a real Windows host. Do not substitute MinGW/GNU or Wine for the
Windows Terminal/ConPTY gate.

The official delivery package uses the `full` variant by default. It includes builtin
WASM plugins and the upstream web capability, but the web server does not start automatically.
The `no-web` variant remains an explicit alternative and is not the default release.

## Automated smoke

Run from a Windows PowerShell session without Rust/Cargo in the runtime `PATH`:

```powershell
.\packaging\acceptance\windows-native.ps1 dist\official\zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.zip
```

The script verifies the `zellij_bin` archive layout, package `README.md` sections, `zellij.exe --version`,
`setup --check`, default layout dump, at least 12 builtin WASM plugins, and SHA-256 when a
companion file is present.

## Manual Windows Terminal gate

- [ ] Extract to a user-writable short path without admin rights.
- [ ] Start Zellij in Windows Terminal through ConPTY.
- [ ] Verify resize, mouse, Unicode/CJK, copy/paste, and the company shell.
- [ ] Verify detach/attach and pane split/close.
- [ ] Start `claude`, `codex`, and `yazi` in separate panes if installed.
- [ ] Run with no Rust, Cargo, OpenSSL, or Visual Studio build tools in `PATH`.
- [ ] Record Windows version, Windows Terminal version, package hash, and failure log.
