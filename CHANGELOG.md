# Changelog

All notable changes to WEBOS-FW-BLOCK.  Versions follow [semantic versioning](https://semver.org/).

## [0.1.2] - 2026-11-20

### Added

- **What's new in your language.**  After an update, and when the app offers one, the release notes show in Spanish or Russian when the app is set to one of them.  The translated notes come signed with the release, and are checked the same way before they're shown.

### Fixed

- **No more "couldn't reach GitHub" when the app first opens.**  The first check could lose GitHub's answer, or run before the TV's network was up.  The app now holds on to every request until it's answered, and quietly tries a check that couldn't reach GitHub again a few times before saying so.

## [0.1.1] - 2026-11-20

### Added

- **What each block does,** in the More tab: every block explained in more detail, one page each, with what it stops and how.
- **Restart the TV from the app.**  After turning the block (or Phone apps) on, the app offers to restart the TV right away, so the phone app block takes hold now instead of at the next start.  Choosing Phone apps while it waits offers it too.  It's the Homebrew Channel's own restart call, and it's refused while the TV is installing or downloading an update (`restart` over SSH).

### Changed

- **Bigger text in every popup,** and the whole app now scales to fit TVs whose browser doesn't scale it to the screen.  Long lists in a popup scroll to follow the selection.

### Fixed

- **Ready for the Homebrew Channel's next update block.**  A pending Homebrew Channel change (webosbrew PR #264) makes its Block system updates turn webOS's update check off too.  FW Block now sees when the installed Homebrew Channel does that, never turns the update check back on behind it (turning FW Block off, restoring a backup or uninstalling), and names the Homebrew Channel as what keeps it off.
- **The real original settings, whatever order the blockers were turned on.**  If LG-USB-2-ETH0 turned webOS's update check or Automatic software update off first, FW Block now saves what LG-USB-2-ETH0 recorded as the original, not the "off" it left behind, and saves it even while LG-USB-2-ETH0 keeps the setting, so it's known if that block is turned off first.  Every original saved, and where it came from, is written to a log that's never rewritten.  Automatic software update is no longer turned back on while LG-USB-2-ETH0 keeps it off.
- **Nothing is lost when something can't be undone.**  If a setting can't be put back, its saved original is kept to try again, instead of being deleted.  Uninstalling only removes FW Block's startup hook and folder once everything is undone, and retries at the next check or start until it is.
- **Uninstalls are only detected when the app storage is really there.**  If the Homebrew Channel's own app isn't visible either (storage not mounted yet), FW Block doesn't take its own app's absence for an uninstall.
- **Safer writes.**  Its settings file is written to a new file and checked before it replaces the old one, so a full disk can't leave it half written.  Taking its lines out of `/etc/hosts` keeps a copy of the file first and checks that exactly its own lines went and every other line is unchanged before writing.
- **Backups record the other blockers too:** whether the Homebrew Channel's block is on and keeps the update check off, LG-USB-2-ETH0's settings file and what it saved as the originals, and FW Block's own log of originals.

## [0.1.0] - 2026-11-19

> **This is the first version, so bugs may occur.**  It has run on a real LG C2 (webOS 25) and passes its tests on a fake TV, but it hasn't met many TVs yet.  If something looks wrong, please open a [bug report](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/issues/new?template=bug-report.yml) with the app's **Help and report**, and a [TV report](https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/issues/new?template=tv-report.yml) helps even when it works.

The firmware update block from LG-USB-2-ETH0's `--block-updates`, as an app of its own, so you don't need a USB network adapter to use it.  Then hardened against every route to an update we found by running LG's own updater, from a C2's firmware, in an emulator on a closed network, and checking the update code of nine firmwares, from a 2018 OLED to 2025 models and webOS 26.

### Added

- **Block firmware updates, with one button.**  Right away and at every start:
  - webOS's hidden update check (`softwareUpdateEnable`) and the visible **Automatic software update** (`automaticUpdate`) are turned off.  The automatic check reads both.
  - An update webOS already found is deleted before it can install.
  - All seven of LG's update servers go nowhere in `/etc/hosts`: `snu`, `su`, `su-ssl`, `su-dev`, `snu-dev`, `nsu` and `ngfts.lge.com`.
  - `156.147.69.32` is dropped by a firewall rule, in a chain of its own.  The updater goes straight to that address, with no name to block, when LG switches it to its "network" server.
- **LG Remote Support is blocked too.**  During a support session, LG can hand the updater a download directly, skipping every check.  Its servers (`rone-*.lge.com`) and addresses (`165.244.62.249`, `165.244.99.174`) are blocked unless you turn that off in the app.
- **Phone apps can't start an update.**  A paired phone app with LG's "update from remote app" permission can make the TV update from a file on the phone, over your home network, past every server block.  FW Block covers the phone gateway's update file with a copy that keeps only the read-only version calls.  Casting, remote control and every other phone feature are unchanged.  It holds from the next TV start.
- **Downloads that start anyway are stopped.**  From a support session or the antenna: within 30 seconds, the download is cancelled and the TV shows a notice.  An install that's already running is only reported, because stopping one could break the TV, and USB updates you start yourself are left alone.
- **A menu like LG-USB-2-ETH0's, sized for the big screen.**  Tabs (Blocks, Activity, More) and a switch for each part, with a line on what it does: Block firmware updates, LG Remote Support, Phone apps and Stop downloads.  The status lists every block with who keeps it: FW Block, LG-USB-2-ETH0 or the Homebrew Channel.  A part another app keeps says so instead of offering a switch.  Over SSH: `phone on|off` and `guard on|off`.
- **Uninstalling cleans up.**  Removed from the Homebrew Channel or the TV, FW Block undoes its changes within 30 seconds (or at the next start) and deletes its hook and folder.  An app update doesn't count.
- **Kept closed.**  Every 10 minutes it checks each part, puts back anything that undid it, deletes an update webOS found, and counts the times it stopped the updater or Remote Support.  **What it caught** lists all of it.
- **Reports LG's flag files** without changing them: a switch to another update server (and whether the firewall rule is what stops it), a forced update, and debug overrides.
- **Plays well with others.**  It only adds the servers nothing else blocks yet, so the Homebrew Channel's own Block system updates is left alone.  When LG-USB-2-ETH0's `--block-updates` is on, that one keeps the main blocks and FW Block adds only what it lacks: phone apps and the download watch, and Automatic software update and Remote Support unless that ETH0 (2.11.45 and later) already keeps them.  It takes over within 10 minutes if ETH0's block is turned off.  It never changes the Homebrew Channel or another app.
- **Turn the block off** puts both update settings back the way they were (the hidden one stays off while LG-USB-2-ETH0 still blocks updates) and takes out everything it added.
- **Automatic backups.**  Before it turns the block on, restores a backup or installs an update, FW Block saves webOS's two update settings, its own switches, a copy of `/etc/hosts`, the phone gateway's update file and the firewall's rules.  **Backups** in the app (or `backups` and `restore NAME`) lists them and puts one back.  The newest 10 are kept.
- **Updates from the app, signed.**  When the app opens it asks GitHub for a newer release, and **Updates** installs it through the Homebrew Channel.  Only a release signed with the project's release key (or its backup key) is accepted, and the Homebrew Channel checks the download's SHA-256 before installing.  The app opens again afterwards and shows what's new.  It's the only network request FW Block makes, and only from the app or `update-check`.
- English, Spanish and Russian.
- MIT License.
