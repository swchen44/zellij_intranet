# SSH → Linux Zellij interactive acceptance

> Historical source-build fallback record. The current official delivery artifact is
> `zellij-v0.45.1-full-x86_64-unknown-linux-musl.tar.gz`; the already completed Linux
> runtime evidence is retained and is not rerun for the package README/documentation update.

- Test time: 2026-09-20
- SSH host alias: `surfer`
- Artifact: `zellij-x86_64-unknown-linux-musl.tar.gz`
- Execution path: PTY-based `ssh -tt` smoke from the build workstation; it exercises the same remote SSH path, but Windows Terminal itself was not directly tested
- Remote package/config/cache: one disposable `/tmp/zellij-ssh.XXXXXX` directory
- Existing Zellij installation: not used, removed, or overwritten

## Result

Passed interactive startup and normal exit. The portable binary entered the Zellij
first-run setup flow, reached the normal terminal session, and exited cleanly after
the smoke-test detach/exit input. The SSH connection then closed with status 0.

This record covers the portable Zellij interactive path. It does not claim that
Claude Code, Codex, Yazi panes, resize, mouse, or OSC 52 clipboard have been tested;
those remain explicit follow-up acceptance items before production rollout.
