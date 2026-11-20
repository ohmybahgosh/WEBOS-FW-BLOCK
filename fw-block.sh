#!/bin/sh
# WEBOS-FW-BLOCK: keep LG firmware updates off a rooted LG webOS TV.
#
# A firmware update can patch the exploit a TV was rooted with and take root
# away for good, along with everything installed through the Homebrew
# Channel.  This closes every part of LG's update path we know of (mapped by
# running the C2's own updater in an emulator on a closed network), checks
# that it stays closed, and puts back anything that opened it again:
#
#   1. webOS's own update check (the hidden support/softwareUpdateEnable
#      setting) is turned off, so the updater doesn't even ask.  It's a
#      saved setting, so it already holds at the next start, before any
#      other part is in place.  The visible "Automatic software update"
#      (support/automaticUpdate), which the automatic check also reads, is
#      turned off too.
#   2. Update details webOS already found or downloaded are deleted, so a
#      found update can't be installed.
#   3. The update servers (snu, su, su-ssl, su-dev, snu-dev, nsu and ngfts
#      .lge.com) go nowhere in /etc/hosts.  Only the ones nothing else
#      blocks yet are added, so the Homebrew Channel's own block and others
#      are left alone.
#   4. The address the updater uses with its "networkupdate" server type
#      (156.147.69.32, no name to block) is dropped by a firewall rule, in a
#      chain of its own (FWBLOCK).
#   5. LG Remote Support (remotediag) can hand the updater a download address
#      directly, skipping the check.  Its servers (rone-*.lge.com) and
#      addresses (165.244.62.249, 165.244.99.174) are blocked too, unless
#      that's turned off ("remote off").
#   6. A paired phone app can't start an update.  The TV's phone gateway
#      (second screen) reads what phones may call from one file per
#      service; the update service's file is covered by a copy that keeps
#      only its read-only version calls.  A phone-pushed update downloads
#      straight from the phone over the home network, so no server block
#      reaches it.  Casting, remote control, the ThinQ app and every other
#      phone feature use other files and keep working.  The gateway reads
#      the file when it starts, so this takes hold at the next start.
#   7. A download that starts anyway (from a remote session or the antenna)
#      is noticed within 30 seconds and cancelled.  An install
#      that's already running is only reported: stopping one could break the
#      TV.  USB updates, which you start yourself, are left alone.
#
# Every 10 minutes it checks all of the above and puts back anything that
# was undone.  It also reports LG's own server switch, forced update and
# debug flag files, without changing them.
#
# Runs as root under busybox sh, from the TV app (through the Homebrew
# Channel's exec service), from its startup hook, or over SSH.  It never
# changes the Homebrew Channel's settings or another app's files.  When
# LG-USB-2-ETH0's --block-updates is on, that one keeps blocks 1 to 4 and
# this adds only what it lacks: phone apps and the download watch, and the
# visible setting and Remote Support unless that ETH0 (2.11.45 and later)
# keeps them too.  So the two never fight.  Everything it does is undone
# by "off".
#
# Usage: sh fw-block.sh COMMAND
#   status [--json]   what's blocked, what isn't, and who blocks it
#   on                block now and at every start (adds the startup hook)
#   off               undo everything this added and remove the hook
#   remote on|off     block LG Remote Support too (on by default)
#   phone on|off      block phone apps from starting an update (on by default)
#   guard on|off      stop downloads that start anyway (on by default)
#   check [--json]    check now and put back anything that was undone
#   events [--json]   what the block has caught and fixed, newest last
#   report            a short summary for asking for help
#   restart           restart the TV now (so the phone app block takes hold);
#                     refused while the TV is installing or downloading an update
#   backup | backups [--json] | restore NAME
#                     a backup of what FW Block and webOS's update settings
#                     were (made by itself before every change), the list,
#                     and putting one back
#   update-check [LANG] | update-install | update-status | changes [VERSION]
#                     a newer FW Block from GitHub, checked against the
#                     release key before the Homebrew Channel installs it
#   boot | watch      used by the startup hook and the background check
#   version
#
# Paths can be moved under FB_ROOT for the tests.

VERSION="1.0.0"
R="${FB_ROOT:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
SELF="$HERE/fw-block.sh"
APP_ID=org.ohmybahgosh.fwblock
# Where the Homebrew Channel installs the app
APP_DIR="$R/media/developer/apps/usr/palm/applications/$APP_ID"

# This script's settings, what it found, and what it changed
DATA="$R/var/lib/webosbrew/webos-fw-block"
CONF="$DATA/settings"
# What webOS's two update settings were before this turned them off, so
# "off" can put them back
ORIG="$DATA/switch.orig"
AUTO_ORIG="$DATA/auto.orig"
# Counts kept across restarts: tries=, last=, found=, fixed=, fixedWhat=,
# server=, remote=, cancelled=
STATS="$DATA/stats"
# "TIME KIND DETAIL", newest last, the last 50
EVENTS="$DATA/events"
# Backups FW Block makes before it changes anything, newest last
BACKUPS="$DATA/backups"
KEEP_BACKUPS="${FB_KEEP_BACKUPS:-10}"
# The startup hook: the Homebrew Channel runs init.d with run-parts
HOOK="$R/var/lib/webosbrew/init.d/50-webos-fw-block"
# Per-start state, in RAM: the background check's PID, firewall counts, the
# writable copy of /etc/hosts.  Its own folder only root can write.
RUN="$R/tmp/webos-fw-block"
PIDF="$RUN/watch.pid"
HITS="$RUN/hits"
RHITS="$RUN/rhits"
LAST="$RUN/last"
SEEN="$RUN/update-seen"
# Updating this app: the last check, the install's state and log
UPD="$RUN/self-update"
NODE="${FB_NODE:-}"
HOSTS="${FB_HOSTS:-$R/etc/hosts}"
PREFS="$R/var/luna/preferences"
# The Homebrew Channel's own Block system updates (four servers in /etc/hosts)
HBC_FLAG="$PREFS/webosbrew_block_updates"
CMN="$R/mnt/lg/cmn_data"
# Where webOS keeps an update it found or downloaded
SWUPDATE="$CMN/swupdate"
# Flag files that send the updater to another server type
UPD_FLAGS="$CMN/update"
# Files the updater keeps while it works: a network update (also during a
# check), a USB update, and either one in progress
NSU_RUNNING="$R/tmp/nsu-running"
USB_RUNNING="$R/tmp/usbupdate-running"
IN_PROGRESS="$CMN/.UpdateIsInprogress"
OS_INFO="$R/var/run/nyx/os_info.json"
LUNA="${FB_LUNA:-luna-send}"
IPT="${FB_IPTABLES:-iptables}"
# Seconds before the first full check after a start, between full checks,
# and between the quick looks for a download that started
FIRST="${FB_FIRST:-60}"
EVERY="${FB_EVERY:-600}"
QUICK="${FB_QUICK:-30}"

# LG-USB-2-ETH0's own update block: its settings, hook, hosts lines and rule
ETH0_CONF="$R/var/lib/webosbrew/lg-usb-2-eth0.conf"
ETH0_HOOK="$R/var/lib/webosbrew/init.d/S01fix-eth"
# What LG-USB-2-ETH0 saved as the update settings' values before it turned
# them off (it puts them back from these when its block is turned off)
ETH0_UPD_MARK="$R/var/lib/webosbrew/lg-usb-2-eth0.updates"
ETH0_AUTO_MARK="$R/var/lib/webosbrew/lg-usb-2-eth0.autoupdate"
# The Homebrew Channel's service, to see whether its Block system updates
# also turns webOS's update check off (webosbrew PR #264 and later)
HBC_SVC="$R/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service"
HBC_APP="$R/media/developer/apps/usr/palm/applications/org.webosbrew.hbchannel"
# Every original value FW Block saved, and where it came from, never
# rewritten: the record to fall back on if anything goes wrong
JOURNAL="$DATA/originals.log"
ETH0_TAG="# lg-usb-2-eth0 block-updates"
# Its own phone app block's mark: boot, or now (from the next TV start)
ETH0_PHONE_MARK="$R/tmp/lg-usb-2-eth0/lg-usb-2-eth0.phone"

TAG="# webos-fw-block"
RTAG="# webos-fw-block remote-support"
CHAIN=FWBLOCK
UPD_HOSTS="snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com nsu.lge.com ngfts.lge.com"
UPD_IP=156.147.69.32
# LG Remote Support (remotediag): its servers, and the addresses it reaches
# without a name
RS_HOSTS="rone-tv-aic.lge.com rone-tv-cic.lge.com rone-tv-eic.lge.com rone-tv-kic.lge.com rone-tv-saic.lge.com rone-aic.lge.com rone-eic.lge.com rone-kic.lge.com rone-saic.lge.com"
RS_IPS="165.244.62.249 165.244.99.174"
# What the TV's phone gateway lets paired phone apps call on the update
# service.  The same path on every firmware checked, 2018 to 2025.
SSG_IF="$R/usr/palm/services/com.webos.service.secondscreen.gateway/interfaces/com.webos.service.update.interface"
SSG_COPY="$RUN/update.interface"
# "boot" when the copy went in at start (before the gateway reads it), or
# "now" when it went in later and holds from the next start
SSG_MARK="$RUN/phone"

say() { printf '%s\n' "$*"; }
die() { say "$*" >&2; exit 1; }
now() { date +%s; }
# luna-send reads its input, so give it none: from a pipe it would eat it
luna() { "$LUNA" "$@" < /dev/null; }

# JSON string, with the characters JSON needs escaped
js() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\010\013-\037' | tr '\t\n' '  ')"
}
jb() { if [ -n "$1" ]; then printf true; else printf false; fi; }
# A JSON number, or 0
jn() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
# A space-separated list as a JSON array of strings
ja() {
    _ja='' _jf=''
    for _x in $1; do _ja="$_ja$_jf$(js "$_x")"; _jf=,; done
    printf '[%s]' "$_ja"
}

# $RUN is in /tmp, which every program on the TV can write to.  This runs
# and mounts files from there as root, so it has to be a real folder only
# root can write.  Anything else in its place is moved out of the way.
secure_run() {
    if [ -L "$RUN" ] || { [ -e "$RUN" ] && [ ! -d "$RUN" ]; }; then
        mv -f "$RUN" "$RUN.bad.$$" 2>/dev/null || rm -f "$RUN"
    fi
    if [ -d "$RUN" ] && [ "$(stat -c %u "$RUN" 2>/dev/null)" != "$(id -u)" ]; then
        mv -f "$RUN" "$RUN.bad.$$" 2>/dev/null
    fi
    mkdir -p "$RUN" && chmod 700 "$RUN"
}

# ------------------------------------------------------------- settings

conf_get() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | awk 'NR == 1'; }
# conf_set KEY VALUE: written to a new file, checked, then moved over the
# old one, so a full disk or a crash never leaves a half-written settings file
conf_set() {
    mkdir -p "$DATA" && chmod 700 "$DATA" || return 1
    _cn=0; [ -f "$CONF" ] && _cn=$(grep -cv "^$1=" "$CONF")
    { grep -v "^$1=" "$CONF" 2>/dev/null; echo "$1=$2"; } > "$CONF.new" 2>/dev/null
    if [ "$(wc -l < "$CONF.new" 2>/dev/null)" -eq $((_cn + 1)) ] 2>/dev/null && grep -qx "$1=$2" "$CONF.new"; then
        mv -f "$CONF.new" "$CONF"
    else
        rm -f "$CONF.new"
        say "Could not save the setting $1 (is the TV's storage full?).  Nothing was changed."
        return 1
    fi
}

# write_file FILE VALUE: the same, for a one-line file
write_file() {
    mkdir -p "${1%/*}" || return 1
    echo "$2" > "$1.new" 2>/dev/null && [ "$(cat "$1.new" 2>/dev/null)" = "$2" ] && mv -f "$1.new" "$1" && return 0
    rm -f "$1.new"
    return 1
}
setting_on() { [ "$(conf_get BLOCK)" = 1 ]; }
# Blocking LG Remote Support is on unless it was turned off
remote_on() { [ "$(conf_get REMOTE)" != 0 ]; }
# Phone apps and the download watch: on unless turned off
phone_on() { [ "$(conf_get PHONE)" != 0 ]; }
guard_on() { [ "$(conf_get GUARD)" != 0 ]; }

stat_get() { sed -n "s/^$1=//p" "$STATS" 2>/dev/null | awk 'NR == 1'; }
stat_set() {
    mkdir -p "$DATA"
    { grep -v "^$1=" "$STATS" 2>/dev/null; echo "$1=$2"; } > "$STATS.new" && mv -f "$STATS.new" "$STATS"
}
stat_inc() {
    _si=$(stat_get "$1")
    case "$_si" in ''|*[!0-9]*) _si=0 ;; esac
    stat_set "$1" $((_si + ${2:-1}))
}

# event KIND [DETAIL]: note what happened, keeping the last 50
event() {
    mkdir -p "$DATA"
    { tail -n 49 "$EVENTS" 2>/dev/null; echo "$(now) $1${2:+ $2}"; } > "$EVENTS.new" && mv -f "$EVENTS.new" "$EVENTS"
}

# A notice on the TV screen, best effort
toast() {
    luna -n 1 luna://com.webos.notification/createToast \
        "{\"sourceId\":\"$APP_ID\",\"message\":\"$1\"}" >/dev/null 2>&1
}

# ------------------------------------------------------------- other blockers

# LG-USB-2-ETH0 blocks updates itself: --block-updates saved and its hook in
# place.  It was here first, so it keeps blocks 1 to 4 and this adds the rest.
eth0_blocking() {
    [ -e "$ETH0_HOOK" ] || [ -L "$ETH0_HOOK" ] || return 1
    grep -q '^BLOCK_UPDATES="1"$' "$ETH0_CONF" 2>/dev/null
}
# Newer LG-USB-2-ETH0 (2.11.45 and later) also turns Automatic software
# update off with --block-updates, and blocks LG Remote Support with
# --block-remote-support.  Those are then its to keep, so the two never
# take turns restoring the same setting.
eth0_auto() { eth0_blocking && grep -q automaticUpdate "$ETH0_HOOK" 2>/dev/null; }
# The Homebrew Channel's Block system updates is on, and the installed
# Homebrew Channel turns webOS's update check off with it
hbc_keeps_check() {
    hbc_blocking || return 1
    grep -qs softwareUpdateEnable "$HBC_SVC/startup.sh" "$HBC_SVC"/*.js 2>/dev/null
}
# Something else wants webOS's update check off: then FW Block never turns
# it back on, even if it was on before FW Block
others_keep_check() { eth0_blocking || hbc_keeps_check; }
check_keeper() {
    if eth0_blocking; then echo eth0
    elif setting_on; then echo fw-block
    elif hbc_keeps_check; then echo hbc
    fi
}

# save_orig FILE CURRENT OTHER-MARK ALLOWED: what a setting was before
# anything turned it off, saved once.  If LG-USB-2-ETH0 turned it off first,
# its saved value is the real original, not the "off" it left behind.
save_orig() {
    [ -f "$1" ] && return 0
    _ov=$2; _os=current
    _om=$(cat "$3" 2>/dev/null)
    case " $4 " in *" $_om "*) [ -n "$_om" ] && { _ov=$_om; _os=lg-usb-2-eth0; } ;; esac
    case " $4 " in *" $_ov "*) [ -n "$_ov" ] || return 0 ;; *) return 0 ;; esac
    mkdir -p "$DATA" && chmod 700 "$DATA"
    write_file "$1" "$_ov" || { say "Could not save what ${1##*/} was."; return 1; }
    echo "$(now) ${1##*/} $_ov from $_os" >> "$JOURNAL" 2>/dev/null
}
eth0_rs() {
    [ -e "$ETH0_HOOK" ] || [ -L "$ETH0_HOOK" ] || return 1
    grep -q '^BLOCK_RS="1"$' "$ETH0_CONF" 2>/dev/null
}
# Newer LG-USB-2-ETH0 also blocks phone apps (BLOCK_PHONE) and stops
# downloads (STOP_DL) with --block-updates, both on unless set to "0".  Its
# startup hook (S01fix-eth) runs after this one (50-), so this one leaves
# them to it rather than taking them first.
eth0_phone() {
    eth0_blocking && grep -q secondscreen.gateway "$ETH0_HOOK" 2>/dev/null || return 1
    ! grep -q '^BLOCK_PHONE="0"$' "$ETH0_CONF" 2>/dev/null
}
eth0_guard() {
    eth0_blocking && grep -q dl_guard "$ETH0_HOOK" 2>/dev/null || return 1
    ! grep -q '^STOP_DL="0"$' "$ETH0_CONF" 2>/dev/null
}
eth0_installed() { [ -f "$ETH0_CONF" ] || [ -e "$ETH0_HOOK" ] || [ -L "$ETH0_HOOK" ]; }
hbc_blocking() { [ -e "$HBC_FLAG" ]; }

# Who else has lines in /etc/hosts or rules for the update path, by name
others() {
    _o=''
    hbc_blocking && _o="$_o hbc"
    eth0_blocking && _o="$_o eth0"
    grep -q "$ETH0_TAG" "$HOSTS" 2>/dev/null && ! eth0_blocking && _o="$_o eth0-leftover"
    grep -q 'APL Launcher' "$HOSTS" 2>/dev/null && _o="$_o apl-launcher"
    _rules=$(fw_rules)
    case "$_rules" in *LG_LOCKOUT*) _o="$_o webos-lockout" ;; esac
    case "$_rules" in *LGTVBLK*) _o="$_o lg-tv-blocklist" ;; esac
    echo "${_o# }"
}

# ------------------------------------------------------------- webOS's update settings

# sup_get KEY: a setting in webOS's "support" category, or nothing when it
# can't tell.  softwareUpdateEnable is true/false, automaticUpdate on/off.
sup_get() {
    luna -n 1 luna://com.webos.settingsservice/getSystemSettings \
        "{\"category\":\"support\",\"keys\":[\"$1\"]}" 2>/dev/null |
        sed -nE "s/.*\"$1\":[[:space:]]*\"?(true|false|on|off)\"?.*/\\1/p" | awk 'NR == 1'
}
sup_set() {
    case "$(luna -n 1 luna://com.webos.settingsservice/setSystemSettings \
        "{\"category\":\"support\",\"settings\":{\"$1\":\"$2\"}}" 2>/dev/null)" in
        *'"returnValue":true'*|*'"returnValue": true'*) return 0 ;;
    esac
    return 1
}
switch_get() { sup_get softwareUpdateEnable; }
auto_get() { sup_get automaticUpdate; }

# The visible "Automatic software update": off, remembering what it was once
auto_off() {
    _a=$(auto_get)
    save_orig "$AUTO_ORIG" "$_a" "$ETH0_AUTO_MARK" "on off" || return 1
    if [ "$_a" = on ]; then
        if sup_set automaticUpdate off; then say "Turned Automatic software update off."; else say "Could not turn Automatic software update off."; fi
    fi
}
# Puts it back only when nothing else keeps it off; the saved value is only
# deleted once that's done (a failed write keeps it, to try again)
auto_restore() {
    [ -f "$AUTO_ORIG" ] || return 0
    if [ "$(cat "$AUTO_ORIG" 2>/dev/null)" = on ]; then
        if eth0_auto; then
            say "Left Automatic software update off: LG-USB-2-ETH0 still keeps it off."
        elif sup_set automaticUpdate on; then
            say "Turned Automatic software update back on."
        else
            say "Could not turn Automatic software update back on."
            return 1
        fi
    fi
    rm -f "$AUTO_ORIG"
}

# ------------------------------------------------------------- /etc/hosts

# hosts_scan LIST blocked|missing: the names in LIST that some line in
# /etc/hosts sends nowhere (0.0.0.0, ::, 127.x or ::1), whoever added it,
# or the ones nothing blocks
hosts_scan() {
    awk -v list="$1" -v want="$2" '
        BEGIN { n = split(list, a, " ") }
        { sub(/#.*/, "") }
        NF >= 2 && ($1 == "0.0.0.0" || $1 == "::" || $1 == "::1" || $1 ~ /^127\./) {
            for (i = 2; i <= NF; i++) b[$i] = 1
        }
        END {
            for (j = 1; j <= n; j++)
                if ((want == "blocked") == (a[j] in b)) printf "%s ", a[j]
        }' "$HOSTS" 2>/dev/null | sed 's/ $//'
}
hosts_missing() {
    _hl=${1:-$UPD_HOSTS}
    if [ -r "$HOSTS" ]; then hosts_scan "$_hl" missing; else echo "$_hl"; fi
}
hosts_blocked() { hosts_scan "${1:-$UPD_HOSTS}" blocked; }
# How many update servers this added (one line each for IPv4 and IPv6)
hosts_ours() { grep "^0\.0\.0\.0.*$TAG\$" "$HOSTS" 2>/dev/null | grep -cv "$RTAG"; }

# /etc/hosts is read-only on webOS unless something (like the Homebrew
# Channel's own block) put a writable copy over it.  FB_NOMOUNT stands in
# for the mount in the tests.
hosts_writable() {
    [ -n "${FB_NOMOUNT:-}" ] && [ -f "$R/.hosts_ro" ] && return 1
    ( : >> "$HOSTS" ) 2>/dev/null
}
hosts_make_writable() {
    hosts_writable && return 0
    secure_run
    cp "$HOSTS" "$RUN/hosts" 2>/dev/null || return 1
    if [ -n "${FB_NOMOUNT:-}" ]; then
        rm -f "$R/.hosts_ro"
    else
        mount --bind "$RUN/hosts" "$HOSTS" 2>/dev/null || return 1
    fi
    : > "$RUN/mounted"
    hosts_writable
}
# hosts_add LIST TAG WHAT: add the names in LIST nothing blocks yet
hosts_add() {
    _miss=$(hosts_missing "$1")
    [ -n "$_miss" ] || return 0
    if ! hosts_make_writable; then say "Could not add the $3 to /etc/hosts."; return 1; fi
    _hd=''
    grep -q "^$2\$" "$HOSTS" 2>/dev/null || _hd=1
    {
        [ -n "$_hd" ] && echo "$2"
        for _h in $_miss; do printf '0.0.0.0\t%s %s\n::\t%s %s\n' "$_h" "$2" "$_h" "$2"; done
    } >> "$HOSTS"
    say "Blocked $3 in /etc/hosts: $_miss"
}
# hosts_remove TAG: take out the lines with TAG.  Written in place: /etc/hosts
# may be a bind mount that can't be replaced.
#
# Checked before it's written: exactly the tagged lines go, every other line
# (the Homebrew Channel's, LG-USB-2-ETH0's, yours) stays as it was, and a
# copy of the file as it was is kept in $RUN/hosts.before.
hosts_remove() {
    grep -q "$1" "$HOSTS" 2>/dev/null || return 0
    hosts_writable || return 1
    secure_run
    cp "$HOSTS" "$RUN/hosts.before" 2>/dev/null || return 1
    grep -v "$1" "$RUN/hosts.before" > "$RUN/hosts.new" 2>/dev/null
    [ $? -le 1 ] || { rm -f "$RUN/hosts.new"; return 1; }
    _hb=$(wc -l < "$RUN/hosts.before"); _ht=$(grep -c "$1" "$RUN/hosts.before"); _hn=$(wc -l < "$RUN/hosts.new")
    if [ "$_hn" -ne $((_hb - _ht)) ] || grep -q "$1" "$RUN/hosts.new"; then
        say "Didn't change /etc/hosts: the new copy didn't come out right."
        rm -f "$RUN/hosts.new"
        return 1
    fi
    cat "$RUN/hosts.new" > "$HOSTS" || { cat "$RUN/hosts.before" > "$HOSTS"; rm -f "$RUN/hosts.new"; return 1; }
    rm -f "$RUN/hosts.new"
}

# ------------------------------------------------------------- firewall

have_ipt() { command -v "$IPT" >/dev/null 2>&1; }
fw_rules() { have_ipt && "$IPT" -S 2>/dev/null; }
fw_jump() { "$IPT" -C OUTPUT -j "$CHAIN" 2>/dev/null; }
# fw_has IP: our chain drops IP, and OUTPUT goes through our chain
fw_has() { have_ipt && "$IPT" -C "$CHAIN" -d "$1" -j DROP 2>/dev/null && fw_jump; }
fw_ours() { fw_has "$UPD_IP"; }
# Who drops the update address: fw-block, eth0, other, or nothing
fw_by() {
    if fw_ours; then echo fw-block; return 0; fi
    # Not our own chain's rule when nothing jumps to it
    _r=$(fw_rules | grep -v -- "^-A $CHAIN " | grep -E -- "-d $UPD_IP(/32)? .*-j DROP")
    [ -n "$_r" ] || return 0
    case "$_r" in *"-A OUTPUT "*) if eth0_blocking; then echo eth0; else echo other; fi ;; *) echo other ;; esac
}
# fw_add IP...: drop each IP in our chain, and send OUTPUT through it
fw_add() {
    have_ipt || return 0
    "$IPT" -N "$CHAIN" 2>/dev/null
    for _ip in "$@"; do
        "$IPT" -C "$CHAIN" -d "$_ip" -j DROP 2>/dev/null || "$IPT" -A "$CHAIN" -d "$_ip" -j DROP 2>/dev/null
    done
    fw_jump || "$IPT" -I OUTPUT 1 -j "$CHAIN" 2>/dev/null
    _bad=''
    for _ip in "$@"; do fw_has "$_ip" || _bad="$_bad $_ip"; done
    if [ -n "$_bad" ]; then say "Could not block${_bad}."; return 1; fi
    return 0
}
fw_del() {
    have_ipt || return 0
    for _ip in "$@"; do
        while "$IPT" -C "$CHAIN" -d "$_ip" -j DROP 2>/dev/null; do "$IPT" -D "$CHAIN" -d "$_ip" -j DROP 2>/dev/null || break; done
    done
}
fw_remove() {
    have_ipt || return 0
    _i=0
    while [ $_i -lt 10 ] && fw_jump; do "$IPT" -D OUTPUT -j "$CHAIN" 2>/dev/null; _i=$((_i + 1)); done
    "$IPT" -F "$CHAIN" 2>/dev/null
    "$IPT" -X "$CHAIN" 2>/dev/null
    return 0
}
# fw_hits IP...: packets our chain has stopped for them since the TV started
fw_hits() {
    have_ipt || return 0
    "$IPT" -L "$CHAIN" -n -v -x 2>/dev/null | awk -v ips=" $* " '
        $3 == "DROP" { d = $9; sub(/\/32$/, "", d); if (index(ips, " " d " ")) n += $1 }
        END { print n + 0 }'
}
# The Remote Support addresses not dropped by our chain
# ip_dropped IP: our chain drops it, or a plain OUTPUT rule does (as
# LG-USB-2-ETH0 adds them)
ip_dropped() {
    fw_has "$1" && return 0
    fw_rules | grep -qE -- "^-A OUTPUT -d $1(/32)? .*-j DROP"
}
rs_ips_open() {
    have_ipt || return 0
    _ro=''
    for _ip in $RS_IPS; do ip_dropped "$_ip" || _ro="$_ro $_ip"; done
    echo "${_ro# }"
}

# ------------------------------------------------------------- the updater

pending() { [ -e "$SWUPDATE/Image_Update_Info.xml" ] || [ -e "$SWUPDATE/Package_Update_Info.xml" ]; }
pending_clear() { rm -f "$SWUPDATE/Image_Update_Info.xml" "$SWUPDATE/Package_Update_Info.xml" 2>/dev/null; }

# The other server type webOS's updater was switched to, if any.  Network
# ("networkupdate") goes straight to 156.147.69.32, so the firewall rule is
# what stops it; the others use names the hosts lines block.
server_switch() {
    for _uf in Network Test SDP Origin; do
        [ -e "$UPD_FLAGS/.nsuServerType$_uf" ] && { echo "$_uf"; return 0; }
    done
    return 0
}
# LG's other flag files that matter: a forced update, and debug overrides
# (ignored on a retail TV, but worth knowing about)
lg_flags() {
    _f=''
    [ -e "$CMN/.forceUpdateFlagFile" ] && _f="$_f force"
    { [ -e "$CMN/debugVersionCheck" ] || [ -e "$CMN/debugDownload" ] || [ -e "$CMN/.UpdateDebug" ]; } && _f="$_f debug"
    echo "${_f# }"
}

# The updater's status (idle, check update, downloading, installing...).
# Only asked while one of its working files says it's busy, so the updater
# isn't woken up for nothing.
upd_busy() { [ -e "$NSU_RUNNING" ] || [ -e "$IN_PROGRESS" ] || [ -e "$USB_RUNNING" ]; }
upd_status() {
    luna -n 1 -w 5000 luna://com.webos.service.update/getStatus '{}' 2>/dev/null |
        sed -n 's/.*"status":[[:space:]]*"\([^"]*\)".*/\1/p' | awk 'NR == 1'
}

# The quick look, every 30 seconds: a download that started anyway is
# cancelled.  An install is only reported (stopping one could break the
# TV), and a USB update, which someone started on purpose, is left alone.
guard() {
    if ! upd_busy; then rm -f "$SEEN"; return 0; fi
    [ -e "$USB_RUNNING" ] && return 0
    _st=$(upd_status)
    case "$_st" in
        downloading*|*download*)
            luna -n 1 -w 5000 luna://com.webos.service.update/cancelUpdate '{}' >/dev/null 2>&1
            pending_clear
            event cancelled "$_st"
            stat_inc cancelled
            stat_set lastCancel "$(now)"
            toast "FW Block stopped a firmware download."
            say "$(date): stopped a firmware download ($_st)."
            ;;
        install*)
            if [ "$(cat "$SEEN" 2>/dev/null)" != installing ]; then
                event installing
                echo installing > "$SEEN"
                say "$(date): a firmware update is installing.  Stopping it could break the TV, so it was left alone."
            fi
            ;;
    esac
    return 0
}

# ------------------------------------------------------------- block, unblock

# ------------------------------------------------------------- phone apps

# A phone app can still ask the update service to update: the gateway's
# file still lists a call that needs the update permission
phone_open() { [ -f "$SSG_IF" ] && grep -q UPDATE_FROM_REMOTE_APP "$SSG_IF"; }
phone_ours() { [ -f "$SSG_MARK" ]; }
# The gateway already read the copy: it went in at start
phone_active() { [ "$(cat "$SSG_MARK" 2>/dev/null)" = boot ]; }
# phone_block WHEN: WHEN is boot or now
phone_block() {
    phone_open || return 0
    secure_run
    # Only the read-only calls the original has, as they are there
    {
        printf '{\n\t"service": "com.webos.service.update",\n\t"methods": [\n'
        _sep=''
        for _m in getCurrentSWInformation getVersion; do
            grep -q "\"/$_m\"" "$SSG_IF" || continue
            printf '%s\t\t{"path": "/%s", "requiredPermissions": ["READ_UPDATE_INFO"]}' "$_sep" "$_m"
            _sep=',
'
        done
        printf '\n\t]\n}\n'
    } > "$SSG_COPY"
    if [ -n "${FB_NOMOUNT:-}" ]; then
        cp "$SSG_IF" "$SSG_COPY.orig" && cat "$SSG_COPY" > "$SSG_IF" || return 1
    else
        mount --bind "$SSG_COPY" "$SSG_IF" 2>/dev/null || { say "Could not stop phone apps from starting an update."; return 1; }
    fi
    echo "${1:-now}" > "$SSG_MARK"
    if [ "${1:-now}" = boot ]; then
        say "Blocked phone apps from starting a firmware update."
    else
        say "Blocked phone apps from starting a firmware update, from the next TV start.  Casting and remote control keep working."
    fi
}
phone_unblock() {
    phone_ours || return 0
    if [ -n "${FB_NOMOUNT:-}" ]; then
        cat "$SSG_COPY.orig" > "$SSG_IF" || return 1
    else
        umount "$SSG_IF" 2>/dev/null || { say "Could not undo the phone app block."; return 1; }
    fi
    rm -f "$SSG_MARK" "$SSG_COPY" "$SSG_COPY.orig"
    say "Phone apps can start an update again from the next TV start."
}

# What's open now: any of check (webOS's update check is on), auto (the
# visible Automatic software update is on), hosts, firewall, remote (Remote
# Support isn't blocked), phone (a paired phone app can start an update),
# download (an update was found).  While
# LG-USB-2-ETH0 blocks updates, only the parts this adds are looked at.
# Changes nothing.
gaps() {
    _g=''
    if ! eth0_blocking; then
        [ "$(switch_get)" = false ] || _g="$_g check"
    fi
    if ! eth0_auto; then [ "$(auto_get)" = on ] && _g="$_g auto"; fi
    if ! eth0_blocking; then
        [ -z "$(hosts_missing)" ] || _g="$_g hosts"
        have_ipt && [ -z "$(fw_by)" ] && _g="$_g firewall"
    fi
    if remote_on && ! eth0_rs && { [ -n "$(hosts_missing "$RS_HOSTS")" ] || [ -n "$(rs_ips_open)" ]; }; then _g="$_g remote"; fi
    phone_on && ! eth0_phone && phone_open && _g="$_g phone"
    if ! eth0_blocking; then pending && _g="$_g download"; fi
    echo "${_g# }"
}

# block [WHEN]: WHEN is boot from the startup hook
block() {
    # First: at boot the phone gateway reads its files about 20 seconds
    # after the startup hooks run (measured on a C2), and the settings calls
    # below can be slow
    phone_on && ! eth0_phone && phone_block "${1:-now}"
    _s=$(switch_get)
    # Remember what it was, once, so "off" can put it back.  Saved even while
    # LG-USB-2-ETH0 keeps it off, so the real original is known if that
    # block is turned off first
    save_orig "$ORIG" "$_s" "$ETH0_UPD_MARK" "true false"
    if ! eth0_blocking; then
        if [ "$_s" != false ]; then
            if sup_set softwareUpdateEnable false; then say "Turned webOS's update check off."; else say "Could not turn webOS's update check off."; fi
        fi
    fi
    if eth0_auto; then save_orig "$AUTO_ORIG" "$(auto_get)" "$ETH0_AUTO_MARK" "on off"; else auto_off; fi
    if ! eth0_blocking; then
        if pending; then pending_clear; say "Deleted an update webOS had already found."; fi
        hosts_add "$UPD_HOSTS" "$TAG" "update servers"
        if have_ipt && ! fw_ours; then
            fw_add "$UPD_IP" && say "Blocked $UPD_IP, the address the updater uses without a name."
        fi
    fi
    if remote_on && ! eth0_rs; then
        hosts_add "$RS_HOSTS" "$RTAG" "LG Remote Support servers"
        if have_ipt && [ -n "$(rs_ips_open)" ]; then
            # shellcheck disable=SC2086 # one argument per address
            fw_add $RS_IPS && say "Blocked LG Remote Support's addresses: $RS_IPS"
        fi
    fi
    return 0
}

remote_unblock() {
    if hosts_remove "$RTAG"; then :; else say "Could not take the Remote Support servers out of /etc/hosts."; fi
    # shellcheck disable=SC2086 # one argument per address
    fw_del $RS_IPS
}

# Returns 1 if anything couldn't be undone, so nothing that's still needed
# (the saved originals, the startup hook) is deleted after it
unblock() {
    _uf=0
    if [ -f "$ORIG" ]; then
        _uo=$(cat "$ORIG" 2>/dev/null)
        if [ "$_uo" = true ]; then
            if eth0_blocking; then
                say "Left webOS's update check off: LG-USB-2-ETH0 still blocks updates."
            elif hbc_keeps_check; then
                say "Left webOS's update check off: the Homebrew Channel's Block system updates keeps it off."
            elif sup_set softwareUpdateEnable true; then
                say "Turned webOS's update check back on."
            else
                say "Could not turn webOS's update check back on."
                _uf=1
            fi
        fi
        [ $_uf = 0 ] && rm -f "$ORIG"
    fi
    auto_restore || _uf=1
    if hosts_remove "$TAG"; then :; else say "Could not take the update servers out of /etc/hosts."; _uf=1; fi
    fw_remove
    phone_unblock || _uf=1
    return $_uf
}

# ------------------------------------------------------------- the hook and the check

install_hook() {
    mkdir -p "$DATA" "${HOOK%/*}" && chmod 700 "$DATA"
    # At boot this runs from that copy when the app isn't installed
    [ "$SELF" -ef "$DATA/fw-block.sh" ] || cp "$SELF" "$DATA/fw-block.sh"
    cat > "$HOOK" <<EOF
#!/bin/sh
# Added by WEBOS-FW-BLOCK: blocks LG firmware updates at every start.
# Turn it off in the app, or: sh /var/lib/webosbrew/webos-fw-block/fw-block.sh off
# The app's own copy when it's installed (always the newest), or the one kept here
S=$DATA/fw-block.sh
A=$R/media/developer/apps/usr/palm/applications/$APP_ID/assets/fw-block.sh
[ -f "\$A" ] && S=\$A
[ -f "\$S" ] && (sh "\$S" boot < /dev/null > $DATA/boot.log 2>&1 &)
exit 0
EOF
    chmod 755 "$HOOK"
}
remove_hook() { rm -f "$HOOK" "$DATA/fw-block.sh"; }

# Uninstalling an app only deletes its folder; webOS runs nothing first.
# So when FW Block was turned on from the app (APP=1) and the app is gone,
# it undoes itself like "off", then removes its hook and its own folder.
# Checked twice a few seconds apart, so an app update (the folder replaced)
# doesn't count.  Turned on over SSH with no app, it never does this.
app_gone() {
    [ "$(conf_get APP)" = 1 ] || return 1
    # Not while an update of this app installs (its folder is replaced)
    if [ -f "$UPD/installing" ]; then
        _ui=$(cat "$UPD/installing" 2>/dev/null)
        case "$_ui" in ''|*[!0-9]*) _ui=0 ;; esac
        [ $(($(now) - _ui)) -lt 900 ] && return 1
    fi
    [ -f "$APP_DIR/appinfo.json" ] && return 1
    # The apps' storage has to be there: early in a start, or with it not
    # mounted, every app looks missing.  The Homebrew Channel (which runs
    # this) is one of them, so its app being there shows the storage is.
    [ -f "$HBC_APP/appinfo.json" ] || return 1
    sleep "${FB_GONE_WAIT:-5}"
    [ ! -f "$APP_DIR/appinfo.json" ] && [ -f "$HBC_APP/appinfo.json" ]
}
uninstalled() {
    say "$(date): the FW Block app was uninstalled, so it undoes its changes."
    # Only once everything is undone: otherwise the setting, the hook and the
    # saved originals stay as they are, and the next check or start tries again
    if ! unblock; then
        say "Not everything could be undone yet, so its startup hook and saved settings stay to try again."
        event uninstall-retry ""
        return 1
    fi
    conf_set BLOCK 0
    remove_hook
    [ -d "$RUN" ] && [ ! -L "$RUN" ] && rm -rf "$RUN"
    [ -d "$DATA" ] && [ ! -L "$DATA" ] && rm -rf "$DATA"
    return 0
}

watch_pid() {
    _p=$(cat "$PIDF" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_p" 2>/dev/null || return 1
    # A check that ended but wasn't reaped yet doesn't count
    case "$(cut -d ' ' -f 3 "/proc/$_p/stat" 2>/dev/null)" in Z) return 1 ;; esac
    echo "$_p"
}
watch_start() {
    watch_pid >/dev/null && return 0
    secure_run
    sh "$SELF" watch < /dev/null >> "$RUN/watch.log" 2>&1 &
    echo $! > "$PIDF"
}
watch_stop() {
    _p=$(watch_pid) || return 0
    kill "$_p" 2>/dev/null
    rm -f "$PIDF"
}

# count_hits FILE STAT KIND IP...: new packets our chain stopped for the IPs
# since the last look, counted as one try
count_hits() {
    _cf=$1 _cs=$2 _ck=$3; shift 3
    _h=$(fw_hits "$@")
    case "$_h" in ''|*[!0-9]*) return 0 ;; esac
    _p=$(cat "$_cf" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) _p=0 ;; esac
    # Fewer than last time: the rule was put back, so its count started over
    [ "$_h" -lt "$_p" ] && _p=0
    if [ "$_h" -gt "$_p" ]; then
        stat_inc "$_cs"
        [ "$_cs" = tries ] && stat_set last "$(now)"
        event "$_ck" "$((_h - _p))"
    fi
    echo "$_h" > "$_cf"
}

# One full check: put back anything that undid the block, remove a found
# update, count what the firewall stopped, note LG's flag files.
tick() {
    secure_run
    now > "$LAST"
    # After an app update, the copy the hook falls back on gets the new script
    _ac="$APP_DIR/assets/fw-block.sh"
    if [ -f "$_ac" ] && [ -f "$DATA/fw-block.sh" ] && ! [ "$_ac" -ef "$DATA/fw-block.sh" ] && ! cmp -s "$_ac" "$DATA/fw-block.sh"; then
        cp "$_ac" "$DATA/fw-block.sh.new" && mv -f "$DATA/fw-block.sh.new" "$DATA/fw-block.sh"
    fi
    if eth0_blocking; then
        [ "$(stat_get standby)" = 1 ] || { event standby eth0; stat_set standby 1; }
    elif [ "$(stat_get standby)" = 1 ]; then
        event resumed; stat_set standby 0
    fi
    _g=$(gaps)
    if [ -n "$_g" ]; then
        case " $_g " in *" download "*) event found; stat_set found "$(now)" ;; esac
        _u=$(echo " $_g " | sed 's/ download / /; s/^ *//; s/ *$//')
        if [ -n "$_u" ]; then
            event fixed "$(echo "$_u" | tr ' ' ,)"
            stat_set fixed "$(now)"
            stat_set fixedWhat "$(echo "$_u" | tr ' ' ,)"
        fi
        block >/dev/null
    fi
    # Only noted, not changed: LG's own files, and other parts may read them
    _sw=$(server_switch)
    if [ -n "$_sw" ] && [ "$_sw" != "$(stat_get server)" ]; then event server "$_sw"; stat_set server "$_sw"; fi
    _lf=$(lg_flags)
    if [ -n "$_lf" ] && [ "$_lf" != "$(stat_get flags)" ]; then event flags "$(echo "$_lf" | tr ' ' ,)"; stat_set flags "$_lf"; fi
    eth0_blocking || count_hits "$HITS" tries stopped "$UPD_IP"
    # shellcheck disable=SC2086 # one argument per address
    remote_on && ! eth0_rs && count_hits "$RHITS" remote remote $RS_IPS
    return 0
}

watch() {
    secure_run
    # Started some other way than watch_start: note it, unless one runs already
    if [ "$(cat "$PIDF" 2>/dev/null)" != $$ ]; then
        watch_pid >/dev/null && return 0
        echo $$ > "$PIDF"
    fi
    _next=$FIRST
    while setting_on && [ "$(cat "$PIDF" 2>/dev/null)" = $$ ]; do
        # Only stops once the clean-up worked; otherwise it tries again
        if app_gone; then uninstalled && return 0; fi
        guard_on && ! eth0_guard && guard
        if [ "$_next" -le 0 ]; then tick; _next=$EVERY; fi
        sleep "$QUICK"
        _next=$((_next - QUICK))
    done
    [ "$(cat "$PIDF" 2>/dev/null)" = $$ ] && rm -f "$PIDF"
}

# At every start, from the hook
boot() {
    setting_on || return 0
    if app_gone; then uninstalled; return 0; fi
    secure_run
    event boot
    if eth0_blocking; then
        say "$(date): LG-USB-2-ETH0 blocks updates, so this adds only what it lacks."
    else
        say "$(date): blocking."
    fi
    block boot
    now > "$LAST"
    watch_start
}

cmd_on() {
    backup_make on >/dev/null
    conf_set BLOCK 1
    # Turned on from the app's own copy: an uninstall later undoes it
    case "$SELF" in "$APP_DIR"/*) conf_set APP 1 ;; esac
    [ -n "$(conf_get REMOTE)" ] || conf_set REMOTE 1
    install_hook
    event on
    if eth0_blocking; then
        say "LG-USB-2-ETH0 already blocks firmware updates, so FW Block adds only what it lacks (see status).  If you turn that off, FW Block takes over within 10 minutes."
        event standby eth0
        stat_set standby 1
    else
        stat_set standby 0
    fi
    block
    secure_run
    now > "$LAST"
    watch_start
    say "Firmware updates are blocked, now and at every start."
}

cmd_off() {
    conf_set BLOCK 0
    watch_stop
    remove_hook
    # A part that couldn't be undone keeps what's needed to try again:
    # turning it off again retries it
    unblock || say "Something couldn't be undone (above).  Its saved settings are kept: turn FW Block off again to retry."
    # Its per-start files in RAM: counts and the check's log
    [ -d "$RUN" ] && [ ! -L "$RUN" ] && rm -rf "$RUN"
    event off
    hbc_blocking && say "The Homebrew Channel's own Block system updates is still on (it covers four servers)."
    eth0_blocking && say "LG-USB-2-ETH0 still blocks updates."
    say "FW Block is off."
}

cmd_phone() {
    case "${1:-}" in
        on)
            conf_set PHONE 1
            event phone-on
            if eth0_phone; then say "LG-USB-2-ETH0 already blocks phone apps, so FW Block leaves that to it."; return 0; fi
            if setting_on; then block >/dev/null; fi
            say "Phone apps can't start a firmware update while FW Block is on (from the next TV start if it's running now).  Casting and remote control keep working." ;;
        off)
            conf_set PHONE 0
            event phone-off
            if phone_ours; then phone_unblock; else say "Phone apps aren't blocked by FW Block."; fi ;;
        *) die "Usage: sh fw-block.sh phone on|off" ;;
    esac
}

cmd_guard() {
    case "${1:-}" in
        on)
            conf_set GUARD 1
            event guard-on
            if eth0_guard; then say "LG-USB-2-ETH0 already stops downloads, so FW Block leaves that to it."; return 0; fi
            say "A firmware download that starts anyway is stopped within 30 seconds while FW Block is on." ;;
        off)
            conf_set GUARD 0
            event guard-off
            say "Downloads are no longer watched.  The other blocks stay on." ;;
        *) die "Usage: sh fw-block.sh guard on|off" ;;
    esac
}

cmd_remote() {
    case "${1:-}" in
        on)
            conf_set REMOTE 1
            event remote-on
            if setting_on; then block >/dev/null; fi
            say "LG Remote Support is blocked while FW Block is on." ;;
        off)
            conf_set REMOTE 0
            event remote-off
            remote_unblock
            if eth0_rs; then
                say "FW Block no longer blocks LG Remote Support, but LG-USB-2-ETH0 still does (its --block-remote-support)."
            else
                say "LG Remote Support is no longer blocked.  LG can then start an update during a support session."
            fi ;;
        *) die "Usage: sh fw-block.sh remote on|off" ;;
    esac
}

# ------------------------------------------------------------- status

firmware() { sed -n 's/.*"webos_manufacturing_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$OS_INFO" 2>/dev/null | awk 'NR == 1'; }
webos() { sed -n 's/.*"webos_release"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$OS_INFO" 2>/dev/null | awk 'NR == 1'; }

# full, partial or none: webOS's update check, the update servers, the
# update address and found updates (the core blocks, whoever keeps them)
level() {
    _sw=$1 _miss=$2 _fw=$3 _pend=$4
    _ok=0 _of=2
    [ "$_sw" = false ] && _ok=$((_ok + 1))
    [ -z "$_miss" ] && _ok=$((_ok + 1))
    if have_ipt; then _of=3; [ -n "$_fw" ] && _ok=$((_ok + 1)); fi
    if [ "$_ok" = "$_of" ] && [ -z "$_pend" ]; then echo full
    # Nothing at all: not even one server blocked by something else
    elif [ "$_ok" = 0 ] && [ "$(echo "$_miss" | wc -w)" -ge 7 ]; then echo none
    else echo partial
    fi
}

status_json() {
    _sw=$(switch_get)
    _miss=$(hosts_missing)
    _bl=$(hosts_blocked)
    _fw=$(fw_by)
    _pend=''; pending && _pend=1
    _own=none
    if eth0_blocking; then _own=eth0; elif setting_on; then _own=fw-block; fi
    _rmiss=$(hosts_missing "$RS_HOSTS")
    _ropen=$(rs_ips_open)
    _rok=''; [ -z "$_rmiss" ] && [ -z "$_ropen" ] && _rok=1
    _busy=''; upd_busy && _busy=1
    printf '{'
    printf '"version":%s,' "$(js "$VERSION")"
    printf '"on":%s,"hook":%s,"watching":%s,"owner":%s,' "$(jb "$(setting_on && echo 1)")" "$(jb "$(test -f "$HOOK" && echo 1)")" \
        "$(jb "$(watch_pid)")" "$(js "$_own")"
    printf '"level":%s,"gaps":%s,' "$(js "$(level "$_sw" "$_miss" "$_fw" "$_pend")")" "$(ja "$(gaps)")"
    printf '"checkBy":%s,"hbcKeepsCheck":%s,' "$(js "$(check_keeper)")" "$(jb "$(hbc_keeps_check && echo 1)")"
    printf '"check":%s,"auto":%s,"hostsBlocked":%s,"hostsMissing":%s,"hostsOurs":%s,"hostsTotal":7,' \
        "$(js "$_sw")" "$(js "$(auto_get)")" "$(ja "$_bl")" "$(ja "$_miss")" "$(jn "$(hosts_ours)")"
    printf '"firewall":%s,"firewallBy":%s,"ip":%s,"pending":%s,"serverSwitch":%s,"lgFlags":%s,' \
        "$(jb "$(have_ipt && echo 1)")" "$(js "$_fw")" "$(js "$UPD_IP")" "$(jb "$_pend")" "$(js "$(server_switch)")" "$(ja "$(lg_flags)")"
    # Who keeps them: LG-USB-2-ETH0 or FW Block
    _aby=''; if eth0_auto; then _aby=eth0; elif setting_on; then _aby=fw-block; fi
    _rby=''; if eth0_rs; then _rby=eth0; elif setting_on && remote_on; then _rby=fw-block; fi
    printf '"autoBy":%s,' "$(js "$_aby")"
    printf '"remote":{"on":%s,"blocked":%s,"by":%s,"hostsMissing":%s,"ipsOpen":%s,"hostsTotal":9},' \
        "$(jb "$(remote_on && echo 1)")" "$(jb "$_rok")" "$(js "$_rby")" "$(ja "$_rmiss")" "$(ja "$_ropen")"
    _pp=''; [ -f "$SSG_IF" ] && _pp=1
    _pb=''; [ -n "$_pp" ] && ! phone_open && _pb=1
    # Blocked, but put in place after the gateway started: holds from the next start
    _pw=''; [ -n "$_pb" ] && phone_ours && ! phone_active && _pw=1
    # LG-USB-2-ETH0's own phone block, put in after its gateway started
    [ -n "$_pb" ] && ! phone_ours && [ "$(cat "$ETH0_PHONE_MARK" 2>/dev/null)" = now ] && _pw=1
    _pby=''
    if phone_ours; then _pby=fw-block; elif [ -n "$_pb" ] && [ -f "$ETH0_PHONE_MARK" ]; then _pby=eth0; elif [ -n "$_pb" ]; then _pby=other; fi
    # LG-USB-2-ETH0 keeps phone apps but hasn't blocked them yet (new setting, its hook runs at the next start)
    if [ -n "$_pp" ] && [ -z "$_pb" ] && eth0_phone; then _pw=1; _pby=eth0; fi
    _gby=''; if eth0_guard; then _gby=eth0; elif setting_on && guard_on; then _gby=fw-block; fi
    printf '"phone":{"on":%s,"present":%s,"blocked":%s,"nextStart":%s,"by":%s,"eth0":%s},' "$(jb "$(phone_on && echo 1)")" "$(jb "$_pp")" "$(jb "$_pb")" "$(jb "$_pw")" \
        "$(js "$_pby")" "$(jb "$(eth0_phone && echo 1)")"
    printf '"guard":%s,"guardBy":%s,' "$(jb "$(guard_on && echo 1)")" "$(js "$_gby")"
    printf '"updaterBusy":%s,' "$(jb "$_busy")"
    printf '"hbcBlock":%s,"eth0":{"installed":%s,"blocking":%s},"others":%s,' \
        "$(jb "$(hbc_blocking && echo 1)")" "$(jb "$(eth0_installed && echo 1)")" "$(jb "$(eth0_blocking && echo 1)")" "$(ja "$(others)")"
    printf '"stats":{"tries":%s,"last":%s,"found":%s,"fixed":%s,"fixedWhat":%s,"remote":%s,"cancelled":%s,"lastCancel":%s},' \
        "$(jn "$(stat_get tries)")" "$(jn "$(stat_get last)")" "$(jn "$(stat_get found)")" "$(jn "$(stat_get fixed)")" "$(js "$(stat_get fixedWhat)")" \
        "$(jn "$(stat_get remote)")" "$(jn "$(stat_get cancelled)")" "$(jn "$(stat_get lastCancel)")"
    printf '"lastCheck":%s,"every":%s,"now":%s,' "$(jn "$(cat "$LAST" 2>/dev/null)")" "$(jn "$EVERY")" "$(now)"
    printf '"firmware":%s,"webos":%s' "$(js "$(firmware)")" "$(js "$(webos)")"
    printf '}\n'
}

status_text() {
    _sw=$(switch_get)
    _miss=$(hosts_missing)
    _fw=$(fw_by)
    _pend=''; pending && _pend=1
    say "WEBOS-FW-BLOCK $VERSION"
    case "$(level "$_sw" "$_miss" "$_fw" "$_pend")" in
        full) say "Firmware updates: blocked" ;;
        partial) say "Firmware updates: partly blocked" ;;
        *) say "Firmware updates: NOT blocked" ;;
    esac
    if eth0_blocking && setting_on; then say "Blocked by: LG-USB-2-ETH0, with FW Block adding the rest"
    elif eth0_blocking; then say "Blocked by: LG-USB-2-ETH0 (FW Block is off)"
    elif setting_on; then say "Blocked by: FW Block, now and at every start"
    else say "FW Block: off"
    fi
    say "  update check:   ${_sw:-unknown}$([ "$_sw" = false ] && echo ' (off, good)')"
    _au=$(auto_get)
    say "  automatic update: ${_au:-unknown}$([ "$_au" = off ] && echo ' (good)')$(eth0_auto && echo ', kept by LG-USB-2-ETH0')"
    say "  update servers: $((7 - $(echo "$_miss" | wc -w))) of 7 blocked${_miss:+, open: $_miss}"
    if ! have_ipt; then say "  update address: no firewall on this TV"
    elif [ -n "$_fw" ]; then say "  update address: blocked ($_fw)"
    else say "  update address: open"
    fi
    if remote_on || eth0_rs; then
        _rm=$(hosts_missing "$RS_HOSTS"); _ro=$(rs_ips_open)
        if [ -z "$_rm" ] && [ -z "$_ro" ]; then say "  LG Remote Support: blocked$(eth0_rs && echo ' by LG-USB-2-ETH0')"
        elif [ "$(echo "$_rm" | wc -w)" = 9 ] && { ! have_ipt || [ "$(echo "$_ro" | wc -w)" = 2 ]; }; then say "  LG Remote Support: open"
        else say "  LG Remote Support: partly open${_rm:+ ($_rm)}${_ro:+ ($_ro)}"
        fi
    else
        say "  LG Remote Support: not blocked (turned off)"
    fi
    if [ -f "$SSG_IF" ]; then
        if phone_open && eth0_phone; then say "  phone apps:     open now, LG-USB-2-ETH0 blocks them from the next TV start"
        elif phone_open; then say "  phone apps:     can start an update$(phone_on || echo ' (turned off)')"
        elif ! phone_ours && [ -f "$ETH0_PHONE_MARK" ]; then say "  phone apps:     blocked by LG-USB-2-ETH0"
        elif phone_ours && ! phone_active; then say "  phone apps:     blocked from the next TV start"
        else say "  phone apps:     can't start an update"
        fi
    fi
    say "  found update:   $([ -n "$_pend" ] && echo 'yes, waiting to install' || echo none)"
    if eth0_guard; then say "  download watch: on, by LG-USB-2-ETH0"
    elif setting_on; then say "  download watch: $(guard_on && echo 'on, every 30 seconds' || echo 'off (turned off)')"; fi
    _sv=$(server_switch)
    case "$_sv" in
        Network) say "  update server:  switched to Network, which uses $UPD_IP: the firewall rule is what stops it" ;;
        ?*) say "  update server:  switched to $_sv (still blocked by name)" ;;
    esac
    _lf=$(lg_flags); [ -n "$_lf" ] && say "  LG flag files:  $_lf"
    say "  Homebrew Channel's block: $(hbc_blocking && echo on || echo off)"
    _t=$(stat_get tries); [ -n "$_t" ] && say "  updater tries stopped: $_t"
    _c=$(stat_get cancelled); [ -n "$_c" ] && say "  downloads cancelled: $_c"
    return 0
}

events_json() {
    printf '['
    awk 'NR > 1 { printf "," } { d = ""; for (i = 3; i <= NF; i++) d = d (i > 3 ? " " : "") $i
        gsub(/[\\"]/, "", d); printf "{\"t\":%d,\"kind\":\"%s\",\"detail\":\"%s\"}", $1, $2, d }' "$EVENTS" 2>/dev/null
    printf ']\n'
}

report() {
    say "WEBOS-FW-BLOCK $VERSION report"
    say "webOS $(webos), firmware $(firmware)"
    status_text | sed 1d
    say "setting: $(setting_on && echo on || echo off), remote support block: $(remote_on && echo on || echo off), hook: $([ -f "$HOOK" ] && echo yes || echo no), check running: $(watch_pid >/dev/null && echo yes || echo no)"
    say "others: $(others)"
    say "iptables: $(have_ipt && echo yes || echo no)"
    say "last events:"
    tail -n 10 "$EVENTS" 2>/dev/null | while read -r _t _k _d; do say "  $(date -d "@$_t" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$_t") $_k $_d"; done
}

# ------------------------------------------------------------- backups
#
# Before it turns the block on, restores a backup or installs an update,
# FW Block saves what things were: webOS's two update settings, its own
# settings, /etc/hosts, the phone gateway's update file and the firewall's
# OUTPUT rules, in a dated folder under $BACKUPS (the newest 10 are kept).
# FW Block never changes /etc/hosts or the gateway file themselves (it covers
# them with a copy), so those two are kept to show what was there.
# "restore NAME" puts back FW Block's settings and webOS's update settings
# as they were, and turns FW Block on or off to match.

backup_make() {
    _bn=$(date +%Y%m%d-%H%M%S)
    _bd="$BACKUPS/$_bn"
    [ -e "$_bd" ] && { _bn="$_bn-$$"; _bd="$BACKUPS/$_bn"; }
    mkdir -p "$_bd" && chmod 700 "$DATA" "$BACKUPS" || return 1
    {
        echo "time=$(now)"
        echo "reason=${1:-manual}"
        echo "version=$VERSION"
        echo "firmware=$(firmware)"
        echo "softwareUpdateEnable=$(switch_get)"
        echo "automaticUpdate=$(auto_get)"
        echo "block=$(setting_on && echo 1 || echo 0)"
        # What the others had, to know whose changes were whose
        echo "hbcBlock=$(hbc_blocking && echo 1 || echo 0)"
        echo "hbcKeepsCheck=$(hbc_keeps_check && echo 1 || echo 0)"
        echo "eth0Blocking=$(eth0_blocking && echo 1 || echo 0)"
        echo "eth0SavedCheck=$(cat "$ETH0_UPD_MARK" 2>/dev/null)"
        echo "eth0SavedAuto=$(cat "$ETH0_AUTO_MARK" 2>/dev/null)"
        echo "savedCheck=$(cat "$ORIG" 2>/dev/null)"
        echo "savedAuto=$(cat "$AUTO_ORIG" 2>/dev/null)"
    } > "$_bd/info"
    [ -f "$JOURNAL" ] && cp "$JOURNAL" "$_bd/originals.log"
    [ -f "$ETH0_CONF" ] && cp "$ETH0_CONF" "$_bd/lg-usb-2-eth0.conf"
    [ -f "$CONF" ] && cp "$CONF" "$_bd/settings"
    [ -f "$HOSTS" ] && cp "$HOSTS" "$_bd/hosts"
    # The gateway's own file, while FW Block's copy isn't over it
    if [ -f "$SSG_IF" ] && ! phone_ours; then cp "$SSG_IF" "$_bd/update.interface"; fi
    have_ipt && "$IPT" -S OUTPUT > "$_bd/iptables" 2>/dev/null
    # The newest ones only
    _bc=$(backup_names | wc -l)
    if [ "$_bc" -gt "$KEEP_BACKUPS" ]; then
        backup_names | head -n $((_bc - KEEP_BACKUPS)) | while read -r _old; do
            [ -n "$_old" ] && rm -rf "${BACKUPS:?}/$_old"
        done
    fi
    event backup "$_bn"
    say "Saved a backup: $_bn"
}

# Backup names, oldest first (they're dates, so the glob sorts them)
backup_names() {
    for _bp in "$BACKUPS"/*; do
        [ -f "$_bp/info" ] && say "${_bp##*/}"
    done
    return 0
}

backup_valid() {
    case "$1" in ''|*[!0-9-]*) return 1 ;; esac
    [ -f "$BACKUPS/$1/info" ]
}
binfo() { sed -n "s/^$2=//p" "$BACKUPS/$1/info" 2>/dev/null | awk 'NR == 1'; }

backups_list() {
    if [ "${1:-}" = --json ]; then
        printf '['
        _bf=''
        for _b in $(backup_names | sort -r); do
            backup_valid "$_b" || continue
            printf '%s{"name":%s,"time":%s,"reason":%s,"version":%s,"check":%s,"auto":%s,"block":%s}' "$_bf" "$(js "$_b")" \
                "$(jn "$(binfo "$_b" time)")" "$(js "$(binfo "$_b" reason)")" "$(js "$(binfo "$_b" version)")" \
                "$(js "$(binfo "$_b" softwareUpdateEnable)")" "$(js "$(binfo "$_b" automaticUpdate)")" "$(jb "$([ "$(binfo "$_b" block)" = 1 ] && echo 1)")"
            _bf=,
        done
        printf ']\n'
        return 0
    fi
    _bany=''
    for _b in $(backup_names | sort -r); do
        backup_valid "$_b" || continue
        _bany=1
        say "$_b  ($(binfo "$_b" reason)): FW Block $([ "$(binfo "$_b" block)" = 1 ] && echo on || echo off), update check $(binfo "$_b" softwareUpdateEnable), automatic update $(binfo "$_b" automaticUpdate)"
    done
    [ -n "$_bany" ] || say "No backups yet.  FW Block makes one by itself before it turns the block on."
}

cmd_restore() {
    backup_valid "$1" || die "No backup called '$1'.  See: sh fw-block.sh backups"
    _rb="$BACKUPS/$1"
    backup_make restore >/dev/null
    _wb=$(binfo "$1" block)
    # FW Block's own switches as they were, then on or off to match
    if [ -f "$_rb/settings" ]; then
        for _k in REMOTE PHONE GUARD; do
            _v=$(sed -n "s/^$_k=//p" "$_rb/settings" | awk 'NR == 1')
            [ -n "$_v" ] && conf_set "$_k" "$_v"
        done
    fi
    if [ "$_wb" = 1 ]; then
        setting_on && unblock >/dev/null
        cmd_on
    else
        setting_on && cmd_off
    fi
    # webOS's update settings as they were (the hidden one stays off while
    # LG-USB-2-ETH0 blocks updates, as that one is its to keep)
    _sw=$(binfo "$1" softwareUpdateEnable)
    if [ "$_wb" != 1 ]; then
        case "$_sw" in
            true|false)
                if [ "$_sw" = true ] && eth0_blocking; then say "Left webOS's update check off: LG-USB-2-ETH0 blocks updates."
                elif [ "$_sw" = true ] && hbc_keeps_check; then say "Left webOS's update check off: the Homebrew Channel's Block system updates keeps it off."
                elif [ "$(switch_get)" != "$_sw" ]; then sup_set softwareUpdateEnable "$_sw" && say "webOS's update check: $_sw, as in the backup."
                fi ;;
        esac
        _au=$(binfo "$1" automaticUpdate)
        case "$_au" in
            on|off)
                if [ "$_au" = on ] && eth0_auto; then say "Left Automatic software update off: LG-USB-2-ETH0 keeps it off."
                elif [ "$(auto_get)" != "$_au" ]; then sup_set automaticUpdate "$_au" && say "Automatic software update: $_au, as in the backup."
                fi ;;
        esac
    fi
    event restored "$1"
    say "Restored the backup from $1."
}

# ------------------------------------------------------------- updating this app
#
# update-check asks GitHub for the latest release (update.js), which only
# accepts a Homebrew Channel manifest signed with the project's release key
# (or its backup key).  update-install hands that release's IPK and SHA-256
# to the Homebrew Channel, which downloads, checks and installs it (closing
# the app), then opens the app again with {"updated": VERSION}.  It runs
# from a copy in /tmp, detached, since the install replaces this script.
# FW Block makes no other network request, and none at all unless asked.

find_node() {
    [ -n "$NODE" ] && { say "$NODE"; return; }
    for _n in /usr/bin/node /usr/local/bin/node; do
        [ -x "$R$_n" ] && { say "$R$_n"; return; }
    done
    command -v node 2>/dev/null
}

upd_state() {
    mkdir -p "$UPD"
    printf '{"state":%s,"version":%s,"error":%s}\n' "$(js "$1")" "$(js "${2:-}")" "$(js "${3:-}")" > "$UPD/state.json.tmp"
    mv "$UPD/state.json.tmp" "$UPD/state.json"
}
upd_get() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$UPD/check.json" 2>/dev/null | awk 'NR == 1'; }

update_check() {
    _n=$(find_node)
    [ -n "$_n" ] || die '{"error":"no-node"}'
    secure_run
    mkdir -p "$UPD"
    # The app's language, for the new version's notes in it
    case "${1:-}" in es|ru) _ul=$1 ;; *) _ul='' ;; esac
    "$_n" "$HERE/update.js" check "$VERSION" "$_ul" > "$UPD/check.json.tmp" 2>/dev/null
    if grep -q '"latest"' "$UPD/check.json.tmp" 2>/dev/null; then
        mv "$UPD/check.json.tmp" "$UPD/check.json"
        cat "$UPD/check.json"
    else
        _e=$(cat "$UPD/check.json.tmp" 2>/dev/null)
        rm -f "$UPD/check.json.tmp"
        say "${_e:-{\"error\":\"no-answer\"\}}"
        return 1
    fi
}

# The last check's answer is what goes to the Homebrew Channel: an address
# with no quotes or spaces, a SHA-256 and a version number, nothing else
upd_valid() {
    _vu=$(upd_get ipkUrl); _vh=$(upd_get sha256); _vv=$(upd_get latest)
    case "$_vu" in https://*|http://127.0.0.1:*) ;; *) return 1 ;; esac
    case "$_vu" in *[!A-Za-z0-9:/._-]*) return 1 ;; esac
    printf '%s' "$_vh" | grep -Eq '^[0-9a-f]{64}$' || return 1
    printf '%s' "$_vv" | grep -Eq '^[0-9]+(\.[0-9]+)+$' || return 1
    # Exactly this app's own IPK for that version, from its own releases
    # (update.js checks this too; checked again here, as it's what installs)
    [ "$_vu" = "${FB_RELEASE_BASE:-https://github.com/ohmybahgosh/WEBOS-FW-BLOCK/releases}/download/v$_vv/org.ohmybahgosh.fwblock_${_vv}_all.ipk" ]
}

update_install() {
    grep -q '"newer":true' "$UPD/check.json" 2>/dev/null || die '{"error":"nothing-newer"}'
    upd_valid || die '{"error":"bad-check"}'
    backup_make update >/dev/null
    cp "$SELF" "$UPD/run.sh"
    upd_state starting "$(upd_get latest)"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$UPD/run.sh" update-run < /dev/null > "$UPD/log" 2>&1 &
    else
        sh "$UPD/run.sh" update-run < /dev/null > "$UPD/log" 2>&1 &
    fi
    cat "$UPD/state.json"
}

update_run() {
    upd_valid || { upd_state failed '' bad-check; return 1; }
    _u=$(upd_get ipkUrl); _h=$(upd_get sha256); _v=$(upd_get latest)
    upd_state installing "$_v"
    # So the background check doesn't take the replaced folder for an uninstall
    now > "$UPD/installing"
    # The Homebrew Channel downloads it, checks the SHA-256 and installs it,
    # telling us as it goes.  It ends with "finished" or an error, but keeps
    # the subscription open, so watch its output and stop it then.
    rm -f "$UPD/result"
    "$LUNA" -i -w 600000 luna://org.webosbrew.hbchannel.service/install "{\"ipkUrl\":\"$_u\",\"ipkHash\":\"$_h\",\"subscribe\":true}" < /dev/null > "$UPD/install.log" 2>&1 &
    _lp=$!
    _i=0
    while [ $_i -lt 600 ]; do
        if grep -q '"finished" *: *true' "$UPD/install.log" 2>/dev/null; then echo ok > "$UPD/result"; break; fi
        if grep -q '"returnValue" *: *false' "$UPD/install.log" 2>/dev/null; then grep '"returnValue" *: *false' "$UPD/install.log" | awk 'NR == 1' > "$UPD/result"; break; fi
        kill -0 "$_lp" 2>/dev/null || { sleep 1; grep -q '"finished" *: *true' "$UPD/install.log" && echo ok > "$UPD/result"; break; }
        sleep 1
        _i=$((_i + 1))
    done
    kill "$_lp" 2>/dev/null
    rm -f "$UPD/installing"
    if [ "$(cat "$UPD/result" 2>/dev/null)" != ok ]; then
        upd_state failed "$_v" "$(sed -n 's/.*"errorText" *: *"\([^"]*\)".*/\1/p' "$UPD/result" 2>/dev/null | awk 'NR == 1')"
        return 1
    fi
    upd_state 'done' "$_v"
    event updated "$_v"
    rm -f "$UPD/check.json"
    # The background check starts again from the new script
    if setting_on && [ -f "$APP_DIR/assets/fw-block.sh" ]; then
        watch_stop
        sh "$APP_DIR/assets/fw-block.sh" check < /dev/null > /dev/null 2>&1
    fi
    sleep 2
    # Open the app again, to show what's new
    luna -n 1 luna://com.webos.applicationManager/launch "{\"id\":\"$APP_ID\",\"params\":{\"updated\":\"$_v\"}}" > /dev/null 2>&1
    return 0
}

update_status() { if [ -f "$UPD/state.json" ]; then cat "$UPD/state.json"; else say '{"state":"none"}'; fi; }

# What changed in VERSION (this one by default), from the bundled changelog
changes() {
    _cv=${1:-$VERSION}
    awk -v v="$_cv" '
        index($0, "## [" v "]") == 1 { on = 1; next }
        on && /^## / { on = 0 }
        on { print }' "$HERE/CHANGELOG.md" 2>/dev/null | sed '/./,$!d'
}

# ------------------------------------------------------------- restart

# Restarting the TV in the middle of an update could break it: refused while
# the updater says it's busy or an update is installing.  Everything is
# written to storage first.  The call is the Homebrew Channel's own.
cmd_restart() {
    if [ -e "$IN_PROGRESS" ] || [ -e "$USB_RUNNING" ] || [ -e "$NSU_RUNNING" ]; then
        die "Not restarting: the TV is busy with an update right now.  Try again in a few minutes."
    fi
    event restart ""
    sync
    say "Restarting the TV..."
    case "$(luna -n 1 luna://com.webos.service.tvpower/power/reboot '{"reason":"cpuCommand"}' 2>/dev/null)" in
        *'"returnValue":true'*|*'"returnValue": true'*) return 0 ;;
    esac
    [ -n "${FB_NOMOUNT:-}" ] && { say "(test: would run reboot)"; return 0; }
    reboot
}

# ------------------------------------------------------------- main

case "${1:-status}" in
    status) if [ "${2:-}" = --json ]; then status_json; else status_text; fi ;;
    on) cmd_on ;;
    off) cmd_off ;;
    remote) cmd_remote "${2:-}" ;;
    phone) cmd_phone "${2:-}" ;;
    guard) cmd_guard "${2:-}" ;;
    check)
        if setting_on; then tick; if guard_on && ! eth0_guard; then guard; fi; watch_start; else say "FW Block is off: nothing to check." >&2; fi
        if [ "${2:-}" = --json ]; then status_json; else status_text; fi ;;
    events) if [ "${2:-}" = --json ]; then events_json; else cat "$EVENTS" 2>/dev/null; fi ;;
    report) report ;;
    restart) cmd_restart ;;
    backup) backup_make manual ;;
    backups) backups_list "${2:-}" ;;
    restore) cmd_restore "${2:-}" ;;
    update-check) update_check "${2:-}" ;;
    update-install) update_install ;;
    update-run) update_run ;;
    update-status) update_status ;;
    changes) changes "${2:-}" ;;
    boot) boot ;;
    watch) watch ;;
    version) say "$VERSION" ;;
    *) die "Usage: sh fw-block.sh status|on|off|remote on|off|phone on|off|guard on|off|check|events|report|restart|backup|backups|restore NAME|update-check|update-install|changes|version" ;;
esac
