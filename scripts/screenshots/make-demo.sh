#!/bin/sh
# Builds scripts/screenshots/demo.js: real fw-block.sh output from fake TVs
# (the test suite's stand-ins), for the screenshots and the UI check.
#   sh scripts/screenshots/make-demo.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FAKE="$ROOT/tests/fakebin"
OUT="$HERE/demo.js"

tv() {
    T=$(mktemp -d)
    export FB_ROOT="$T/root" FB_NOMOUNT=1 FB_FIRST=3600 FB_EVERY=600 FB_LUNA="$FAKE/luna-send" FB_IPTABLES="$FAKE/iptables"
    mkdir -p "$FB_ROOT/etc" "$FB_ROOT/var/luna/preferences" "$FB_ROOT/var/lib/webosbrew/init.d" \
        "$FB_ROOT/mnt/lg/cmn_data/swupdate" "$FB_ROOT/mnt/lg/cmn_data/update" "$FB_ROOT/tmp" "$FB_ROOT/var/run/nyx"
    printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n' > "$FB_ROOT/etc/hosts"
    printf '{"webos_release":"25.10.1","webos_manufacturing_version":"43.21.77"}\n' > "$FB_ROOT/var/run/nyx/os_info.json"
    _g="$FB_ROOT/usr/palm/services/com.webos.service.secondscreen.gateway/interfaces"
    mkdir -p "$_g" && cp "$ROOT/tests/fixtures/update-webos26.interface" "$_g/com.webos.service.update.interface"
    : > "$FB_ROOT/var/luna/preferences/webosbrew_block_updates"
    printf '127.0.0.1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com\n::1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com\n' >> "$FB_ROOT/etc/hosts"
}
sh_() { sh "$ROOT/fw-block.sh" "$@"; }
stopw() { _p=$(cat "$FB_ROOT/tmp/webos-fw-block/watch.pid" 2>/dev/null) && kill "$_p" 2>/dev/null; rm -rf "$T"; }
q() { node -e 'process.stdout.write(JSON.stringify(require("fs").readFileSync(0, "utf8")))'; }

{
    echo '// Made by make-demo.sh from real fw-block.sh runs on fake TVs.  Pick a TV with ?tv=NAME.'
    echo '(function () {'
    echo 'var TVS = {};'

    # Not blocked, only the Homebrew Channel's four servers
    tv
    printf 'TVS.open = { status: %s, events: "[]", report: %s };\n' "$(sh_ status --json | q)" "$(sh_ report | q)"
    stopw

    # Blocked, with a week of catches
    tv
    sh_ on >/dev/null
    # As after a restart: the phone block went in before the gateway started
    echo boot > "$FB_ROOT/tmp/webos-fw-block/phone"
    d="$FB_ROOT/var/lib/webosbrew/webos-fw-block"
    n=$(date +%s)
    {
        echo "$((n - 604800)) on"
        echo "$((n - 600000)) boot"
        echo "$((n - 432000)) stopped 6"
        echo "$((n - 259200)) boot"
        echo "$((n - 259000)) fixed hosts"
        echo "$((n - 86400)) found"
        echo "$((n - 86000)) stopped 4"
        echo "$((n - 7200)) stopped 3"
    } > "$d/events"
    printf 'tries=3\nlast=%s\nfound=%s\nfixed=%s\nfixedWhat=hosts\n' "$((n - 7200))" "$((n - 86400))" "$((n - 259000))" > "$d/stats"
    echo "$((n - 240))" > "$FB_ROOT/tmp/webos-fw-block/last"
    printf 'TVS.blocked = { status: %s, events: %s, report: %s, on: %s, off: %s };\n' "$(sh_ status --json | q)" "$(sh_ events --json | q)" "$(sh_ report | q)" \
        "$(printf 'Turned webOS'"'"'s update check off.\nBlocked update servers in /etc/hosts: snu-dev.lge.com nsu.lge.com ngfts.lge.com\nBlocked 156.147.69.32, the address the updater falls back to.\nFirmware updates are blocked, now and at every start.\n' | q)" \
        "$(printf 'Turned webOS'"'"'s update check back on.\nThe Homebrew Channel'"'"'s own Block system updates is still on (it covers four servers).\nFW Block is off.\n' | q)"
    stopw

    # LG-USB-2-ETH0 does the blocking
    tv
    printf 'BLOCK_UPDATES="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    # 2.11.45 and later: its script knows automaticUpdate, and keeps it off
    printf '#!/bin/sh\n# upd_auto_set: automaticUpdate\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    echo false > "$FB_ROOT/.switch"
    echo off > "$FB_ROOT/.auto"
    printf '0.0.0.0 snu-dev.lge.com nsu.lge.com ngfts.lge.com # lg-usb-2-eth0 block-updates\n' >> "$FB_ROOT/etc/hosts"
    "$FAKE/iptables" -I OUTPUT -d 156.147.69.32/32 -j DROP
    sh_ on >/dev/null
    printf 'TVS.eth0 = { status: %s, events: %s, report: "" };\n' "$(sh_ status --json | q)" "$(sh_ events --json | q)"
    stopw

    # Like the C2 now: LG-USB-2-ETH0 blocks updates and Remote Support, FW Block off
    tv
    printf 'BLOCK_UPDATES="1"\nBLOCK_RS="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    printf '#!/bin/sh\n# upd_auto_set: automaticUpdate\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    echo false > "$FB_ROOT/.switch"
    echo off > "$FB_ROOT/.auto"
    printf '0.0.0.0 snu-dev.lge.com nsu.lge.com ngfts.lge.com # lg-usb-2-eth0 block-updates\n' >> "$FB_ROOT/etc/hosts"
    for _h in rone-tv-aic rone-tv-cic rone-tv-eic rone-tv-kic rone-tv-saic rone-aic rone-eic rone-kic rone-saic; do
        printf '0.0.0.0 %s.lge.com # lg-usb-2-eth0 block-remote-support\n' "$_h" >> "$FB_ROOT/etc/hosts"
    done
    "$FAKE/iptables" -I OUTPUT -d 156.147.69.32/32 -j DROP
    "$FAKE/iptables" -I OUTPUT -d 165.244.62.249/32 -j DROP
    "$FAKE/iptables" -I OUTPUT -d 165.244.99.174/32 -j DROP
    printf 'TVS.eth0off = { status: %s, events: "[]", report: "" };\n' "$(sh_ status --json | q)"
    stopw

    # LG-USB-2-ETH0 keeping every block, FW Block off
    tv
    printf 'BLOCK_UPDATES="1"\nBLOCK_RS="1"\n' > "$FB_ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf"
    printf '#!/bin/sh\n# automaticUpdate secondscreen.gateway dl_guard\n' > "$FB_ROOT/var/lib/webosbrew/init.d/S01fix-eth"
    echo false > "$FB_ROOT/.switch"; echo off > "$FB_ROOT/.auto"
    printf '0.0.0.0 snu-dev.lge.com nsu.lge.com ngfts.lge.com # lg-usb-2-eth0 block-updates\n' >> "$FB_ROOT/etc/hosts"
    for _h in rone-tv-aic rone-tv-cic rone-tv-eic rone-tv-kic rone-tv-saic rone-aic rone-eic rone-kic rone-saic; do
        printf '0.0.0.0 %s.lge.com # lg-usb-2-eth0 block-remote-support\n' "$_h" >> "$FB_ROOT/etc/hosts"
    done
    "$FAKE/iptables" -I OUTPUT -d 156.147.69.32/32 -j DROP
    "$FAKE/iptables" -I OUTPUT -d 165.244.62.249/32 -j DROP
    "$FAKE/iptables" -I OUTPUT -d 165.244.99.174/32 -j DROP
    mkdir -p "$FB_ROOT/tmp/lg-usb-2-eth0"; echo boot > "$FB_ROOT/tmp/lg-usb-2-eth0/lg-usb-2-eth0.phone"
    grep -v UPDATE_FROM_REMOTE_APP "$ROOT/tests/fixtures/update-webos26.interface" > "$_g/com.webos.service.update.interface"
    printf 'TVS.eth0all = { status: %s, events: "[]", report: "" };\n' "$(sh_ status --json | q)"
    stopw

    cat <<'EOJ'
var m = /[?&]tv=(\w+)/.exec(window.location.search);
var tv = TVS[(m && m[1]) || 'blocked'] || TVS.blocked;
window.FB_DEMO = function (args, cb) {
    var a = args.split(' ')[0];
    setTimeout(function () {
        if (a === 'status' || a === 'check') { cb(true, tv.status, ''); }
        else if (a === 'events') { cb(true, tv.events, ''); }
        else if (a === 'report') { cb(true, tv.report, ''); }
        else if (a === 'on' || a === 'off') { cb(true, tv[a] || '', ''); }
        else if (a === 'update-check') { cb(true, '{"current":"0.1.0","latest":"0.1.0","newer":false,"ipkUrl":"","sha256":"","notes":"","published":""}', ''); }
        else if (a === 'backups') { cb(true, '[{"name":"20261119-181302","time":1795129982,"reason":"on","version":"0.1.0","check":"true","auto":"on","block":false},{"name":"20261118-090511","time":1795019111,"reason":"manual","version":"0.1.0","check":"false","auto":"off","block":true}]', ''); }
        else { cb(false, '', 'unknown'); }
    }, 60);
};
}());
EOJ
} > "$OUT"
echo "Wrote $OUT"
