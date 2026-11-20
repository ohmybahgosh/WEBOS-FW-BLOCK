# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, Copilot and others) working in this repository.  Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) too: SECURITY.md lists everything the app is allowed to do as root.

- `fw-block.sh` is plain POSIX `sh` that runs as root under busybox on the TV.  No bashisms (`[[ ]]`, arrays, `local`, `echo -e`), no `A && B || C` (use `if`), and don't let a pipe close early (`head`, or `awk` with `exit`): GitHub's runners ignore SIGPIPE, and the writer's error lands in the output.  Use `awk 'NR == 1'`.
- Everything it reads goes through the paths at the top of the script, so the tests can move them under `FB_ROOT`.  `luna-send` and `iptables` go through `FB_LUNA` and `FB_IPTABLES`.
- Never change another app: the Homebrew Channel's settings and `/etc/hosts` lines, LG-USB-2-ETH0's settings, lines and rule, and other firewall chains are read only.  When LG-USB-2-ETH0's `--block-updates` is on, it keeps the job and this stands by.
- `off` removes exactly what `on` added (tagged hosts lines, the `FWBLOCK` chain, the hook) and puts webOS's update check back as it was, unless LG-USB-2-ETH0 still blocks updates.
- The only network request is the update check (`update.js`), and it must only accept a manifest signed with a key in `update.js` (the release key or its backup).  Don't add keys, loosen that check, or add any other request.  Never commit a private key: `node tests/check-signing.js` fails if one is in the repository.
- Fear-driven safety: when in doubt, leave updates blocked.  Never turn webOS's update check or Automatic software update back on while another blocker keeps it off (`others_keep_check`, `eth0_auto`).  Never delete a saved original until it has been put back.  Write settings with `conf_set` / `write_file` (new file, checked, then moved).  Never rewrite `/etc/hosts` without the checks in `hosts_remove`.  Never treat a missing app folder as an uninstall unless `app_gone` agrees.
- Anything that changes the TV's state should make a backup first (`backup_make REASON`), like `on`, `restore` and `update-install` do.
- The TV app (`webos-app/src/`) is plain ES5: no `let`, `const`, arrow functions, template literals, `async`, `?.` or `??`.  New app text goes through `T()` with a Russian and Spanish translation in `i18n.js`, and new script messages for an action get a pattern in each language's `*Script` list.
- Text people read: plain words, two spaces between sentences, no em dashes.
- Before you finish: `sh tests/run.sh busybox` (and `dash`, `bash`), ShellCheck, `node tests/check-i18n.js` and `node tests/check-signing.js .cache/tweetnacl-1.0.3-nacl-fast.min.js` pass, a test covers the change, and `CHANGELOG.md` and `README.md` cover anything a user would notice.
- Don't bump `VERSION`, tag, or publish releases.  The maintainer does that.
- Say in the pull request that AI was used, and test on a real TV (model and webOS version).
