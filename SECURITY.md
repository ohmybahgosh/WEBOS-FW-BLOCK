# Security policy

FW Block runs as root on your TV and stands between it and LG's firmware updates, so security problems matter even for a small app.

## Supported versions

Only the [latest release](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/releases/latest) gets fixes.

## Reporting a problem

Please don't open a public issue for a security problem.  Report it privately through GitHub's [private vulnerability reporting](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/security/advisories/new) instead.

Include what you found, how to reproduce it, and which version you used.  You'll get a reply as soon as possible, and credit in the changelog if you'd like it.

## What it does as root

So you can judge it yourself:

- **Reads** `/etc/hosts`, the Homebrew Channel's Block system updates flag (`/var/luna/preferences/webosbrew_block_updates`), LG-USB-2-ETH0's settings (`/var/lib/webosbrew/lg-usb-2-eth0.conf`) and hook, the firewall's rules (`iptables -S`), webOS's update folders (`/mnt/lg/cmn_data/swupdate` and `/mnt/lg/cmn_data/update`), the TV's webOS and firmware version (`/var/run/nyx/os_info.json`), and webOS's update check setting (through `luna-send` to `com.webos.settingsservice`).
- **When you turn it on:**
  - sets webOS's update check (`support` / `softwareUpdateEnable`) to `false` and **Automatic software update** (`support` / `automaticUpdate`) to `off`, and keeps what they were in `/var/lib/webosbrew/webos-fw-block/switch.orig` and `auto.orig`
  - deletes `Image_Update_Info.xml` and `Package_Update_Info.xml` from `/mnt/lg/cmn_data/swupdate`, the details of an update webOS already found
  - adds `0.0.0.0` and `::` lines, tagged `# webos-fw-block`, to `/etc/hosts` for each update server nothing else blocks yet.  `/etc/hosts` is read-only on webOS, so when nothing has done it already, it copies it to `/tmp/webos-fw-block/hosts` and bind-mounts that over it, the way the Homebrew Channel does.  The system partition is never written.
  - adds a firewall chain, `FWBLOCK`, with rules that drop `156.147.69.32` (and, while Remote Support is blocked, `165.244.62.249` and `165.244.99.174`), and one rule at the top of `OUTPUT` that jumps to it
  - while Remote Support is blocked (the default), adds `0.0.0.0` and `::` lines tagged `# webos-fw-block remote-support` for LG Remote Support's nine `rone-*.lge.com` servers
  - writes `/tmp/webos-fw-block/update.interface`, a copy of the phone gateway's file for the update service (`/usr/palm/services/com.webos.service.secondscreen.gateway/interfaces/com.webos.service.update.interface`) with only its read-only `getCurrentSWInformation` and `getVersion` calls, and bind-mounts it over that file.  The gateway reads it at its next start; FW Block never restarts it.  `off` unmounts it.
  - every 30 seconds, looks for the updater's working files (`/tmp/nsu-running`, `/mnt/lg/cmn_data/.UpdateIsInprogress`, `/tmp/usbupdate-running`).  Only when one is there does it ask the updater its status (`com.webos.service.update/getStatus`).  If it's downloading, it calls `com.webos.service.update/cancelUpdate`, deletes the found update details, and shows a notice (`com.webos.notification/createToast`).  It never cancels an install, or anything while a USB update runs.
  - when it was turned on from the app and the app's folder is gone (checked twice, a few seconds apart), undoes everything like `off` and deletes its hook and `/var/lib/webosbrew/webos-fw-block`: an uninstall cleans up after itself
  - writes one startup hook, `/var/lib/webosbrew/init.d/50-webos-fw-block`, and a copy of `fw-block.sh` in `/var/lib/webosbrew/webos-fw-block`, so the block comes back at every start, even if the app is removed
  - runs a check every 10 minutes that puts back anything above that was undone.  It writes what it did to `/var/lib/webosbrew/webos-fw-block/events` (the last 50) and `stats`.
- **When you turn it off,** it puts both update settings back the way they were (the hidden one stays off while LG-USB-2-ETH0 still blocks updates), takes out its tagged `/etc/hosts` lines and its firewall chain, stops the check, and removes the hook and the copy.  **remote off** takes out only the Remote Support lines and rules.
- **Backups.**  Before it turns the block on, restores a backup or installs an update, it saves webOS's two update settings, its own settings, a copy of `/etc/hosts`, the phone gateway's update file (while its own copy isn't over it) and the firewall's `OUTPUT` rules (`iptables -S OUTPUT`) in a dated folder under `/var/lib/webosbrew/webos-fw-block/backups`, only root can read, the newest 10 kept.  **Restore** (`restore NAME`) puts FW Block's switches and webOS's two update settings back as they were in that backup and turns FW Block on or off to match.  It never writes the saved `/etc/hosts` or gateway file back: FW Block never changes those files themselves, so turning it off already leaves them as they were.
- **Other blockers' settings.**  It never changes the Homebrew Channel's or LG-USB-2-ETH0's settings, `/etc/hosts` lines or firewall rules; it reads them (the Homebrew Channel's flag file and, to see whether its block also turns the update check off, its service's `startup.sh` and scripts; LG-USB-2-ETH0's settings, startup hook and its saved originals `lg-usb-2-eth0.updates` and `lg-usb-2-eth0.autoupdate`) to know what they already block.  It never turns webOS's update check back on while either of them keeps it off.
- **Saved originals.**  What each update setting was before anything turned it off is saved once (`switch.orig`, `auto.orig`; from LG-USB-2-ETH0's record if it turned the setting off first) and logged in `originals.log`, which is only ever appended to.  A saved original is only deleted once it has been put back.
- **Restart,** only when you choose it in the app or run `restart`: the Homebrew Channel's own call (`com.webos.service.tvpower/power/reboot`, then `reboot` if that fails), after writing everything to storage, and refused while the updater or a USB update is busy.
- **Updates,** only when you ask: **Updates** in the app, or `update-check`, asks GitHub for the latest release (`api.github.com` and `github.com`, with Node.js and `update.js`).  It only accepts a release whose Homebrew Channel manifest is signed with the project's release key or its backup key (below), and only an IPK at this app's own release address for exactly that version.  `update-install` then hands that IPK's address and SHA-256 to the Homebrew Channel's own installer (`org.webosbrew.hbchannel.service/install`), which downloads it and installs it only if the SHA-256 matches, and opens the app again.  The private half of the release key is only in an encrypted GitHub Actions secret, used to sign each release; the backup key's private half is kept offline, to bring in a new release key if that one is ever lost.
- **Never** changes the Homebrew Channel's settings or files, LG-USB-2-ETH0's settings, lines or rules, another program's firewall chains, or LG's flag files (`.nsuServerType*`, `.forceUpdateFlagFile`, the debug files: only reported).
- **Its working files** are in `/tmp/webos-fw-block`.  `/tmp` is shared with every program on the TV, so each run makes sure that's a real folder owned by root that nobody else can open, and moves anything else found there out of the way first.

It opens no ports and sends nothing about you or your TV anywhere.  The only network requests it ever makes are the update check and download above, and only when you ask for them.

## Verifying a download

Every release is signed with this key, in [minisign](https://jedisct1.github.io/minisign/)'s format:

```
RWQyan7EPkJW9+KGMzThbQap5637AGhavzN+fDTC4vl4FLLQc0zKdzP9
```

If that key is ever lost, a release signed with the backup key brings in a new one:

```
RWRN/D4IwUk2lLzkmxyap22UKY0boFGZwFIxu9MzQEVIaoumsdWWmY6G
```

Each release has a `.minisig` file next to the IPK, the script, the manifest, the translated changelogs (`changelog.es.md`, `changelog.ru.md`) and `SHA256SUMS`.  The app only shows translated release notes whose signature checks out, the same way as the manifest.  To check one:

```sh
minisign -Vm org.ohmybahgosh.fwblock_0.1.0_all.ipk -P RWQyan7EPkJW9+KGMzThbQap5637AGhavzN+fDTC4vl4FLLQc0zKdzP9
```

## Known limits

- Anything that can already run commands as root on the TV can undo the block.  The 10-minute check puts it back, but can't stop a program that's determined to.
- If LG adds an update server or address it doesn't know, it isn't blocked until it's added here.  The update check being off still stops the updater asking, as far as we know.  Seen one?  Please report it.
- It can't undo a firmware update that already installed, and it won't stop one that's already installing.
- A download is noticed within about 30 seconds and cancelled through the updater's own cancel.  That was confirmed in code and in an emulator, not yet on a TV mid-download.
- An LG Remote Support session you start is your own choice.  FW Block blocks Remote Support's servers and stops downloads, but don't start one.  Phone apps can't start an update once the TV has restarted with FW Block on; before that restart, don't accept one.
