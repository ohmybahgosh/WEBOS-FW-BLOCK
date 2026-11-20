# Contributing to WEBOS-FW-BLOCK

Thanks for helping.  Reports from real TVs, fixes, translations, docs and code are all welcome.

## Reporting how it went on your TV

Reports from real TVs help most, whether FW Block worked or not.  In the TV app, choose **Help and report**: the report has no IP addresses or names in it.  Paste it into a [TV report](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/issues/new?template=tv-report.yml), or a [bug report](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/issues/new?template=bug-report.yml) if something's broken.  Over SSH, `sh fw-block.sh report` prints the same thing.

Seen your TV reach an LG update server or address FW Block doesn't block?  That's the most useful report there is: say which, and how you saw it.

Security problems go privately, see [SECURITY.md](SECURITY.md).  Questions and ideas go to [Discussions](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/discussions), not issues.  Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## Working on the code

- `fw-block.sh`: the block, its check and its status, one POSIX `sh` file that runs as root under busybox on the TV.
- `webos-app/src/`: the TV app, plain HTML, CSS and ES5 JavaScript for old webOS browsers.

```sh
sh tests/run.sh busybox          # the script against a fake TV (also dash and bash)
shellcheck -s sh fw-block.sh tests/run.sh tests/fakebin/* webos-app/build.sh scripts/screenshots/make-demo.sh
node tests/check-i18n.js         # every text in the TV app translated
sh webos-app/build.sh            # the IPK (needs ares-package from @webos-tools/cli)
```

The tests run the script against a fake TV in a temporary folder (its own `/etc/hosts`, settings service, firewall and update folders), so they need no TV and no root, and change nothing on your machine.

Ground rules:

- **It stands between someone's TV and an update that can take root away for good.**  Never weaken a block to fix something else, and never leave a block half-undone: `off` takes out everything it added, and only that.
- **Never touch another app.**  The Homebrew Channel's settings and lines, LG-USB-2-ETH0's settings, lines and rules, and other programs' firewall chains are read, never changed.  LG-USB-2-ETH0 keeps the job when its `--block-updates` is on.
- **No system files.**  `/etc/hosts` changes go through a bind-mounted copy, like the Homebrew Channel's own block.
- **POSIX `sh` for busybox, ES5 for the app.**  No bashisms; ShellCheck must pass.
- **A test for every change in behavior** in `tests/run.sh`.
- **Translations.**  The TV app speaks English, Russian and Spanish.  New app text, and new messages the script prints for an action, need a translation in each, or `node tests/check-i18n.js` fails.  If you can't translate it, say so in the pull request and the maintainer will.
- **Write for TV owners.**  Plain words, two spaces between sentences, no em dashes, and a line in `CHANGELOG.md` for anything they'd notice.

AI-assisted pull requests are welcome, held to the same standard as the rest of this project (it was built with AI coding agents too): say in the pull request that AI was used, make sure you understand and have reviewed every change, and test it on a real TV.  Coding agents read [AGENTS.md](AGENTS.md) by themselves.

Open a pull request against `main`; the template lists what to check.

## Releases

The maintainer cuts releases by pushing a `v*` tag.  GitHub Actions runs the tests, builds the TV app, publishes the IPK, its Homebrew Channel manifest, `fw-block.sh` and `SHA256SUMS`, and tells ohmybahgosh.dev to refresh its Homebrew Channel repository.
