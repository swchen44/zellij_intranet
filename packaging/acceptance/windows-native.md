# Windows native acceptance

This record is a checklist for the Windows host gate. The local macOS
`cargo-xwin` build is only a candidate build and cannot complete this record.

The package must be built with the fixed target `x86_64-pc-windows-msvc` and
validated on a real Windows host. Do not substitute MinGW/GNU or Wine for the
Windows Terminal/ConPTY gate.

The initial package uses the `terminal-only` feature profile. It includes builtin
WASM plugins but intentionally excludes Zellij web/share capability; that is not
needed for Windows Terminal + Zellij + Yazi.

## Automated smoke

Run from a Windows PowerShell session without Rust/Cargo in the runtime `PATH`:

```powershell
./packaging/acceptance/windows-native.ps1 dist/zellij-x86_64-pc-windows-msvc.zip
```

The script verifies the archive, `zellij.exe --version`, `setup --check`, default
layout dump, at least 12 builtin WASM plugins, and SHA-256 when a companion file is
present.

## Manual Windows Terminal gate

- [ ] Extract to a user-writable short path without admin rights.
- [ ] Start Zellij in Windows Terminal through ConPTY.
- [ ] Verify resize, mouse, Unicode/CJK, copy/paste, and the company shell.
- [ ] Verify detach/attach and pane split/close.
- [ ] Start `claude`, `codex`, and `yazi` in separate panes if installed.
- [ ] Run with no Rust, Cargo, OpenSSL, or Visual Studio build tools in `PATH`.
- [ ] Record Windows version, Windows Terminal version, package hash, and failure log.
