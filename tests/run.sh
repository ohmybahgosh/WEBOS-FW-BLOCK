#!/bin/sh
# Tests for fw-block.sh against a fake TV: a temporary folder holds
# /etc/hosts, the Homebrew Channel's and LG-USB-2-ETH0's files, webOS's
# update folders, and stand-ins for luna-send and iptables.  Nothing outside
# it is touched.  Needs python3 for reading the JSON.
#
#   tests/run.sh [busybox|dash|bash] [NAME-FILTER]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SHELL_NAME=${1:-busybox}
FILTER=${2:-}
case "$SHELL_NAME" in busybox) SH="busybox sh" ;; *) SH=$SHELL_NAME ;; esac
pass=0; fail=0; failed=''
SSG=/usr/palm/services/com.webos.service.secondscreen.gateway/interfaces/com.webos.service.update.interface

HOSTS_STOCK='127.0.0.1	localhost.localdomain		localhost
::1	localhost ip6-localhost ip6-loopback'
HBC_LINES='# This file is dynamically regenerated on boot by webosbrew startup script
127.0.0.1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com
::1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com'

setup() {
    T=$(mktemp -d "${TMPDIR:-/tmp}/fbtest.XXXXXX")
    export FB_ROOT="$T/root" FB_NOMOUNT=1 FB_FIRST=3600 FB_EVERY=3600 FB_QUICK=30
    export FB_LUNA="$HERE/fakebin/luna-send" FB_IPTABLES="$HERE/fakebin/iptables"
    mkdir -p "$FB_ROOT/etc" "$FB_ROOT/var/luna/preferences" "$FB_ROOT/var/lib/webosbrew/init.d" \
        "$FB_ROOT/mnt/lg/cmn_data/swupdate" "$FB_ROOT/mnt/lg/cmn_data/update" "$FB_ROOT/tmp" "$FB_ROOT/var/run/nyx"
    printf '%s\n' "$HOSTS_STOCK" > "$FB_ROOT/etc/hosts"
    printf '{"webos_release":"25.10.0","webos_manufacturing_version":"43.21.77"}\n' > "$FB_ROOT/var/run/nyx/os_info.json"
    # The phone gateway's file for the update service, as on webOS 26
    mkdir -p "$(dirname "$FB_ROOT$SSG")"
    cp "$HERE/fixtures/update-webos26.interface" "$FB_ROOT$SSG"
    # The Homebrew Channel's own app and service, there on every rooted TV
    mkdir -p "$FB_ROOT$HBC_APPD" "$FB_ROOT$HBC_SVCD"
    echo '{"id":"org.webosbrew.hbchannel"}' > "$FB_ROOT$HBC_APPD/appinfo.json"
    printf '#!/bin/sh\n# block updates: hosts only\n' > "$FB_ROOT$HBC_SVCD/startup.sh"
}
HBC_APPD=/media/developer/apps/usr/palm/applications/org.webosbrew.hbchannel
HBC_SVCD=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service
# The Homebrew Channel with webosbrew PR #264: its block turns the update check off
hbc_new_on() {
    : > "$FB_ROOT/var/luna/preferences/webosbrew_block_updates"
    printf '#!/bin/sh\nluna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \x27{"category":"support","settings":{"softwareUpdateEnable":"false"}}\x27\n' > "$FB_ROOT$HBC_SVCD/startup.sh"
}
FBD() { echo "$FB_ROOT/var/lib/webosbrew/webos-fw-block"; }
teardown() {
    _p=$(cat "$FB_ROOT/tmp/webos-fw-block/watch.pid" 2>/dev/null)
    [ -n "$_p" ] && kill "$_p" 2>/dev/null
    # The watcher's sleep, started by the shell above
    pkill -f "sleep 3600" 2>/dev/null
    rm -rf "$T"
}

run() { OUT=$($SH "$ROOT/fw-block.sh" "$@" 2>&1); RC=$?; }
json() { run status --json; printf '%s' "$OUT" > "$T/s.json"; }
has() { printf '%s' "$OUT" | grep -q -F -- "$1"; }
lacks() { ! has "$1"; }
field() { python3 -c "import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'): d=d[k]
print(json.dumps(d))" "$T/s.json" "$1"; }
is() { [ "$1" = "$2" ]; }
switch() { cat "$FB_ROOT/.switch" 2>/dev/null || echo true; }
auto() { cat "$FB_ROOT/.auto" 2>/dev/null || echo on; }
hosts() { cat "$FB_ROOT/etc/hosts"; }
in_hosts() { grep -q -F -- "$1" "$FB_ROOT/etc/hosts"; }
rules() { cat "$FB_ROOT/.iptables" 2>/dev/null; }
has_rule() { rules | grep -qx -- "$1"; }
ev() { grep -q " $1" "$FB_ROOT/var/lib/webosbrew/webos-fw-block/events" 2>/dev/null; }
stat() { sed -n "s/^$1=//p" "$FB_ROOT/var/lib/webosbrew/webos-fw-block/stats" 2>/dev/null; }
eth0_on() {
    printf 'BLOCK_UPDATES="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    ln -s /nonexistent "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
}
ssg() { cat "$FB_ROOT$SSG"; }
ssg_paths() { python3 -c "import json,sys; print(' '.join(m['path'] for m in json.load(open(sys.argv[1]))['methods']))" "$FB_ROOT$SSG"; }
phone_closed() { ! grep -q UPDATE_FROM_REMOTE_APP "$FB_ROOT$SSG"; }
# LG-USB-2-ETH0 2.11.45 and later: its hook is the script, which knows
# automaticUpdate; BLOCK_RS is its --block-remote-support
eth0_new_on() {
    printf 'BLOCK_UPDATES="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    printf '#!/bin/sh\n# upd_auto_set: automaticUpdate\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
}
eth0_rs_on() {
    printf 'BLOCK_RS="1"\n' >> "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    for _h in rone-tv-aic rone-tv-cic rone-tv-eic rone-tv-kic rone-tv-saic rone-aic rone-eic rone-kic rone-saic; do
        printf '0.0.0.0\t%s.lge.com # lg-usb-2-eth0 block-remote-support\n' "$_h" >> "$FB_ROOT/etc/hosts"
    done
    "$FB_IPTABLES" -I OUTPUT -d 165.244.62.249/32 -j DROP
    "$FB_IPTABLES" -I OUTPUT -d 165.244.99.174/32 -j DROP
}
# LG-USB-2-ETH0 with its own phone block and download guard (newer)
eth0_full_on() {
    printf 'BLOCK_UPDATES="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    printf '#!/bin/sh\n# automaticUpdate secondscreen.gateway dl_guard\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
}
valid_json() { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$T/s.json"; }

check() {
    _what=$1; shift
    if "$@"; then :; else echo "    not ok: $_what"; CASE_OK=0; fi
}

t() {
    case "$1" in *"$FILTER"*) ;; *) return ;; esac
    CASE_OK=1
    setup
    $2
    teardown
    if [ $CASE_OK = 1 ]; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); failed="$failed $1"; echo "FAIL $1"; fi
}

# ---------------------------------------------------------------- cases

test_fresh() {
    json
    check "valid JSON" valid_json
    check "level none" is "$(field level)" '"none"'
    check "owner none" is "$(field owner)" '"none"'
    check "every gap but download" is "$(field gaps)" '["check", "auto", "hosts", "firewall", "remote", "phone"]'
    check "7 missing" is "$(field hostsMissing | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 7
    check "firmware read" is "$(field firmware)" '"43.21.77"'
    run status
    check "says not blocked" has "NOT blocked"
}

test_on() {
    run on
    check "exit 0" is "$RC" 0
    check "switch off" is "$(switch)" false
    check "old value kept" is "$(cat "$FB_ROOT/var/lib/webosbrew/webos-fw-block/switch.orig")" true
    check "nsu blocked" in_hosts "0.0.0.0	nsu.lge.com # webos-fw-block"
    check "v6 too" in_hosts "::	ngfts.lge.com # webos-fw-block"
    check "chain" has_rule "-A FWBLOCK -d 156.147.69.32 -j DROP"
    check "jump" has_rule "-A OUTPUT -j FWBLOCK"
    check "hook" test -x "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    check "copy kept" test -f "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh"
    check "watcher running" test -s "$FB_ROOT/tmp/webos-fw-block/watch.pid"
    json
    check "level full" is "$(field level)" '"full"'
    check "owner us" is "$(field owner)" '"fw-block"'
    check "no gaps" is "$(field gaps)" '[]'
    check "firewall by us" is "$(field firewallBy)" '"fw-block"'
    check "watching" is "$(field watching)" true
    check "event" ev on
    # Twice changes nothing
    _h=$(hosts | md5sum); _r=$(rules | md5sum)
    run on
    check "hosts unchanged" is "$(hosts | md5sum)" "$_h"
    check "rules unchanged" is "$(rules | md5sum)" "$_r"
}

test_with_hbc_block() {
    : > "$FB_ROOT/var/luna/preferences/webosbrew_block_updates"
    printf '%s\n' "$HBC_LINES" >> "$FB_ROOT/etc/hosts"
    run on
    check "adds only the three it misses" is "$(grep -c '^0.0.0.0.*webos-fw-block$' "$FB_ROOT/etc/hosts")" 3
    check "not snu" eval "! grep -q '0.0.0.0	snu.lge.com' '$FB_ROOT/etc/hosts'"
    json
    check "hbc seen" is "$(field hbcBlock)" true
    check "level after on" is "$(field level)" '"full"'
    run off
    json
    check "hbc alone is partial" is "$(field level)" '"partial"'
    run on
    check "others hbc" is "$(field others)" '["hbc"]'
    run off
    check "hbc lines kept" in_hosts "127.0.0.1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com"
    check "ours gone" eval "! grep -q webos-fw-block '$FB_ROOT/etc/hosts'"
    check "mentions hbc" has "still on"
}

test_off() {
    run on
    run off
    check "exit 0" is "$RC" 0
    check "switch back on" is "$(switch)" true
    check "hosts back" is "$(hosts)" "$HOSTS_STOCK"
    check "no chain" eval "! rules | grep -q FWBLOCK"
    check "no hook" test ! -e "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    check "no copy" test ! -e "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh"
    check "watcher stopped" test ! -e "$FB_ROOT/tmp/webos-fw-block/watch.pid"
    check "run folder gone" test ! -e "$FB_ROOT/tmp/webos-fw-block"
    json
    check "owner none" is "$(field owner)" '"none"'
    check "on false" is "$(field on)" false
}

test_off_keeps_switch_that_was_off() {
    echo false > "$FB_ROOT/.switch"
    run on
    check "nothing remembered as true" is "$(cat "$FB_ROOT/var/lib/webosbrew/webos-fw-block/switch.orig")" false
    run off
    check "stays off" is "$(switch)" false
}

test_eth0_owns() {
    eth0_on
    run on
    check "adds only what it lacks" has "adds only what it lacks"
    check "switch untouched" is "$(switch)" true
    check "no update servers" eval "! grep -q 'nsu.lge.com # webos-fw-block' '$FB_ROOT/etc/hosts'"
    check "no update IP rule" eval "! has_rule '-A FWBLOCK -d 156.147.69.32 -j DROP'"
    check "automatic update off" is "$(auto)" off
    check "remote support blocked" in_hosts "0.0.0.0	rone-tv-aic.lge.com # webos-fw-block remote-support"
    check "remote IP dropped" has_rule "-A FWBLOCK -d 165.244.62.249 -j DROP"
    check "hook still added" test -f "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    json
    check "owner eth0" is "$(field owner)" '"eth0"'
    check "eth0 blocking" is "$(field eth0.blocking)" true
    check "no gaps for the parts eth0 keeps" is "$(field gaps)" '[]'
    run check
    check "standby event" ev "standby eth0"
    check "still no update servers" eval "! grep -q 'nsu.lge.com # webos-fw-block' '$FB_ROOT/etc/hosts'"
    # ETH0's block turned off: we take over at the next check
    rm -f "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    run check
    check "resumed" ev resumed
    check "now blocking" is "$(switch)" false
    check "update IP now" has_rule "-A FWBLOCK -d 156.147.69.32 -j DROP"
}

test_off_while_eth0_blocks_leaves_switch() {
    run on
    eth0_on
    run off
    check "says why" has "LG-USB-2-ETH0 still blocks"
    check "switch stays off" is "$(switch)" false
}

test_readonly_hosts() {
    : > "$FB_ROOT/.hosts_ro"
    run on
    check "made writable" test -f "$FB_ROOT/tmp/webos-fw-block/mounted"
    check "copy in RUN" test -f "$FB_ROOT/tmp/webos-fw-block/hosts"
    check "added" in_hosts "nsu.lge.com # webos-fw-block"
}

test_check_heals() {
    run on
    echo true > "$FB_ROOT/.switch"
    grep -v webos-fw-block "$FB_ROOT/etc/hosts" > "$T/h" && cat "$T/h" > "$FB_ROOT/etc/hosts"
    "$FB_IPTABLES" -D OUTPUT -j FWBLOCK
    json
    check "level partial or none" eval "[ \"$(field level)\" != '\"full\"' ]"
    run check --json
    check "switch back off" is "$(switch)" false
    check "hosts back" in_hosts "nsu.lge.com # webos-fw-block"
    check "jump back" has_rule "-A OUTPUT -j FWBLOCK"
    check "event" ev "fixed check,hosts,firewall,remote"
    check "stat" is "$(stat fixedWhat)" "check,hosts,firewall,remote"
}

test_found_update_removed() {
    run on
    : > "$FB_ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    json
    check "pending seen" is "$(field pending)" true
    check "gap download" is "$(field gaps)" '["download"]'
    run check
    check "removed" test ! -e "$FB_ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    check "found event" ev found
    check "no fixed event" eval "! grep -q ' fixed' '$FB_ROOT/var/lib/webosbrew/webos-fw-block/events'"
}

test_on_removes_found_update() {
    : > "$FB_ROOT/mnt/lg/cmn_data/swupdate/Package_Update_Info.xml"
    run on
    check "removed" test ! -e "$FB_ROOT/mnt/lg/cmn_data/swupdate/Package_Update_Info.xml"
    check "said so" has "already found"
}

test_hits_counted() {
    run on
    echo "FWBLOCK 156.147.69.32 4" > "$FB_ROOT/.iptables.hits"
    run check
    check "one try" is "$(stat tries)" 1
    check "event" ev "stopped 4"
    run check
    check "same count, no new try" is "$(stat tries)" 1
    echo "FWBLOCK 156.147.69.32 9" > "$FB_ROOT/.iptables.hits"
    run check
    check "second try" is "$(stat tries)" 2
    json
    check "in status" is "$(field stats.tries)" 2
}

test_server_switch_noted() {
    run on
    : > "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeSDP"
    run check
    check "event" ev "server SDP"
    check "flag left alone" test -e "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeSDP"
    json
    check "status" is "$(field serverSwitch)" '"SDP"'
}

test_luna_down() {
    export FAKE_LUNA_DOWN=1
    json
    check "valid JSON" valid_json
    check "check unknown" is "$(field check)" '""'
    run status
    check "text works" has "update check:   unknown"
    unset FAKE_LUNA_DOWN
}

test_no_iptables() {
    export FB_IPTABLES=/nonexistent/iptables
    run on
    check "exit 0" is "$RC" 0
    json
    check "full without a firewall" is "$(field level)" '"full"'
    check "firewall false" is "$(field firewall)" false
    run status
    check "says so" has "no firewall on this TV"
}

test_redirect_is_not_a_block() {
    printf '10.0.0.5 snu.lge.com\n' >> "$FB_ROOT/etc/hosts"
    json
    check "snu still missing" eval "field hostsMissing | grep -q snu.lge.com"
}

test_eth0_leftover_rule() {
    "$FB_IPTABLES" -I OUTPUT -d 156.147.69.32/32 -j DROP
    json
    check "counted as other" is "$(field firewallBy)" '"other"'
}

test_others() {
    printf '# APL Launcher: LG system updates blocked\n' >> "$FB_ROOT/etc/hosts"
    "$FB_IPTABLES" -N LG_LOCKOUT
    json
    check "apl and lockout" is "$(field others)" '["apl-launcher", "webos-lockout"]'
}

test_events_json() {
    run on
    run off
    run events --json
    printf '%s' "$OUT" > "$T/s.json"
    check "valid" valid_json
    # backup, on, off
    check "three events" is "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$T/s.json")" 3
}

test_boot() {
    run on
    teardown_watch
    # A restart: RAM is gone, the switch survives, the hosts copy doesn't
    rm -rf "$FB_ROOT/tmp/webos-fw-block" "$FB_ROOT/.iptables"
    printf '%s\n' "$HOSTS_STOCK" > "$FB_ROOT/etc/hosts"
    cp "$HERE/fixtures/update-webos26.interface" "$FB_ROOT$SSG"
    sh "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    _i=0; while [ $_i -lt 50 ] && ! has_rule "-A OUTPUT -j FWBLOCK"; do sleep 0.1; _i=$((_i + 1)); done
    sleep 0.3
    check "hosts back" in_hosts "nsu.lge.com # webos-fw-block"
    check "chain back" has_rule "-A OUTPUT -j FWBLOCK"
    check "boot event" ev boot
    check "watcher" test -s "$FB_ROOT/tmp/webos-fw-block/watch.pid"
    check "boot log" test -f "$FB_ROOT/var/lib/webosbrew/webos-fw-block/boot.log"
    check "phone block back" phone_closed
    json
    check "phone holds now" is "$(field phone.nextStart)" false
}
teardown_watch() {
    _p=$(cat "$FB_ROOT/tmp/webos-fw-block/watch.pid" 2>/dev/null)
    [ -n "$_p" ] && kill "$_p" 2>/dev/null
    rm -f "$FB_ROOT/tmp/webos-fw-block/watch.pid"
}

test_boot_when_off() {
    run boot
    check "nothing" is "$(hosts)" "$HOSTS_STOCK"
    check "no events" test ! -e "$FB_ROOT/var/lib/webosbrew/webos-fw-block/events"
}

test_boot_eth0() {
    run on
    teardown_watch
    run off
    printf 'BLOCK=1\nREMOTE=1\n' > "$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings"
    eth0_on
    run boot
    check "adds only what it lacks" has "adds only what it lacks"
    check "no update servers" eval "! grep -q 'nsu.lge.com # webos-fw-block' '$FB_ROOT/etc/hosts'"
    check "remote support blocked" in_hosts "rone-kic.lge.com # webos-fw-block remote-support"
    teardown_watch
}

test_run_dir_link_moved() {
    ln -s "$T" "$FB_ROOT/tmp/webos-fw-block"
    run on
    check "real folder now" eval "[ -d '$FB_ROOT/tmp/webos-fw-block' ] && [ ! -L '$FB_ROOT/tmp/webos-fw-block' ]"
}

test_watch_tick() {
    export FB_FIRST=0 FB_EVERY=1
    run on
    echo true > "$FB_ROOT/.switch"
    _i=0; while [ $_i -lt 40 ] && [ "$(switch)" != false ]; do sleep 0.1; _i=$((_i + 1)); done
    check "watcher put it back" is "$(switch)" false
    _p=$(cat "$FB_ROOT/tmp/webos-fw-block/watch.pid")
    run off
    sleep 0.2
    check "watcher gone" eval "! kill -0 $_p 2>/dev/null || [ \"\$(cut -d ' ' -f 3 /proc/$_p/stat)\" = Z ]"
    export FB_FIRST=3600 FB_EVERY=3600
}

test_report() {
    run on
    run report
    check "has version" has "WEBOS-FW-BLOCK"
    check "has firmware" has "43.21.77"
    check "has events" has "last events:"
}

test_usage() {
    run nonsense
    check "fails" is "$RC" 1
    check "usage" has "Usage"
}

test_auto_update() {
    run on
    check "turned off" is "$(auto)" off
    check "remembered" is "$(cat "$FB_ROOT/var/lib/webosbrew/webos-fw-block/auto.orig")" on
    check "said so" has "Automatic software update off"
    echo on > "$FB_ROOT/.auto"
    run check
    check "put back by the check" is "$(auto)" off
    check "fixed event" ev "fixed auto"
    run off
    check "restored" is "$(auto)" on
}

test_auto_update_already_off() {
    echo off > "$FB_ROOT/.auto"
    run on
    run off
    check "stays off" is "$(auto)" off
}

test_remote_support() {
    run on
    check "9 hosts" is "$(grep -c '^0.0.0.0.*webos-fw-block remote-support' "$FB_ROOT/etc/hosts")" 9
    check "ip 1" has_rule "-A FWBLOCK -d 165.244.62.249 -j DROP"
    check "ip 2" has_rule "-A FWBLOCK -d 165.244.99.174 -j DROP"
    json
    check "blocked" is "$(field remote.blocked)" true
    run remote off
    check "hosts gone" eval "! grep -q remote-support '$FB_ROOT/etc/hosts'"
    check "ips gone" eval "! rules | grep -q 165.244"
    check "update block kept" in_hosts "nsu.lge.com # webos-fw-block"
    check "update ip kept" has_rule "-A FWBLOCK -d 156.147.69.32 -j DROP"
    json
    check "remote off" is "$(field remote.on)" false
    check "no remote gap" is "$(field gaps)" '[]'
    run check
    check "check leaves it off" eval "! grep -q remote-support '$FB_ROOT/etc/hosts'"
    run remote on
    check "back" in_hosts "rone-saic.lge.com # webos-fw-block remote-support"
    check "ips back" has_rule "-A FWBLOCK -d 165.244.99.174 -j DROP"
    run off
    check "all gone" eval "! grep -q webos-fw-block '$FB_ROOT/etc/hosts'"
    check "no chain" eval "! rules | grep -q FWBLOCK"
}

test_remote_off_kept_across_on() {
    run remote off
    run on
    check "not blocked" eval "! grep -q remote-support '$FB_ROOT/etc/hosts'"
}

test_remote_hits() {
    run on
    echo "FWBLOCK 165.244.62.249 5" > "$FB_ROOT/.iptables.hits"
    run check
    check "counted" is "$(stat remote)" 1
    check "event" ev "remote 5"
    check "not an update try" is "$(stat tries)" ""
}

test_guard_cancels_download() {
    run on
    # The background watch checks downloads as it starts: stopped, so only this check acts
    teardown_watch
    : > "$FB_ROOT/tmp/nsu-running"
    echo downloading > "$FB_ROOT/.updstatus"
    : > "$FB_ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    run check
    check "cancel sent" grep -q "service.update/cancelUpdate" "$FB_ROOT/.luna.log"
    check "status idle" is "$(cat "$FB_ROOT/.updstatus")" idle
    check "found info deleted" test ! -e "$FB_ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    check "event" ev "cancelled downloading"
    check "stat" is "$(stat cancelled)" 1
    check "toast" grep -q "createToast" "$FB_ROOT/.luna.log"
}

test_guard_leaves_install() {
    run on
    # The background watch checks downloads as it starts: stopped, so only this check acts
    teardown_watch
    : > "$FB_ROOT/mnt/lg/cmn_data/.UpdateIsInprogress"
    echo installing > "$FB_ROOT/.updstatus"
    run check
    run check
    check "no cancel" eval "! grep -q cancelUpdate '$FB_ROOT/.luna.log'"
    check "one event" is "$(grep -c ' installing' "$FB_ROOT/var/lib/webosbrew/webos-fw-block/events")" 1
}

test_guard_leaves_usb() {
    run on
    # The background watch checks downloads as it starts: stopped, so only this check acts
    teardown_watch
    : > "$FB_ROOT/tmp/usbupdate-running"
    echo downloading > "$FB_ROOT/.updstatus"
    run check
    check "no cancel" eval "! grep -q cancelUpdate '$FB_ROOT/.luna.log'"
}

test_guard_quiet_when_idle() {
    run on
    # The background watch checks downloads as it starts: stopped, so only this check acts
    teardown_watch
    : > "$FB_ROOT/.luna.log"
    run check
    check "updater not asked" eval "! grep -q 'service.update/getStatus' '$FB_ROOT/.luna.log'"
}

test_guard_in_watch() {
    export FB_FIRST=3600 FB_EVERY=3600 FB_QUICK=1
    run on
    : > "$FB_ROOT/tmp/nsu-running"
    echo downloading > "$FB_ROOT/.updstatus"
    _i=0; while [ $_i -lt 40 ] && [ "$(cat "$FB_ROOT/.updstatus")" != idle ]; do sleep 0.1; _i=$((_i + 1)); done
    check "background watch cancelled it" is "$(cat "$FB_ROOT/.updstatus")" idle
    teardown_watch
    export FB_QUICK=30
}

test_lg_flags() {
    run on
    : > "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeNetwork"
    : > "$FB_ROOT/mnt/lg/cmn_data/.forceUpdateFlagFile"
    : > "$FB_ROOT/mnt/lg/cmn_data/debugVersionCheck"
    run check
    check "server event" ev "server Network"
    check "flags event" ev "flags force,debug"
    check "left alone" test -e "$FB_ROOT/mnt/lg/cmn_data/.forceUpdateFlagFile"
    json
    check "json flags" is "$(field lgFlags)" '["force", "debug"]'
    run status
    check "explains network" has "the firewall rule is what stops it"
}

test_phone_block() {
    run on
    check "says next start" has "from the next TV start"
    check "no update calls left" phone_closed
    check "still valid JSON" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FB_ROOT$SSG"
    check "read-only calls kept" is "$(ssg_paths)" "/getCurrentSWInformation /getVersion"
    check "service name kept" grep -q '"service": "com.webos.service.update"' "$FB_ROOT$SSG"
    json
    check "blocked" is "$(field phone.blocked)" true
    check "from the next start" is "$(field phone.nextStart)" true
    check "no phone gap" is "$(field gaps)" '[]'
    run status
    check "status line" has "phone apps:     blocked from the next TV start"
    # Twice changes nothing
    _s=$(ssg | md5sum)
    run on
    check "unchanged" is "$(ssg | md5sum)" "$_s"
}
test_phone_off_restores() {
    run on
    run off
    check "says again" has "Phone apps can start an update again"
    check "original back" cmp -s "$FB_ROOT$SSG" "$HERE/fixtures/update-webos26.interface"
    json
    check "not blocked" is "$(field phone.blocked)" false
}
test_phone_webos25() {
    cp "$HERE/fixtures/update-webos25.interface" "$FB_ROOT$SSG"
    run on
    check "only the call it had" is "$(ssg_paths)" "/getCurrentSWInformation"
    run off
    check "original back" cmp -s "$FB_ROOT$SSG" "$HERE/fixtures/update-webos25.interface"
}
test_phone_no_gateway() {
    rm -f "$FB_ROOT$SSG"
    run on
    check "exit 0" is "$RC" 0
    check "nothing said" lacks "phone apps"
    json
    check "not present" is "$(field phone.present)" false
    check "no gap" is "$(field gaps)" '[]'
    run status
    check "no status line" lacks "phone apps:"
}
test_phone_with_eth0() {
    eth0_on
    run on
    check "says phone apps" has "phone apps"
    check "blocked anyway" phone_closed
}
test_phone_check_heals() {
    run on
    # Something put the original back
    cp "$HERE/fixtures/update-webos26.interface" "$FB_ROOT$SSG"
    json
    check "gap seen" is "$(field gaps)" '["phone"]'
    run check
    check "closed again" phone_closed
    check "fixed event" ev "fixed phone"
}

test_eth0_new_keeps_auto() {
    eth0_new_on
    run on
    check "automatic update left to eth0" is "$(auto)" on
    check "its original saved anyway, for later" is "$(cat "$(FBD)/auto.orig")" on
    check "phone apps still ours" phone_closed
    check "remote support still ours" in_hosts "rone-tv-aic.lge.com # webos-fw-block remote-support"
    json
    check "auto kept by eth0" is "$(field autoBy)" '"eth0"'
    check "no auto gap" is "$(field gaps)" '[]'
    run off
    check "auto still untouched" is "$(auto)" on
}
test_eth0_remote_support() {
    eth0_new_on
    eth0_rs_on
    run on
    check "no remote lines of ours" eval "! grep -q 'webos-fw-block remote-support' '$FB_ROOT/etc/hosts'"
    check "no remote rules of ours" eval "! has_rule '-A FWBLOCK -d 165.244.62.249 -j DROP'"
    json
    check "blocked" is "$(field remote.blocked)" true
    check "by eth0" is "$(field remote.by)" '"eth0"'
    check "no gaps" is "$(field gaps)" '[]'
    run status
    check "status says eth0" has "LG Remote Support: blocked by LG-USB-2-ETH0"
    run remote off
    check "says eth0 still blocks" has "LG-USB-2-ETH0 still does"
    check "eth0's lines untouched" in_hosts "rone-saic.lge.com # lg-usb-2-eth0 block-remote-support"
    check "eth0's rule untouched" has_rule "-A OUTPUT -d 165.244.99.174/32 -j DROP"
}
test_eth0_rs_without_updates() {
    # Only its Remote Support block: FW Block keeps everything else
    printf 'BLOCK_UPDATES="0"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    printf '#!/bin/sh\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    eth0_rs_on
    run on
    check "update servers ours" in_hosts "nsu.lge.com # webos-fw-block"
    check "auto off" is "$(auto)" off
    check "no remote lines of ours" eval "! grep -q 'webos-fw-block remote-support' '$FB_ROOT/etc/hosts'"
    json
    check "no gaps" is "$(field gaps)" '[]'
}

test_phone_toggle() {
    run on
    run phone off
    check "says not blocked" has "Phone apps can start an update again"
    check "original back" cmp -s "$FB_ROOT$SSG" "$HERE/fixtures/update-webos26.interface"
    json
    check "phone off" is "$(field phone.on)" false
    check "no phone gap when off" is "$(field gaps)" '[]'
    run check
    check "check leaves it open" eval "grep -q UPDATE_FROM_REMOTE_APP '$FB_ROOT$SSG'"
    run status
    check "status says turned off" has "can start an update (turned off)"
    run phone on
    check "blocked again" phone_closed
    run off
    run on
    check "setting kept across off/on" phone_closed
}
test_guard_toggle() {
    run on
    run guard off
    check "says off" has "no longer watched"
    json
    check "guard off" is "$(field guard)" false
    echo downloading > "$FB_ROOT/.updstatus"
    : > "$FB_ROOT/tmp/nsu-running"
    run check
    check "not cancelled" is "$(cat "$FB_ROOT/.updstatus")" downloading
    run guard on
    run check
    check "cancelled once on" is "$(cat "$FB_ROOT/.updstatus")" idle
    json
    check "guard on" is "$(field guard)" true
}

# The app installed in the fake TV, with this script as its asset
APPD=/media/developer/apps/usr/palm/applications/org.ohmybahgosh.fwblock
app_install() {
    mkdir -p "$FB_ROOT$APPD/assets"
    cp "$ROOT/fw-block.sh" "$FB_ROOT$APPD/assets/fw-block.sh"
    echo '{"id":"org.ohmybahgosh.fwblock"}' > "$FB_ROOT$APPD/appinfo.json"
}
run_app() { OUT=$($SH "$FB_ROOT$APPD/assets/fw-block.sh" "$@" 2>&1); RC=$?; }
test_uninstall_undoes() {
    app_install
    run_app on
    check "remembered it came from the app" eval "grep -qx APP=1 '$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings'"
    teardown_watch
    # Uninstalled: the Homebrew Channel deletes the app's folder
    rm -rf "$FB_ROOT$APPD"
    OUT=$(FB_GONE_WAIT=0 $SH "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh" boot 2>&1)
    check "says why" has "was uninstalled"
    check "switch back on" is "$(switch)" true
    check "auto back on" is "$(auto)" on
    check "hosts back" is "$(hosts)" "$HOSTS_STOCK"
    check "no chain" eval "! rules | grep -q FWBLOCK"
    check "phone file back" cmp -s "$FB_ROOT$SSG" "$HERE/fixtures/update-webos26.interface"
    check "no hook" test ! -e "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    check "no data folder" test ! -e "$FB_ROOT/var/lib/webosbrew/webos-fw-block"
    check "no run folder" test ! -e "$FB_ROOT/tmp/webos-fw-block"
}
test_uninstall_leaves_eth0() {
    eth0_on
    app_install
    run_app on
    teardown_watch
    rm -rf "$FB_ROOT$APPD"
    FB_GONE_WAIT=0 $SH "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh" boot >/dev/null 2>&1
    check "eth0's conf untouched" eval "grep -q 'BLOCK_UPDATES=\"1\"' '$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf'"
    check "eth0's hook untouched" test -L "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    check "our remote lines gone" eval "! grep -q 'webos-fw-block' '$FB_ROOT/etc/hosts'"
}
test_ssh_only_not_uninstalled() {
    # Turned on over SSH, never from the app: no app folder is expected
    run on
    teardown_watch
    rm -rf "$FB_ROOT/tmp/webos-fw-block"
    printf '%s\n' "$HOSTS_STOCK" > "$FB_ROOT/etc/hosts"
    FB_GONE_WAIT=0 $SH "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh" boot >/dev/null 2>&1
    check "still blocking" in_hosts "nsu.lge.com # webos-fw-block"
    check "hook kept" test -e "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
}
test_app_update_not_uninstall() {
    app_install
    run_app on
    teardown_watch
    # An update replaces the folder: gone for a moment, back before the second look
    mv "$FB_ROOT$APPD" "$FB_ROOT$APPD.tmp"
    ( sleep 0.3; mv "$FB_ROOT$APPD.tmp" "$FB_ROOT$APPD" ) &
    FB_GONE_WAIT=1 $SH "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh" boot >/dev/null 2>&1
    wait
    check "still on" eval "grep -qx BLOCK=1 '$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings'"
    check "hook kept" test -e "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
}

test_eth0_keeps_phone_and_downloads() {
    eth0_full_on
    run on
    check "no phone mount of ours" eval "grep -q UPDATE_FROM_REMOTE_APP '$FB_ROOT$SSG'"
    check "no phone mark of ours" test ! -e "$FB_ROOT/tmp/webos-fw-block/phone"
    json
    check "phone left to eth0" is "$(field phone.eth0)" true
    check "guard by eth0" is "$(field guardBy)" '"eth0"'
    # ETH0's own block in place (its hook runs after ours)
    mkdir -p "$FB_ROOT/tmp/lg-usb-2-eth0"; echo boot > "$FB_ROOT/tmp/lg-usb-2-eth0/lg-usb-2-eth0.phone"
    grep -v UPDATE_FROM_REMOTE_APP "$HERE/fixtures/update-webos26.interface" > "$T/x" ; cp "$T/x" "$FB_ROOT$SSG"
    json
    check "phone blocked by eth0" is "$(field phone.by)" '"eth0"'
    run status
    check "status names eth0" has "phone apps:     blocked by LG-USB-2-ETH0"
    check "download watch by eth0" has "download watch: on, by LG-USB-2-ETH0"
    run phone on
    check "phone on says eth0 does it" has "LG-USB-2-ETH0 already blocks phone apps"
}
test_eth0_phone_off_fwblock_takes_it() {
    eth0_full_on
    printf 'BLOCK_PHONE="0"\nSTOP_DL="0"\n' >> "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    run on
    check "we block phone apps" phone_closed
    json
    check "not eth0's" is "$(field phone.eth0)" false
    check "guard ours" is "$(field guardBy)" '"fw-block"'
}

test_eth0_phone_pending() {
    eth0_full_on
    json
    check "not blocked yet" is "$(field phone.blocked)" false
    check "eth0 next start" is "$(field phone.nextStart)" true
    check "by eth0" is "$(field phone.by)" '"eth0"'
    run status
    check "says next start" has "open now, LG-USB-2-ETH0 blocks them from the next TV start"
    check "says fw-block off" has "Blocked by: LG-USB-2-ETH0 (FW Block is off)"
}

nbackups() { find "$FB_ROOT/var/lib/webosbrew/webos-fw-block/backups" -mindepth 1 -maxdepth 1 -type d | wc -l; }
test_backups() {
    run backups
    check "none yet" has "No backups yet"
    echo false > "$FB_ROOT/.switch"; echo off > "$FB_ROOT/.auto"
    run on
    _b=$(cd "$FB_ROOT/var/lib/webosbrew/webos-fw-block/backups" && echo *)
    check "one made before turning on" is "$(echo "$_b" | wc -l)" 1
    _d="$FB_ROOT/var/lib/webosbrew/webos-fw-block/backups/$_b"
    check "with the settings as they were" grep -qx "block=0" "$_d/info"
    check "and the update check" grep -qx "softwareUpdateEnable=false" "$_d/info"
    check "the hosts file as it was" eval "! grep -q webos-fw-block '$_d/hosts'"
    check "the phone gateway's own file" grep -q UPDATE_FROM_REMOTE_APP "$_d/update.interface"
    run backups --json
    printf '%s' "$OUT" > "$T/b.json"
    check "listed" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[0]['reason']=='on' and d[0]['block'] is False and d[0]['check']=='false'" "$T/b.json"
    run restore "nope;rm"
    check "a bad name is refused" is "$RC" 1
    run restore "$_b"
    check "restored" has "Restored the backup"
    json
    check "FW Block off again, as in the backup" is "$(field on)" false
    check "update check as it was" is "$(switch)" false
    check "a backup made before restoring" is "$(nbackups)" 2
    # The newest ten are kept
    _i=0; while [ $_i -lt 12 ]; do run backup; _i=$((_i + 1)); done
    check "only ten kept" is "$(nbackups)" 10
}

REL_PID=''
release_start() {
    rm -f "$T/rel.ready"
    node "$HERE/fakebin/fake-release.js" "$1" "$T/rel.ready" > /dev/null 2>&1 &
    REL_PID=$!
    _i=0; while [ ! -s "$T/rel.ready" ] && [ $_i -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
    read -r _rp FB_RELEASE_PUBKEY < "$T/rel.ready"
    FB_RELEASE_BASE="http://127.0.0.1:$_rp/rel"
    FB_API_BASE="http://127.0.0.1:$_rp/api"
    export FB_RELEASE_BASE FB_API_BASE FB_RELEASE_PUBKEY
}
release_stop() { [ -n "$REL_PID" ] && kill "$REL_PID" 2>/dev/null; REL_PID=''; unset FB_RELEASE_BASE FB_API_BASE FB_RELEASE_PUBKEY FAKE_LUNA_FAIL; }
UPDS() { echo "$FB_ROOT/tmp/webos-fw-block/self-update/state.json"; }
upd_wait() { _i=0; while [ $_i -lt 50 ]; do grep -q "\"state\":\"$1\"" "$(UPDS)" 2>/dev/null && return 0; sleep 0.2; _i=$((_i + 1)); done; return 1; }

test_update() {
    command -v node > /dev/null || { echo "  (no node: update test skipped)"; return 0; }
    FB_NODE=$(command -v node); export FB_NODE
    release_start 9.9.9
    run update-check
    check "newer found" has '"newer":true'
    check "its notes" has 'Something new'
    run update-check es
    check "notes in Spanish too, signed" has '"notesLang":"### Added'
    check "this version's section only" lacks 'Viejo'
    release_stop
    export FAKE_CL_SIG=tampered
    release_start 9.9.9
    run update-check es
    check "a changed translation isn't shown" lacks 'notesLang'
    check "the update itself still offered" has '"newer":true'
    release_stop
    unset FAKE_CL_SIG
    release_start 9.9.9
    run update-check
    run update-install
    check "started" has '"state":"starting"'
    check "installed" upd_wait "done"
    check "through the Homebrew Channel, with the hash" grep -q "hbchannel.service/install.*/download/v9.9.9/org.ohmybahgosh.fwblock_9.9.9_all.ipk.*\"ipkHash\":\"abab" "$FB_ROOT/.luna.log"
    _i=0; while [ $_i -lt 30 ] && ! grep -q applicationManager "$FB_ROOT/.luna.log"; do sleep 0.2; _i=$((_i + 1)); done
    check "then the app opens again with what's new" grep -q 'applicationManager/launch.*"updated":"9.9.9"' "$FB_ROOT/.luna.log"
    check "a backup first" eval "grep -q 'reason=update' '$FB_ROOT'/var/lib/webosbrew/webos-fw-block/backups/*/info"
    run update-check
    export FAKE_LUNA_FAIL=1
    run update-install
    check "failure noticed" upd_wait failed
    check "with the reason" grep -q "Invalid file checksum" "$(UPDS)"
    release_stop
    release_start "$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/fw-block.sh")"
    rm -f "$FB_ROOT/tmp/webos-fw-block/self-update/check.json"
    run update-check
    check "same version: not newer" has '"newer":false'
    run update-install
    check "install refused" is "$RC" 1
    release_stop
    for _bad in none other-key tampered; do
        rm -f "$FB_ROOT/tmp/webos-fw-block/self-update/check.json"
        export FAKE_SIG=$_bad
        release_start 9.9.9
        run update-check
        check "signature $_bad: refused" has bad-signature
        run update-install
        check "signature $_bad: nothing installed" is "$RC" 1
        release_stop
        unset FAKE_SIG
    done
    for _bad in FAKE_IPK_URL=https://evil.example/org.ohmybahgosh.fwblock_9.9.9_all.ipk FAKE_IPK_V=0.0.1; do
        rm -f "$FB_ROOT/tmp/webos-fw-block/self-update/check.json"
        export "${_bad?}"
        release_start 9.9.9
        run update-check
        check "$_bad: refused" has unexpected-url
        run update-install
        check "$_bad: nothing installed" is "$RC" 1
        release_stop
        unset FAKE_IPK_URL FAKE_IPK_V
    done
    # A check's answer changed afterwards (not through update.js): the
    # script itself only hands over this app's own IPK for that version
    _cj="$FB_ROOT/tmp/webos-fw-block/self-update/check.json"
    printf '{"current":"0.0.1","latest":"9.9.9","newer":true,"ipkUrl":"https://evil.example/download/v9.9.9/org.ohmybahgosh.fwblock_9.9.9_all.ipk","sha256":"%s"}\n' "$(printf 'ab%.0s' $(seq 32))" > "$_cj"
    : > "$FB_ROOT/.luna.log"
    run update-install
    check "edited check: refused" has bad-check
    check "edited check: nothing handed over" eval "! grep -q hbchannel.service/install '$FB_ROOT/.luna.log'"
    run changes 0.1.0
    check "what changed in a version" has "Block firmware updates, with one button"
    unset FB_NODE
}

test_update_not_uninstall() {
    run on
    sed -i 's/^APP=.*//' "$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings"; echo APP=1 >> "$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings"
    mkdir -p "$FB_ROOT/tmp/webos-fw-block/self-update"; date +%s > "$FB_ROOT/tmp/webos-fw-block/self-update/installing"
    export FB_GONE_WAIT=0
    run boot
    check "an update installing isn't an uninstall" test -f "$FB_ROOT/var/lib/webosbrew/webos-fw-block/settings"
    unset FB_GONE_WAIT
}

# ---- living with the Homebrew Channel and LG-USB-2-ETH0: whose value is whose

test_hbc_keeps_check() {
    hbc_new_on
    run on
    check "update check off" is "$(switch)" false
    run off
    check "left off for the Homebrew Channel" is "$(switch)" false
    check "and says why" has "the Homebrew Channel's Block system updates keeps it off"
    json
    check "credited to the Homebrew Channel" is "$(field checkBy)" '"hbc"'
    check "seen" is "$(field hbcKeepsCheck)" true
}
test_hbc_old_doesnt_keep_check() {
    : > "$FB_ROOT/var/luna/preferences/webosbrew_block_updates"
    run on
    run off
    check "an older Homebrew Channel doesn't: back on" is "$(switch)" true
    json
    check "not credited" is "$(field hbcKeepsCheck)" false
}
test_restore_from_backup_respects_hbc() {
    run on
    _b=$(cd "$(FBD)/backups" && echo *)
    hbc_new_on
    run restore "$_b"
    check "the backup's 'on' not forced over the Homebrew Channel" is "$(switch)" false
}
test_eth0_first_original_kept() {
    # LG-USB-2-ETH0 turned the check off first, and saved "true"
    eth0_new_on
    echo true > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates"; echo false > "$FB_ROOT/.switch"
    echo on > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.autoupdate"; echo off > "$FB_ROOT/.auto"
    run on
    check "the real original, from LG-USB-2-ETH0's record" is "$(cat "$(FBD)/switch.orig")" true
    check "automatic update's too" is "$(cat "$(FBD)/auto.orig")" on
    check "where it came from, written down" grep -q "switch.orig true from lg-usb-2-eth0" "$(FBD)/originals.log"
    # LG-USB-2-ETH0's block turned off: it puts back what it saved
    rm -f "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf" "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates" "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.autoupdate"
    echo true > "$FB_ROOT/.switch"; echo on > "$FB_ROOT/.auto"
    run check
    check "FW Block closes it again" is "$(switch)" false
    check "automatic update too" is "$(auto)" off
    run off
    check "then puts back the real original" is "$(switch)" true
    check "for automatic update too" is "$(auto)" on
}
test_failed_restore_keeps_original() {
    run on
    export FAKE_SETTINGS_FAIL=1
    run off
    check "says it couldn't" has "Could not turn webOS's update check back on"
    check "keeps the original to retry" is "$(cat "$(FBD)/switch.orig")" true
    check "automatic update's too" is "$(cat "$(FBD)/auto.orig")" on
    unset FAKE_SETTINGS_FAIL
    run off
    check "retried: back on" is "$(switch)" true
    check "and back on" is "$(auto)" on
    check "then let go of it" test ! -e "$(FBD)/switch.orig"
}
test_uninstall_waits_for_storage() {
    app_install
    run_app on
    teardown_watch
    # Early in a start: no app looks installed, the Homebrew Channel included
    rm -rf "$FB_ROOT$APPD" "$FB_ROOT$HBC_APPD"
    OUT=$(FB_GONE_WAIT=0 $SH "$(FBD)/fw-block.sh" boot 2>&1)
    check "not taken for an uninstall" lacks "was uninstalled"
    check "still blocking" is "$(switch)" false
    check "settings kept" test -f "$(FBD)/settings"
}
test_uninstall_retries() {
    app_install
    run_app on
    teardown_watch
    rm -rf "$FB_ROOT$APPD"
    OUT=$(FAKE_SETTINGS_FAIL=1 FB_GONE_WAIT=0 $SH "$(FBD)/fw-block.sh" boot 2>&1)
    check "says it'll try again" has "try again"
    check "hook kept" test -e "$FB_ROOT/var/lib/webosbrew/init.d/50-webos-fw-block"
    check "originals kept" test -f "$(FBD)/switch.orig"
    OUT=$(FB_GONE_WAIT=0 $SH "$(FBD)/fw-block.sh" boot 2>&1)
    check "next start finishes it" has "was uninstalled"
    check "update check back on" is "$(switch)" true
    check "all gone" test ! -e "$(FBD)"
}
test_others_lines_untouched() {
    eth0_new_on
    printf '0.0.0.0 ads.example # my own line\n0.0.0.0 snu.lge.com # webosbrew\n' >> "$FB_ROOT/etc/hosts"
    printf '0.0.0.0 nsu.lge.com # lg-usb-2-eth0 block-updates\n' >> "$FB_ROOT/etc/hosts"
    cp "$FB_ROOT/etc/hosts" "$T/before"
    run on
    run off
    check "every line that wasn't ours, exactly as it was" cmp -s "$T/before" "$FB_ROOT/etc/hosts"
}
test_backup_records_others() {
    eth0_new_on
    echo true > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates"
    hbc_new_on
    run backup
    _d="$(FBD)/backups/$(cd "$(FBD)/backups" && echo *)"
    check "the Homebrew Channel's block" grep -qx "hbcKeepsCheck=1" "$_d/info"
    check "LG-USB-2-ETH0's block" grep -qx "eth0Blocking=1" "$_d/info"
    check "what LG-USB-2-ETH0 saved" grep -qx "eth0SavedCheck=true" "$_d/info"
    check "LG-USB-2-ETH0's settings file" test -f "$_d/lg-usb-2-eth0.conf"
}

test_restart() {
    run restart
    check "the Homebrew Channel's restart call" grep -q "tvpower/power/reboot" "$FB_ROOT/.luna.log"
    check "noted" ev restart
    : > "$FB_ROOT/mnt/lg/cmn_data/.UpdateIsInprogress"
    rm -f "$FB_ROOT/.luna.log"
    run restart
    check "refused while an update installs" is "$RC" 1
    check "says why" has "busy with an update"
    check "no restart call" eval "! grep -q reboot '$FB_ROOT/.luna.log' 2>/dev/null"
}

GH_HEAD='# LG Ad & Telemetry Blackhole (lg-webos-dashboard)'
GH_KEPT='# Kept from /etc/hosts, where other tools put them'
test_glasshouse_hosts() {
    # Glasshouse's own table is what /etc/hosts shows
    printf '%s\n%s\n0.0.0.0 ads.lge.com\n0.0.0.0 ngfts.lge.com\n' "$HOSTS_STOCK" "$GH_HEAD" > "$FB_ROOT/etc/hosts"
    run on
    check "its header added" is "$(grep -cxF "$GH_KEPT" "$FB_ROOT/etc/hosts")" 1
    _kl=$(grep -nxF "$GH_KEPT" "$FB_ROOT/etc/hosts" | cut -d: -f1)
    _fl=$(grep -n "# webos-fw-block\$" "$FB_ROOT/etc/hosts" | head -n 1 | cut -d: -f1)
    check "our lines under it" test "$_fl" -gt "$_kl"
    check "Glasshouse's lines kept" in_hosts "0.0.0.0 ads.lge.com"
    json
    check "named among the others" eval "field others | grep -q glasshouse"
    # Glasshouse dropped our lines (no header yet): put back, header once
    grep -v webos-fw-block "$FB_ROOT/etc/hosts" | grep -vxF "$GH_KEPT" > "$T/h" && cat "$T/h" > "$FB_ROOT/etc/hosts"
    run check
    check "header once" is "$(grep -cxF "$GH_KEPT" "$FB_ROOT/etc/hosts")" 1
    check "lines back" in_hosts "0.0.0.0	nsu.lge.com # webos-fw-block"
    run off
    check "ours gone" eval "! grep -q 'webos-fw-block' '$FB_ROOT/etc/hosts'"
    check "Glasshouse's stay" in_hosts "0.0.0.0 ads.lge.com"
}
test_no_glasshouse_no_header() {
    run on
    check "no header without Glasshouse" eval "! grep -qF 'Kept from' '$FB_ROOT/etc/hosts'"
}

probe() { FB_NODE=$(command -v node) FB_PROBE_HOSTS="$FB_ROOT/etc/hosts" FB_PROBE_SIM="$1" run test --json; printf '%s' "$OUT" > "$T/s.json"; }
tstate() { python3 -c "import json,sys
r=[x for x in json.load(open(sys.argv[1]))['results'] if x['id']==sys.argv[2]]
print(r[0]['state']+(' '+r[0]['detail'] if r and r[0]['detail'] else '') if r else 'none')" "$T/s.json" "$1"; }
test_block_test() {
    probe 'github.com:443=open'
    check "valid JSON" valid_json
    check "check open" is "$(tstate check)" open
    check "servers open" is "$(tstate servers)" "open snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com nsu.lge.com ngfts.lge.com"
    run on
    probe 'github.com:443=open'
    check "check ok" is "$(tstate check)" ok
    check "auto ok" is "$(tstate auto)" ok
    check "servers ok" is "$(tstate servers)" ok
    check "address ok" is "$(tstate address)" ok
    check "remote ok" is "$(tstate remote)" ok
    check "phone waits for a start" is "$(tstate phone)" wait
    check "guard ok" is "$(tstate guard)" ok
    check "no files" is "$(tstate files)" ok
    # The address reachable after all
    probe 'github.com:443=open,156.147.69.32:8080=open'
    check "address open" is "$(tstate address)" open
    # No network at all: can't tell
    probe ''
    check "no network: unknown" is "$(tstate address)" "unknown no-network"
    # A server answering for real
    probe 'github.com:443=open,su.lge.com=open 1.2.3.4'
    check "one server open" is "$(tstate servers)" "open su.lge.com"
    # Without Node.js: read from the settings
    FB_NODE=/nonexistent run test --json; printf '%s' "$OUT" > "$T/s.json"
    check "without node: servers from hosts" is "$(tstate servers)" ok
    check "without node: address from the rule" is "$(tstate address)" "ok rule"
    run report
    check "in the report" has "block test (from the settings):"
}

test_clean_downloads() {
    mkdir -p "$FB_ROOT/mnt/lg/appstore/.update"
    printf 'epkdata' > "$FB_ROOT/mnt/lg/appstore/swupdatefile.epk"
    printf 'usbdata!' > "$FB_ROOT/mnt/lg/cmn_data/usbupdatefile.epk"
    json
    check "two listed" is "$(field downloads | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 2
    check "sizes" is "$(field downloads | python3 -c 'import json,sys; print(sum(x["bytes"] for x in json.load(sys.stdin)))')" 15
    : > "$FB_ROOT/tmp/nsu-running"
    run clean
    check "not while an update runs" has "nothing was deleted"
    check "kept" test -f "$FB_ROOT/mnt/lg/appstore/swupdatefile.epk"
    rm -f "$FB_ROOT/tmp/nsu-running"
    run clean
    check "deleted" has "Deleted 2 firmware files"
    check "gone" test ! -e "$FB_ROOT/mnt/lg/appstore/swupdatefile.epk"
    check "listed in a backup" eval "grep -q swupdatefile.epk '$(FBD)'/backups/*/downloads"
    check "logged" ev "cleaned 2"
    run clean
    check "nothing left" has "No downloaded firmware files"
}

test_flags_clear() {
    : > "$FB_ROOT/mnt/lg/cmn_data/.forceUpdateFlagFile"
    : > "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeNetwork"
    : > "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeSDP"
    json
    check "listed" is "$(field flagFiles)" '[".forceUpdateFlagFile", ".nsuServerTypeNetwork"]'
    run flags-clear
    check "removed" has "Removed 2 LG flag files"
    check "force gone" test ! -e "$FB_ROOT/mnt/lg/cmn_data/.forceUpdateFlagFile"
    check "network switch gone" test ! -e "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeNetwork"
    check "SDP left alone" test -e "$FB_ROOT/mnt/lg/cmn_data/update/.nsuServerTypeSDP"
    check "copies in the backup" eval "ls '$(FBD)'/backups/*/lg-flags/.forceUpdateFlagFile >/dev/null"
    run flags-clear
    check "none left" has "No LG flag files"
}

test_pause() {
    run pause 60
    check "not when off" has "nothing to pause"
    run on
    run pause abc
    check "minutes checked" is "$RC" 1
    run pause 2000
    check "at most a day" is "$RC" 1
    run pause 60
    check "paused" has "Paused for 60 minutes"
    check "update check back on" is "$(switch)" true
    check "hosts lines gone" eval "! grep -q 'webos-fw-block' '$FB_ROOT/etc/hosts'"
    json
    check "until" test "$(field paused)" -gt "$(date +%s)"
    run check
    check "the check doesn't block while paused" is "$(switch)" true
    # The time is up
    sed -i 's/^PAUSE=.*/PAUSE=1000/' "$(FBD)/settings"
    run check
    check "blocked again" is "$(switch)" false
    check "lines back" in_hosts "0.0.0.0	nsu.lge.com # webos-fw-block"
    check "logged" ev "pause-end time"
    check "a notice" grep -q "pause is over" "$FB_ROOT/.luna.log"
    # Ended early
    run pause 30
    run resume
    check "resume" has "blocked again"
    check "switch off again" is "$(switch)" false
    # The next start ends it
    run pause 30
    run boot
    check "boot blocks" is "$(switch)" false
    check "boot ended it" ev "pause-end boot"
    run pause 30
    run on
    json
    check "on ends it" is "$(field paused)" 0
}

test_alerts() {
    run on
    : > "$FB_ROOT/.luna.log"
    echo true > "$FB_ROOT/.switch"
    run check
    check "a notice" grep -q "put back a block" "$FB_ROOT/.luna.log"
    : > "$FB_ROOT/.luna.log"
    echo true > "$FB_ROOT/.switch"
    run check
    check "not again for the same thing" eval "! grep -q createToast '$FB_ROOT/.luna.log'"
    run alerts off
    sed -i '/^alert/d' "$(FBD)/stats"
    : > "$FB_ROOT/.luna.log"
    echo true > "$FB_ROOT/.switch"
    run check
    check "off: none" eval "! grep -q createToast '$FB_ROOT/.luna.log'"
    run alerts on
    run lang es
    sed -i '/^alert/d' "$(FBD)/stats"
    echo true > "$FB_ROOT/.switch"
    run check
    check "in the app's language" grep -q "volvió a poner" "$FB_ROOT/.luna.log"
    run lang xx
    check "only known languages" is "$RC" 1
}

# Glasshouse's table first in the file (as its bind mount shows it), then
# a recheck adds lines later, then the app is uninstalled
test_glasshouse_uninstall() {
    printf '%s\n0.0.0.0 ads.lge.com\n::\tads.lge.com\n%s\n' "$GH_HEAD" "$HOSTS_STOCK" > "$FB_ROOT/etc/hosts"
    cp "$FB_ROOT/etc/hosts" "$T/gh"
    app_install
    run_app on
    teardown_watch
    check "header once" is "$(grep -cxF "$GH_KEPT" "$FB_ROOT/etc/hosts")" 1
    _kl=$(grep -nxF "$GH_KEPT" "$FB_ROOT/etc/hosts" | cut -d: -f1)
    check "every line of ours below it" eval "grep -n 'webos-fw-block' '$FB_ROOT/etc/hosts' | cut -d: -f1 | awk -v k=$_kl '\$1 <= k { bad = 1 } END { exit bad }'"
    check "blocking lines only" eval "! grep 'webos-fw-block\$' '$FB_ROOT/etc/hosts' | grep -v '^#' | grep -qv '^\(0\.0\.0\.0\|::\)	'"
    check "Glasshouse's table untouched" eval "head -n \$(wc -l < '$T/gh') '$FB_ROOT/etc/hosts' | cmp -s - '$T/gh'"
    rm -rf "$FB_ROOT$APPD"
    OUT=$(FB_GONE_WAIT=0 $SH "$FB_ROOT/var/lib/webosbrew/webos-fw-block/fw-block.sh" boot 2>&1)
    check "uninstalled" has "was uninstalled"
    check "only ours removed" is "$(grep -v '^$' "$FB_ROOT/etc/hosts" | grep -vxF "$GH_KEPT")" "$(cat "$T/gh")"
}

for c in fresh on with_hbc_block off off_keeps_switch_that_was_off eth0_owns off_while_eth0_blocks_leaves_switch \
    readonly_hosts check_heals found_update_removed on_removes_found_update hits_counted server_switch_noted \
    luna_down no_iptables redirect_is_not_a_block eth0_leftover_rule others events_json boot boot_when_off boot_eth0 \
    run_dir_link_moved watch_tick report usage auto_update auto_update_already_off remote_support remote_off_kept_across_on \
    remote_hits guard_cancels_download guard_leaves_install guard_leaves_usb guard_quiet_when_idle guard_in_watch lg_flags \
    phone_block phone_off_restores phone_webos25 phone_no_gateway phone_with_eth0 phone_check_heals \
    eth0_new_keeps_auto eth0_remote_support eth0_rs_without_updates \
    phone_toggle guard_toggle uninstall_undoes uninstall_leaves_eth0 ssh_only_not_uninstalled app_update_not_uninstall \
    eth0_keeps_phone_and_downloads eth0_phone_off_fwblock_takes_it eth0_phone_pending \
    backups update update_not_uninstall \
    hbc_keeps_check hbc_old_doesnt_keep_check restore_from_backup_respects_hbc eth0_first_original_kept \
    failed_restore_keeps_original uninstall_waits_for_storage uninstall_retries others_lines_untouched backup_records_others restart \
    glasshouse_hosts glasshouse_uninstall no_glasshouse_no_header block_test clean_downloads flags_clear pause alerts; do
    t "$c" "test_$c"
done

echo
echo "$pass passed, $fail failed${failed:+:$failed}"
[ "$fail" = 0 ]
