/*
 * WEBOS-FW-BLOCK TV app.
 *
 * A remote-friendly front end for fw-block.sh, bundled in assets/.  Root
 * commands go through the Homebrew Channel's own root service
 * (luna://org.webosbrew.hbchannel.service/exec).  Plain ES5 for older webOS
 * browsers.
 */
(function () {
    'use strict';

    var I18N = window.FB_I18N || null;
    var T = I18N ? I18N.T : function (t, v) { return v ? t.replace(/\{(\w+)\}/g, function (m, k) { return k in v ? v[k] : m; }) : t; };
    var TS = I18N ? I18N.TS : function (t) { return t; };

    var HBC_EXEC = 'luna://org.webosbrew.hbchannel.service/exec';
    var KEY = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13, BACK: 461, ESC: 27, BACKSPACE: 8 };
    var appDir = decodeURIComponent(window.location.pathname).replace(/\/[^\/]*$/, '');
    var SCRIPT = appDir + '/assets/fw-block.sh';
    var REPO = 'github.com/ohmybahgosh/WEBOS-FW-BLOCK';

    var state = null;
    var busy = false;
    var overlayMode = null; // null, 'busy', 'message', 'confirm'
    var onConfirm = null;

    function $(id) { return document.getElementById(id); }
    function esc(s) {
        return String(s === undefined || s === null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function p(html) { return '<p>' + html + '</p>'; }
    function pre(s) { return '<pre>' + esc(s) + '</pre>'; }

    // ------------------------------------------------------------------ luna

    function luna(uri, params, cb) {
        if (typeof window.PalmServiceBridge === 'undefined') {
            cb({ returnValue: false, errorText: 'Not running on a webOS TV' });
            return;
        }
        var bridge = new window.PalmServiceBridge();
        bridge.onservicecallback = function (msg) {
            var reply;
            try { reply = JSON.parse(msg); } catch (e) { reply = { returnValue: false, errorText: 'Unreadable reply' }; }
            bridge = null;
            cb(reply);
        };
        bridge.call(uri, JSON.stringify(params));
    }

    // Run the bundled script as root. cb(ok, stdout, stderr)
    function runScript(args, cb) {
        if (window.FB_DEMO) { window.FB_DEMO(args, cb); return; }
        luna(HBC_EXEC, { command: 'sh ' + shq(SCRIPT) + ' ' + args + ' 2>&1' }, function (r) {
            cb(r.returnValue !== false, r.stdoutString || '', r.errorText || r.stderrString || '');
        });
    }
    function parse(out) {
        var i = out.indexOf('{'), j = out.indexOf('[');
        var at = i < 0 ? j : (j < 0 ? i : Math.min(i, j));
        try { return JSON.parse(out.slice(at)); } catch (e) { return null; }
    }

    // ------------------------------------------------------------------ time

    function pad(n) { return n < 10 ? '0' + n : String(n); }
    function ago(t, now) {
        if (!t) { return T('never'); }
        var s = Math.max(0, (now || Math.floor(Date.now() / 1000)) - t);
        if (s < 90) { return T('just now'); }
        if (s < 5400) { return T('{n} min ago', { n: Math.round(s / 60) }); }
        if (s < 172800) { return T('{n} h ago', { n: Math.round(s / 3600) }); }
        return T('{n} days ago', { n: Math.round(s / 86400) });
    }
    function when(t) {
        var d = new Date(t * 1000);
        return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }

    // ------------------------------------------------------------------ status

    function servers(s) { return s.hostsTotal - (s.hostsMissing || []).length; }
    function gapName(g) {
        return { check: T('update check'), auto: T('Automatic software update'), hosts: T('update servers'), firewall: T('firewall rule'),
            remote: T('LG Remote Support'), phone: T('phone apps'), download: T('found update') }[g] || g;
    }

    // With LG-USB-2-ETH0 blocking: the parts it doesn't keep itself
    function eth0Missing(s) {
        var m = [];
        if (s.remote.by !== 'eth0') { m.push(T('Remote Support')); }
        if (s.phone && s.phone.present && !s.phone.eth0) { m.push(T('phone apps')); }
        if (s.guardBy !== 'eth0') { m.push(T('downloads')); }
        return m;
    }
    function headline(s) {
        if (s.owner === 'eth0') {
            var miss = eth0Missing(s), all = s.level === 'full' && (s.on || !miss.length);
            return { dot: all ? 'ok' : 'warn', text: T('Blocked by LG-USB-2-ETH0'), lit: all,
                sub: s.on ? T('LG-USB-2-ETH0 keeps the main blocks, and FW Block adds the rest.  If LG-USB-2-ETH0\'s block is turned off, FW Block takes over within 10 minutes.')
                    : (miss.length ? T('LG-USB-2-ETH0 keeps the main blocks.  Turn on Block firmware updates to also block: {what}.', { what: miss.join(', ') })
                        : T('LG-USB-2-ETH0 keeps every block FW Block has.  Turn FW Block on too if you want a backup.')) };
        }
        if (s.on && s.level === 'full') {
            return { dot: 'ok', text: T('Firmware updates blocked'), lit: true,
                sub: s.firmware ? T('This TV stays on firmware {fw}.  Checked {ago}, and every 10 minutes.', { fw: s.firmware, ago: ago(s.lastCheck, s.now) })
                    : T('Checked {ago}, and every 10 minutes.', { ago: ago(s.lastCheck, s.now) }) };
        }
        if (s.on) {
            return { dot: 'warn', text: T('Partly blocked'),
                sub: T('Open right now: {what}.  Check now closes it again.', { what: s.gaps.map(gapName).join(', ') }) };
        }
        if (s.level === 'full') {
            return { dot: 'warn', text: T('Blocked, but not kept that way'),
                sub: T('Something else closed LG\'s update path, but nothing checks that it stays closed.  Block firmware updates keeps it closed.') };
        }
        if (s.level === 'partial') {
            return { dot: 'bad', text: T('Only partly blocked'),
                sub: T('Some of LG\'s update path is open.  A firmware update can take root away for good: Block firmware updates closes the rest.') };
        }
        return { dot: 'bad', text: T('Firmware updates NOT blocked'),
            sub: T('A firmware update can take root away for good, and everything installed with it.  Block firmware updates closes LG\'s update path.') };
    }

    // Who keeps a block, by name
    var ETH0 = 'LG-USB-2-ETH0';
    function whoName(w) { return { 'fw-block': T('FW Block'), eth0: ETH0, hbc: T('Homebrew Channel'), other: T('something else') }[w] || ''; }
    function hostsWho(s) {
        var w = [];
        if (s.hostsOurs) { w.push(T('FW Block')); }
        if (s.eth0 && s.eth0.blocking) { w.push(ETH0); }
        if (s.hbcBlock) { w.push(T('Homebrew Channel')); }
        return w.join(' + ');
    }
    function checkWho(s) {
        if (s.checkBy === 'eth0' || (!s.checkBy && s.owner === 'eth0')) { return ETH0; }
        if (s.checkBy === 'fw-block' || (!s.checkBy && s.on)) { return T('FW Block'); }
        if (s.checkBy === 'hbc') { return T('Homebrew Channel'); }
        return '';
    }
    // "off · LG-USB-2-ETH0"
    function by(v, who) { return who ? v + '  ·  ' + who : v; }

    function render(s) {
        state = s;
        var h = headline(s);
        $('dot').className = 'dot dot-' + h.dot;
        $('headline').textContent = h.text;
        $('headline').className = h.lit ? 'lit' : (h.dot === 'bad' ? 'open' : (h.dot === 'warn' ? 'part' : ''));
        $('subline').textContent = h.sub;

        var rows = [];
        function row(k, v, cls) { rows.push('<tr><td>' + esc(k) + '</td><td class="' + (cls || '') + '">' + esc(v) + '</td></tr>'); }
        row(T('Update check'), s.check === 'false' ? by(T('off'), checkWho(s)) : (s.check === 'true' ? T('on: webOS looks for updates') : T('can\'t tell')),
            s.check === 'false' ? 'ok' : (s.check === 'true' ? 'bad' : 'warn'));
        if (s.auto) {
            row(T('Automatic update'), s.auto === 'off' ? by(T('off'), whoName(s.autoBy)) : T('on'), s.auto === 'off' ? 'ok' : 'bad');
        }
        row(T('Update servers'), by(T('{n} of {total} blocked', { n: servers(s), total: s.hostsTotal }), hostsWho(s)), servers(s) === s.hostsTotal ? 'ok' : 'bad');
        if (s.firewall) {
            row(T('Fallback address'), s.firewallBy ? by(T('blocked'), whoName(s.firewallBy)) : T('open'), s.firewallBy ? 'ok' : 'bad');
        }
        if (s.remote.blocked) { row(T('LG Remote Support'), by(T('blocked'), whoName(s.remote.by)), 'ok'); }
        else { row(T('LG Remote Support'), s.on && !s.remote.on && !s.remote.by ? T('not blocked (turned off)') : T('not blocked'), s.on && !s.remote.on ? 'warn' : 'bad'); }
        if (s.phone && s.phone.present) {
            if (s.phone.blocked || (s.phone.nextStart && s.phone.by === 'eth0')) { row(T('Phone apps'), by(s.phone.nextStart ? T('blocked from the next TV start') : T('blocked'), whoName(s.phone.by)), s.phone.nextStart ? 'warn' : 'ok'); }
            else { row(T('Phone apps'), s.on && !s.phone.on ? T('can start an update (turned off)') : T('can start an update'), s.on && !s.phone.on ? 'warn' : 'bad'); }
        }
        if (s.guardBy === 'eth0') { row(T('Download watch'), by(T('on'), ETH0), 'ok'); }
        else if (s.on) { row(T('Download watch'), s.guard && s.watching ? by(T('every 30 seconds'), T('FW Block')) : (s.guard ? T('not running') : T('off (turned off)')), s.guard && s.watching ? 'ok' : 'warn'); }
        row(T('Found update'), s.pending ? T('one is waiting to install') : T('none'), s.pending ? 'bad' : 'ok');
        if (s.stats.cancelled) {
            row(T('Downloads stopped'), T('{n}, the last {ago}', { n: s.stats.cancelled, ago: ago(s.stats.lastCancel, s.now) }), 'ok');
        }
        if (s.stats.tries) {
            row(T('Updater tries stopped'), T('{n}, the last {ago}', { n: s.stats.tries, ago: ago(s.stats.last, s.now) }), 'ok');
        }
        $('facts').innerHTML = rows.join('');

        var notes = [];
        function note(text, tip) { notes.push('<li' + (tip ? ' class="tip"' : '') + '>' + esc(text) + '</li>'); }
        if (s.on && !s.watching) { note(T('The 10-minute check isn\'t running.  Check now starts it again.')); }
        if (s.on && !s.hook) { note(T('The startup hook is missing, so the block won\'t come back after a restart.  Turn the block off and on again.')); }
        if (s.serverSwitch === 'Network') { note(T('webOS was switched to its "network" update server, which is an address with no name.  The firewall rule is what stops it, so keep FW Block on.'), true); }
        else if (s.serverSwitch) { note(T('webOS was switched to another update server ({name}).  The update check stays off, so it still can\'t update.', { name: s.serverSwitch }), true); }
        if ((s.lgFlags || []).indexOf('force') >= 0) { note(T('LG left a forced-update flag on this TV.  FW Block leaves LG\'s files alone, and the blocks still stop it.'), true); }
        if ((s.lgFlags || []).indexOf('debug') >= 0) { note(T('LG debug files that redirect the updater are on this TV.  A retail TV ignores them, and the blocks still apply.'), true); }
        if (s.updaterBusy && s.on) { note(T('webOS\'s updater is busy right now.  FW Block stops any download within 30 seconds.'), true); }
        if ((s.others || []).indexOf('eth0-leftover') >= 0) { note(T('LG-USB-2-ETH0 left update-block lines behind.  They\'re harmless, and turning its --block-updates off removes them.'), true); }
        if (!s.on && s.eth0.installed && !s.eth0.blocking) { note(T('LG-USB-2-ETH0 is installed with its --block-updates off.  FW Block does the same job on its own.'), true); }
        $('findings').innerHTML = notes.join('');
        $('status').className = 'card' + (rows.length + notes.length >= 8 ? ' compact' : '');

        $('meta').innerHTML = esc('v' + s.version) + (s.webos ? '<br>' + esc('webOS ' + s.webos) : '') + (s.firmware ? esc('  ·  ' + T('firmware {fw}', { fw: s.firmware })) : '');
        renderToggles(s);
        $('check-hint').textContent = s.on ? T('puts back anything that was undone') : T('shows what\'s open');
        $('events-hint').textContent = s.stats.tries ? T('{n} updater tries stopped', { n: s.stats.tries }) : T('tries stopped, fixes made');
        fitRows();
        focusCurrent();
    }

    // The switches on the Blocks tab.  A row another app keeps says so, and
    // the other switches wait for the main one.
    function tog(id, on) { $('tog-' + id).className = 'tog' + (on ? ' on' : ''); }
    // The line under a switch: an optional colored tag that says why it's
    // in that state, then what it does.  Nothing is faded: every switch
    // works, and the tag says what pressing it means.
    function hint(id, text, tag, cls) {
        $(id + '-hint').innerHTML = (tag ? '<span class="tag ' + cls + '">' + esc(tag) + '</span>' : '') + esc(text);
    }
    function renderToggles(s) {
        var e0 = s.eth0 && s.eth0.blocking;
        tog('main', s.on);
        if (s.on) {
            hint('main', e0 ? T('adds what LG-USB-2-ETH0 doesn\'t cover, and takes over if its block is turned off') : T('now and at every start, checked every 10 minutes'));
        } else {
            var miss = e0 ? eth0Missing(s) : [];
            hint('main', !e0 ? T('LG can update this TV, and an update can take root away for good')
                : (miss.length ? T('LG-USB-2-ETH0 blocks the main routes, but not: {what}', { what: miss.join(', ') })
                    : T('LG-USB-2-ETH0 blocks everything this would.  Turn it on as a backup.')),
                T('Off'), !e0 ? 'red' : (miss.length ? 'amber' : 'gray'));
        }

        var need = T('Needs the main switch');
        if (s.remote.by === 'eth0') {
            tog('remote', true);
            hint('remote', T('LG can\'t push an update in a support session.  Change it in LG-USB-2-ETH0.'), T('Kept by LG-USB-2-ETH0'), 'green');
        } else if (!s.on) {
            tog('remote', false);
            hint('remote', T('stops LG pushing an update in a support session'), need, 'amber');
        } else {
            tog('remote', s.remote.on);
            if (s.remote.on) { hint('remote', T('LG can\'t push an update in a support session')); }
            else { hint('remote', T('LG can push an update during a support session'), T('Off by your choice'), 'amber'); }
        }

        var ph = s.phone || {};
        tog('phone', s.on && ph.on && ph.present);
        if (!ph.present) { hint('phone', T('this TV\'s firmware has no phone app updates'), T('Not needed'), 'gray'); }
        else if (ph.eth0) {
            tog('phone', true);
            if (!ph.blocked && ph.nextStart) { hint('phone', T('LG-USB-2-ETH0 blocks them from the next TV start.  Change it in LG-USB-2-ETH0.'), T('From the next TV start'), 'amber'); }
            else if (ph.nextStart) { hint('phone', T('LG-USB-2-ETH0 blocks them from the next TV start.  Change it in LG-USB-2-ETH0.'), T('Kept by LG-USB-2-ETH0'), 'green'); }
            else { hint('phone', T('Casting and remote control keep working.  Change it in LG-USB-2-ETH0.'), T('Kept by LG-USB-2-ETH0'), 'green'); }
        }
        else if (!s.on) { hint('phone', T('stops a paired phone app starting an update'), need, 'amber'); }
        else if (!ph.on) { hint('phone', T('a paired phone app can start an update'), T('Off by your choice'), 'amber'); }
        else if (ph.nextStart) { hint('phone', T('Casting and remote control keep working.'), T('From the next TV start'), 'amber'); }
        else { hint('phone', T('Casting, remote control and the rest keep working.')); }

        tog('guard', (s.on && s.guard) || s.guardBy === 'eth0');
        if (s.guardBy === 'eth0') { hint('guard', T('a download that starts anyway is stopped.  Change it in LG-USB-2-ETH0.'), T('Kept by LG-USB-2-ETH0'), 'green'); }
        else if (!s.on) { hint('guard', T('stops a firmware download that starts anyway'), need, 'amber'); }
        else if (!s.guard) { hint('guard', T('a download that starts anyway isn\'t stopped'), T('Off by your choice'), 'amber'); }
        else { hint('guard', T('a download that starts anyway is stopped within 30 seconds')); }
    }

    function noRoot(err) {
        $('dot').className = 'dot dot-bad';
        $('headline').textContent = T('No root access');
        $('subline').textContent = T('This app runs as root through the Homebrew Channel.  Open the Homebrew Channel once, check it says the system is rooted, then come back.');
        $('facts').innerHTML = err ? '<tr><td>' + esc(T('Error')) + '</td><td class="bad">' + esc(err) + '</td></tr>' : '';
        $('findings').innerHTML = '';
    }

    function refresh(cb) {
        runScript('status --json', function (ok, out, err) {
            var s = ok ? parse(out) : null;
            if (s && s.version) { render(s); } else { noRoot(err || out); }
            if (cb) { cb(s); }
        });
    }

    // ------------------------------------------------------------------ overlay

    function overlay(mode, title, body, hint) {
        overlayMode = mode;
        $('overlay-title').textContent = title;
        $('overlay-body').innerHTML = body;
        $('overlay-hint').textContent = hint || '';
        $('overlay').className = 'overlay';
        // The layers list gets the tighter panel
        document.querySelector('.panel').className = 'panel' + (body.indexOf('class="layers"') >= 0 ? ' tall' : '');
    }
    var onClose = null;
    function closeOverlay() {
        var after = onClose;
        overlayMode = null;
        onConfirm = null;
        onClose = null;
        $('overlay').className = 'overlay hidden';
        focusCurrent();
        if (after) { after(); }
    }
    // message(title, body[, after]): after runs once it's closed
    function message(title, body, after) {
        overlay('message', title, body, T('Press OK or BACK to close.'));
        onClose = after || null;
    }
    function confirm(title, body, fn) {
        onConfirm = fn;
        overlay('confirm', title, body, T('Press OK to go ahead, or BACK to cancel.'));
    }
    // A list to choose from: UP and DOWN move, OK picks, BACK closes
    var pickItems = [], pickAt = 0;
    function pickDraw() {
        $('overlay-body').innerHTML = (pickItems.intro || '') + '<div class="pick">' + pickItems.map(function (it, i) {
            return '<div class="' + (i === pickAt ? 'sel' : '') + '" data-i="' + i + '">' + esc(it.label) + (it.sub ? '<small>' + esc(it.sub) + '</small>' : '') + '</div>';
        }).join('') + '</div>';
        // Long lists scroll to keep the chosen one in view
        var box = $('overlay-body').querySelector('.pick'), sel = box && box.querySelector('.sel');
        if (box && sel) {
            // .pick is the items' offsetParent (position: relative)
            var top = sel.offsetTop, bottom = top + sel.offsetHeight;
            if (top < box.scrollTop) { box.scrollTop = top; }
            else if (bottom > box.scrollTop + box.clientHeight) { box.scrollTop = bottom - box.clientHeight; }
        }
        Array.prototype.slice.call($('overlay-body').querySelectorAll('.pick div')).forEach(function (el) {
            el.addEventListener('mouseover', function () { pickAt = +el.getAttribute('data-i'); pickDraw(); });
            el.addEventListener('click', function (ev) { ev.stopPropagation(); var it = pickItems[+el.getAttribute('data-i')]; closeOverlay(); if (it) { it.fn(); } });
        });
    }
    function pickMove(d) { pickAt = Math.max(0, Math.min(pickItems.length - 1, pickAt + d)); pickDraw(); }
    function pick(title, intro, items) {
        pickItems = items; pickItems.intro = intro; pickAt = 0;
        overlay('pick', title, '', T('UP and DOWN to choose, OK to pick, BACK to close.'));
        pickDraw();
    }

    function working(title) {
        overlay('busy', title, '<span class="spinner"></span>' + esc(T('Working on it…')), '');
    }

    // Run a command that changes something, then show what it said
    function act(title, args, after) {
        busy = true;
        working(title);
        runScript(args, function (ok, out, err) {
            busy = false;
            refresh(function () {
                var text = TS((out || err || '').replace(/\s+$/, ''));
                if (after) { after(ok, text); return; }
                message(ok ? T('{title}: done', { title: title }) : T('{title}: something went wrong', { title: title }), text ? pre(text) : '');
            });
        });
    }

    // ------------------------------------------------------------------ actions

    function layersBody(s) {
        function ok(good, text) {
            return good ? '<span class="ok">' + esc(text) + '</span>' : '<span class="bad">' + esc(T('open')) + '</span>';
        }
        function dim(text) { return '<span class="dim">' + esc(text) + '</span>'; }
        var r = [
            ['1', T('webOS\'s own update check'), T('A hidden setting, and the visible Automatic software update.  With them off, the updater doesn\'t even ask LG.  They hold from the moment the TV starts.'),
                ok(s.check === 'false' && s.auto !== 'on', by(T('off'), checkWho(s)))],
            ['2', T('Updates it already found'), T('Update details webOS saved are deleted, so a found update can\'t install.'),
                s.pending ? '<span class="bad">' + esc(T('one is waiting')) + '</span>' : '<span class="ok">' + esc(T('none')) + '</span>'],
            ['3', T('LG\'s update servers'), T('snu, su, su-ssl, su-dev, snu-dev, nsu and ngfts.lge.com go nowhere in /etc/hosts.'),
                ok(servers(s) === s.hostsTotal, by(T('{n} of {total}', { n: servers(s), total: s.hostsTotal }), hostsWho(s)))],
            ['4', T('The address with no name'), T('156.147.69.32, which the updater uses with its "network" server, is dropped by a firewall rule.'),
                s.firewall ? ok(!!s.firewallBy, by(T('blocked'), whoName(s.firewallBy))) : dim(T('no firewall on this TV'))],
            ['5', T('LG Remote Support'), T('In a support session, LG can hand the updater a download directly.  Its servers and addresses are blocked.'),
                s.remote.blocked ? ok(true, by(T('blocked'), whoName(s.remote.by))) : (s.on && !s.remote.on ? dim(T('turned off')) : ok(false))],
            ['6', T('Phone apps'), T('A paired phone app can\'t start an update.  Casting, remote control and everything else a phone does keep working.'),
                !s.phone || !s.phone.present ? dim(T('not on this TV'))
                    : (s.phone.blocked && s.phone.nextStart ? '<span class="warn">' + esc(T('from the next start')) + '</span>'
                        : (s.on && !s.phone.on ? dim(T('turned off')) : ok(s.phone.blocked, by(T('blocked'), whoName(s.phone.by) || T('FW Block')))))],
            ['7', T('Downloads that start anyway'), T('From a support session or the antenna.  Stopped within 30 seconds.  An install already running is left alone.'),
                s.guardBy === 'eth0' ? ok(true, by(T('watching'), ETH0))
                    : (s.watching && s.guard ? ok(true, by(T('watching'), T('FW Block'))) : dim(s.on && !s.guard ? T('turned off') : T('not running')))]
        ];
        // Not a block of its own: the check that keeps the others in place
        var again = s.on
            ? (s.watching ? '<span class="ok">' + esc(T('FW Block checks all of these every 10 minutes and puts back anything that was undone.')) + '</span>'
                : '<span class="bad">' + esc(T('FW Block\'s 10-minute check isn\'t running.  Check now starts it again.')) + '</span>')
            : '<span class="dim">' + esc(T('With FW Block on, it checks all of these every 10 minutes and puts back anything that was undone.')) + '</span>';
        return '<table class="layers">' + r.map(function (x) {
            return '<tr><td>' + x[0] + '</td><td>' + esc(x[1]) + '<small>' + esc(x[2]) + '</small></td><td>' + x[3] + '</td></tr>';
        }).join('') + '</table><div class="again"><svg class="again-ic" viewBox="0 0 24 24" width="26" height="26"><path d="M20 12a8 8 0 1 1-2.34-5.66" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>' + again + '</div>';
    }

    function eventText(e) {
        switch (e.kind) {
            case 'on': return T('Turned on');
            case 'off': return T('Turned off');
            case 'boot': return T('The TV started: block put in place');
            case 'standby': return T('Standing by: LG-USB-2-ETH0 blocks updates');
            case 'resumed': return T('Took over from LG-USB-2-ETH0');
            case 'fixed': return T('Put back: {what}', { what: e.detail.split(',').map(gapName).join(', ') });
            case 'found': return T('Deleted an update webOS had found');
            case 'stopped': return T('Stopped the updater reaching LG ({n} packets)', { n: e.detail });
            case 'cancelled': return T('Stopped a firmware download');
            case 'installing': return T('A firmware update was installing (left alone)');
            case 'remote': return T('Stopped LG Remote Support reaching LG ({n} packets)', { n: e.detail });
            case 'remote-on': return T('LG Remote Support blocked');
            case 'remote-off': return T('LG Remote Support no longer blocked');
            case 'phone-on': return T('Phone apps blocked');
            case 'phone-off': return T('Phone apps no longer blocked');
            case 'guard-on': return T('Download watch on');
            case 'guard-off': return T('Download watch off');
            case 'flags': return T('LG flag files found: {what}', { what: e.detail });
            case 'backup': return T('Saved a backup');
            case 'restored': return T('Restored the backup from {name}', { name: e.detail });
            case 'updated': return T('Updated FW Block to v{v}', { v: e.detail });
            case 'server': return T('webOS switched to another update server ({name})', { name: e.detail });
            default: return e.kind + (e.detail ? ' ' + e.detail : '');
        }
    }

    // Turning something off never touches another app's block: say so
    function othersStay(s) {
        var w = [];
        if (s.eth0 && s.eth0.blocking) { w.push(T('LG-USB-2-ETH0\'s own update block stays on, with its settings unchanged.')); }
        if (s.hbcBlock) { w.push(T('The Homebrew Channel\'s Block system updates stays on.')); }
        return w.length ? p(esc(w.join('  '))) : '';
    }
    // A switch that comes with the main one: offer to turn that on
    function needsMain() {
        actions.main();
    }

    function backupReason(r) {
        return { on: T('before turning on'), restore: T('before restoring'), update: T('before an update'), manual: T('by hand') }[r] || r;
    }

    // ------------------------------------------------------------------ updates

    var upd = null;
    function checkUpdate(cb) {
        runScript('update-check', function (ok, out) {
            upd = parse(out) || { error: 'no-answer' };
            updateHint();
            if (cb) { cb(); }
        });
    }
    function updateHint() {
        var v = (state && state.version) || (upd && upd.current) || '';
        if (!upd) { hint('update', T('v{v}, checking for a newer one…', { v: v })); return; }
        if (upd.error) { hint('update', T('v{v}.  Couldn\'t check for a newer one: {e}', { v: v, e: updErr(upd.error) })); return; }
        if (upd.newer) { hint('update', T('v{v} is out, with what\'s new', { v: upd.latest }), T('Update'), 'amber'); return; }
        hint('update', T('v{v}, the latest', { v: v }), T('Up to date'), 'green');
    }
    // An update error code in plain words
    function updErr(e) {
        return {
            'no-node': T('this TV has no Node.js to check with'),
            'bad-signature': T('the release isn\'t signed with the project\'s key, so it wasn\'t trusted'),
            'unexpected-url': T('the release points somewhere it shouldn\'t, so it wasn\'t trusted'),
            'bad-manifest': T('the release\'s details couldn\'t be read'),
            'nothing-newer': T('there\'s nothing newer'),
            'bad-check': T('the last check didn\'t look right, so check again'),
            'no-answer': T('no answer from GitHub')
        }[e] || (/^(http-|E[A-Z]|network|too-big|insecure)/.test(e || '') ? T('no answer from GitHub') + ' (' + e + ')' : (e || '?'));
    }
    function notesHtml(text) {
        return '<p class="dim">' + esc(T('What\'s new, from the release notes (in English):')) + '</p><div class="notes">' + esc(text.replace(/\*\*/g, '').replace(/^#+ /gm, '')) + '</div>';
    }
    function showUpdate() {
        if (!upd || upd.error) {
            message(T('Updates'), p(esc(T('Couldn\'t check GitHub for a newer FW Block: {e}.  Check the TV is online and try again.', { e: updErr(upd && upd.error) }))));
            return;
        }
        if (!upd.newer) {
            message(T('Updates'), p(esc(T('FW Block v{v} is the latest.', { v: upd.current }))) + p(esc(T('Releases are signed, and the app checks the signature before it installs one.'))));
            return;
        }
        confirm(T('Update to v{v}?', { v: upd.latest }),
            (upd.notes ? notesHtml(upd.notes) : '') +
            p(esc(T('The Homebrew Channel downloads and installs it, after checking it\'s the signed release.  The app closes and opens again.  The block stays on the whole time.'))),
            function () {
                busy = true;
                working(T('Updating to v{v}', { v: upd.latest }));
                runScript('update-install', function (ok, out) {
                    var r = parse(out) || {};
                    if (r.error) { busy = false; message(T('Updates'), p(esc(T('The update didn\'t start: {e}', { e: updErr(r.error) })))); return; }
                    var tries = 0;
                    var poll = setInterval(function () {
                        runScript('update-status', function (ok2, out2) {
                            var st = parse(out2) || {};
                            tries++;
                            if (st.state === 'failed' || tries > 200) {
                                clearInterval(poll);
                                busy = false;
                                message(T('Updates'), p(esc(T('The update failed: {e}.  Nothing changed: FW Block v{v} is still installed and blocking.', { e: st.error || '?', v: upd.current }))));
                            }
                        });
                    }, 3000);
                });
            });
    }
    // Opened again after an update: what's new
    function launchParams() {
        try { return JSON.parse((window.PalmSystem && window.PalmSystem.launchParams) || '{}') || {}; } catch (e) { return {}; }
    }
    function showUpdated(v) {
        runScript('changes ' + shq(v), function (ok, out) {
            message(T('Updated to v{v}', { v: v }), out ? notesHtml(out) : '');
        });
    }

    // ------------------------------------------------------------------ restart

    // The phone app block waits for the next TV start: offer to restart now
    function phoneWaiting(s) { return !!(s && s.phone && s.phone.present && !s.phone.blocked && s.phone.nextStart); }
    function offerRestart(title, resultText, who) {
        confirm(T('Restart the TV now?'),
            (resultText ? pre(resultText) : '') +
            p(esc(who === 'eth0'
                ? T('LG-USB-2-ETH0 blocks phone apps from the next TV start.  Restart now to finish, or choose BACK and it happens the next time the TV starts.')
                : T('Everything else is already blocked.  Phone apps are blocked from the next TV start: restart now to finish, or choose BACK and it happens the next time the TV starts.'))) +
            p('<span class="dim">' + esc(T('The TV turns off and on again, which takes about a minute.  FW Block won\'t restart it while an update is installing.')) + '</span>'),
            function () {
                busy = true;
                working(T('Restarting the TV'));
                runScript('restart', function (ok, out, err) {
                    busy = false;
                    if (!ok) { message(T('Restart the TV now?'), pre(TS((err || out || '').replace(/\s+$/, '')))); }
                });
            });
    }
    // Turn something on, then offer the restart if the phone block is waiting
    function actThenRestart(title, args) {
        act(title, args, function (ok, text) {
            if (ok && phoneWaiting(state) && state.phone.by !== 'eth0') { offerRestart(title, text, 'fw-block'); return; }
            message(ok ? T('{title}: done', { title: title }) : T('{title}: something went wrong', { title: title }), text ? pre(text) : '');
        });
    }

    // ------------------------------------------------------------------ what each block does

    function explainItems() {
        var E = [
            [T('1.  webOS\'s own update check'), T('Off, so the updater doesn\'t ask LG at all'),
                [T('webOS has two settings that decide whether the TV looks for updates: a hidden one (softwareUpdateEnable) and the visible Automatic software update.  The automatic check reads both.  FW Block turns both off.'),
                 T('They\'re saved settings, so they hold from the moment the TV starts, before anything else is in place.  This alone stops the updater from asking LG.'),
                 T('FW Block remembers what they were and puts them back when turned off, unless LG-USB-2-ETH0 or the Homebrew Channel still keeps them off.  Then it leaves them off, so the update check never comes back on behind another app\'s back.')]],
            [T('2.  Updates it already found'), T('Deleted, so they can\'t install'),
                [T('If webOS found or downloaded an update before the block was on, the details it saved are deleted, so it can\'t install and a waiting prompt goes away.'),
                 T('This is checked again every 10 minutes and at every start.')]],
            [T('3.  LG\'s update servers'), T('All seven sent nowhere'),
                [T('snu, su, su-ssl, su-dev, snu-dev, nsu and ngfts.lge.com are sent nowhere in /etc/hosts.  The Homebrew Channel\'s Block system updates covers four of them; FW Block adds the rest.'),
                 T('Only lines nothing else has are added, marked as FW Block\'s, so turning it off takes out exactly those and leaves every other line as it was.')]],
            [T('4.  The address with no name'), T('Dropped by a firewall rule'),
                [T('LG can switch the updater to a server it reaches straight by its address (156.147.69.32), which no hosts file can block.'),
                 T('A firewall rule in a chain of FW Block\'s own (FWBLOCK) drops it.  The rule also counts every try, which is how What it caught knows the updater tried.')]],
            [T('5.  LG Remote Support'), T('Its servers blocked, with a switch'),
                [T('During an LG Remote Support session, LG\'s staff can hand the updater a download address directly, skipping the update check.'),
                 T('FW Block blocks Remote Support\'s servers and the two addresses it uses without a name.  While it\'s on, LG support can\'t connect: turn it off first if they ever need to.')]],
            [T('6.  Phone apps'), T('Can\'t start an update; casting still works'),
                [T('A paired phone app with LG\'s update permission can tell the TV to update from a file on the phone.  That comes straight over your home network, so no server block touches it.'),
                 T('The TV\'s phone connection reads what phones may do from one small file per service.  FW Block covers the update service\'s file with a copy that keeps only its read-only calls.  Casting, the phone remote and the ThinQ app keep working.'),
                 T('The phone connection reads that file when the TV starts, so this holds from the next start.  FW Block offers to restart the TV for you.')]],
            [T('7.  Stop downloads'), T('A download that starts anyway, cancelled'),
                [T('The last line of defense, for a route nobody knows of yet.  Every 30 seconds, only while the updater says it\'s busy, FW Block asks what it\'s doing and cancels a download, with a notice on the TV.'),
                 T('An install already running is never stopped (that could break the TV), and a USB update you start yourself is left alone.')]],
            [T('Kept closed'), T('Checked every 10 minutes and at every start'),
                [T('These TVs can go weeks in standby without a start, so FW Block checks all of the above every 10 minutes and puts back anything that was undone.  What it caught lists everything it stopped or put back.'),
                 T('A startup hook in the Homebrew Channel\'s init.d does it all again at every start.')]],
            [T('Safety and other apps'), T('Backups, and never touching their settings'),
                [T('FW Block never changes the Homebrew Channel\'s or LG-USB-2-ETH0\'s settings, lines or rules.  It reads them to know what they already block, and adds only the rest.'),
                 T('Before it turns on, restores a backup or installs an update, it saves a backup.  Settings are written to a new file and checked before they replace the old one.  If something can\'t be undone, it keeps what it needs and tries again.'),
                 T('Uninstalling the app undoes everything it added, once it\'s sure the app is really gone.')]]
        ];
        return E;
    }

    var actions = {
        main: function () {
            var s = state || {};
            if (!s.on) {
                confirm(T('Block firmware updates?'),
                    (s.eth0 && s.eth0.blocking ? p(esc(T('LG-USB-2-ETH0 already blocks updates, so FW Block adds only what it lacks, and takes over if that\'s turned off.  It doesn\'t change LG-USB-2-ETH0\'s settings.'))) : '')
                    + p(esc(T('This turns webOS\'s update checks off, deletes any update it already found, sends LG\'s update servers and Remote Support nowhere, drops the addresses they use without a name, and stops paired phone apps from starting an update.  A download that starts anyway is stopped.  It does that again at every start, and checks every 10 minutes.')))
                    + p(esc(T('The Homebrew Channel\'s own settings aren\'t changed.  Turning it off undoes all of it.'))),
                    function () { actThenRestart(T('Block firmware updates'), 'on'); });
            } else {
                confirm(T('Turn FW Block off?'),
                    p(esc(T('This removes only what FW Block added: its lines in /etc/hosts, its firewall rules, the phone app block and its startup hook, and puts back the update settings it changed.'))) + othersStay(s)
                    + (s.eth0 && s.eth0.blocking ? '' : p('<span class="bad">' + esc(T('With nothing else blocking, LG can then update this TV\'s firmware, and a firmware update can take root away for good.')) + '</span>')),
                    function () { act(T('Turn FW Block off'), 'off'); });
            }
        },
        remote: function () {
            var s = state || {};
            if (s.remote && s.remote.by === 'eth0') {
                message(T('LG Remote Support'), p(esc(T('LG-USB-2-ETH0 blocks LG Remote Support on this TV (its Block LG Remote Support).  FW Block leaves that to it.  To change it, use LG-USB-2-ETH0.'))));
                return;
            }
            if (!s.on) { needsMain(); return; }
            if (s.remote.on) {
                confirm(T('Stop blocking LG Remote Support?'),
                    p(esc(T('During a support session, LG can then hand this TV a firmware download directly, skipping every other block.  Only do this if LG support needs to connect.'))) + othersStay(s),
                    function () { act(T('LG Remote Support'), 'remote off'); });
            } else {
                act(T('LG Remote Support'), 'remote on');
            }
        },
        phone: function () {
            var s = state || {};
            if (!s.phone || !s.phone.present) { return; }
            if (s.phone.eth0) {
                if (phoneWaiting(s)) { offerRestart(T('Phone apps'), '', 'eth0'); return; }
                message(T('Phone apps'), p(esc(T('LG-USB-2-ETH0 blocks phone apps from starting an update on this TV.  FW Block leaves that to it.  To change it, use LG-USB-2-ETH0.'))));
                return;
            }
            if (s.on && s.phone.on && phoneWaiting(s)) {
                pick(T('Phone apps'), p(esc(T('Phone apps are blocked from the next TV start.'))), [
                    { label: T('Restart the TV now'), sub: T('so the block takes hold right away'), fn: function () { offerRestart(T('Phone apps'), '', 'fw-block'); } },
                    { label: T('Stop blocking phone apps'), sub: T('turn this block off instead'), fn: function () {
                        confirm(T('Stop blocking phone apps?'),
                            p(esc(T('A paired phone app with LG\'s update permission can then make the TV update from a file on the phone, over your home network.  No other block stops that.'))) + p(esc(T('It takes effect at the next TV start.'))),
                            function () { act(T('Phone apps'), 'phone off'); });
                    } }
                ]);
                return;
            }
            if (!s.on) { needsMain(); return; }
            if (s.phone.on) {
                confirm(T('Stop blocking phone apps?'),
                    p(esc(T('A paired phone app with LG\'s update permission can then make the TV update from a file on the phone, over your home network.  No other block stops that.'))) + p(esc(T('It takes effect at the next TV start.'))),
                    function () { act(T('Phone apps'), 'phone off'); });
            } else {
                actThenRestart(T('Phone apps'), 'phone on');
            }
        },
        guard: function () {
            var s = state || {};
            if (s.guardBy === 'eth0') {
                message(T('Stop downloads'), p(esc(T('LG-USB-2-ETH0 stops firmware downloads on this TV.  FW Block leaves that to it.  To change it, use LG-USB-2-ETH0.'))));
                return;
            }
            if (!s.on) { needsMain(); return; }
            if (s.guard) {
                confirm(T('Stop watching downloads?'),
                    p(esc(T('The other blocks stay on.  A firmware download that starts anyway (from a support session or the antenna) is then no longer stopped.'))),
                    function () { act(T('Stop downloads'), 'guard off'); });
            } else {
                act(T('Stop downloads'), 'guard on');
            }
        },
        about: function () {
            message(T('About'), p(esc(T('FW Block keeps LG firmware updates off a rooted LG webOS TV, so root and everything installed with it stay.'))) +
                p(esc(T('Version {v}.', { v: (state && state.version) || '' }))) +
                p(esc(T('Free and open source under the MIT License.  Copyright (c) 2026 OhMyBahGosh.  The full license is in the app\'s LICENSE file and on GitHub.'))) +
                p(esc(T('Not affiliated with LG Electronics.  LG and webOS are trademarks of their owners.'))) +
                p('<span class="ok">' + esc(REPO) + '</span>'));
        },
        explain: function () {
            var E = explainItems();
            function list(at) {
                pick(T('What each block does'), p(esc(T('Choose one to read more.'))), E.map(function (e, i) {
                    return { label: e[0], sub: e[1], fn: function () {
                        message(e[0], e[2].map(function (t) { return p(esc(t)); }).join(''), function () { list(i); });
                    } };
                }));
                if (at) { pickAt = at; pickDraw(); }
            }
            list(0);
        },
        update: function () {
            if (!upd || upd.error) {
                busy = true;
                working(T('Updates'));
                checkUpdate(function () { busy = false; closeOverlay(); showUpdate(); });
                return;
            }
            showUpdate();
        },
        backups: function () {
            busy = true;
            working(T('Backups'));
            runScript('backups --json', function (ok, out) {
                busy = false;
                var list = (ok && parse(out)) || [];
                var items = [{ label: T('Back up now'), sub: T('saves what FW Block and webOS\'s update settings are right now'), fn: function () { act(T('Backups'), 'backup', function () { actions.backups(); }); } }];
                list.slice(0, 8).forEach(function (b) {
                    items.push({
                        label: when(b.time) + '  ·  ' + backupReason(b.reason),
                        sub: T('FW Block {state}, update check {check}, automatic update {auto}', { state: b.block ? T('on') : T('off'), check: b.check === 'true' ? T('on') : (b.check === 'false' ? T('off') : '?'), auto: b.auto === 'on' ? T('on') : (b.auto === 'off' ? T('off') : '?') }),
                        fn: function () {
                            confirm(T('Restore this backup?'),
                                p(esc(T('This puts FW Block\'s switches and webOS\'s update settings back the way they were on {when}, and turns FW Block {state} to match.  A backup of how things are now is saved first.', { when: when(b.time), state: b.block ? T('on') : T('off') }))) +
                                (b.block ? '' : p('<span class="bad">' + esc(T('FW Block was off in this backup.  With nothing else blocking, LG can then update this TV\'s firmware.')) + '</span>')),
                                function () { act(T('Restore'), 'restore ' + shq(b.name)); });
                        }
                    });
                });
                pick(T('Backups'), p(esc(list.length ? T('FW Block saves one by itself before it turns the block on, restores a backup or installs an update.  The newest 10 are kept.') : T('No backups yet.  FW Block saves one by itself before it turns the block on.'))), items);
            });
        },
        check: function () {
            busy = true;
            working(T('Check now'));
            runScript('check --json', function (ok, out) {
                busy = false;
                var s = ok ? parse(out) : null;
                if (!s || !s.version) { message(T('Check now'), pre(out)); return; }
                render(s);
                var h = headline(s);
                message(h.text, p(esc(h.sub)) + layersBody(s));
            });
        },
        layers: function () {
            if (!state) { return; }
            message(T('Every block, and who keeps it'), layersBody(state));
        },
        events: function () {
            busy = true;
            working(T('What it caught'));
            runScript('events --json', function (ok, out) {
                busy = false;
                var list = (ok && parse(out)) || [];
                if (!list.length) { message(T('What it caught'), p(esc(T('Nothing yet.  Each time the block stops the updater or puts something back, it shows here.')))); return; }
                list = list.slice(-14).reverse();
                message(T('What it caught'), '<div class="ev">' + list.map(function (e) {
                    return '<div><span class="t">' + esc(when(e.t)) + '</span><span class="' + (/^(fixed|found|stopped|cancelled|remote)$/.test(e.kind) ? 'x' : '') + '">' + esc(eventText(e)) + '</span></div>';
                }).join('') + '</div>');
            });
        },
        help: function () {
            busy = true;
            working(T('Help and report'));
            runScript('report', function (ok, out) {
                busy = false;
                message(T('Help and report'), p(esc(T('Asking for help?  Copy this report into a GitHub issue or discussion:'))) + pre(out.replace(/\s+$/, '')) + p('<span class="dim">' + esc(T('The report stays in English, so anyone can read it on GitHub.')) + '</span>')
                    + p('<span class="ok">' + esc(REPO) + '</span>'));
            });
        },
        lang: function () {
            if (I18N && I18N.next()) {
                try { window.sessionStorage.setItem('fb.focus', 'lang'); } catch (e) { /* not kept */ }
                window.location.reload();
            }
        }
    };

    // ------------------------------------------------------------------ tabs

    // Like LG-USB-2-ETH0's menu: only the open tab's rows show, LEFT and
    // RIGHT change tabs, UP from a tab's first row goes to the tab bar.
    var TABS = ['blocks', 'activity', 'more'];
    var tab = 'blocks';
    var onTabs = false;
    function tabRows(t) {
        return Array.prototype.slice.call(document.querySelectorAll('.btn[data-tab="' + t + '"]')).filter(function (b) {
            return b.style.display !== 'none';
        });
    }
    function fitRows() {
        Array.prototype.slice.call(document.querySelectorAll('.tab')).forEach(function (el) {
            el.className = 'tab' + (el.getAttribute('data-tab') === tab ? ' on' : '');
        });
        Array.prototype.slice.call(document.querySelectorAll('.btn')).forEach(function (b) {
            b.className = b.className.replace(/ ?off-tab/g, '') + (b.getAttribute('data-tab') === tab ? '' : ' off-tab');
        });
        // Longer tab names (Spanish, Russian) step the tab text down to fit
        var bar = $('tabs');
        bar.className = 'tabs';
        if (bar.scrollWidth > bar.clientWidth) { bar.className = 'tabs small'; }
    }
    function openTab(t) {
        tab = t;
        current = 0;
        fitRows();
        focusCurrent();
    }
    function stepTab(dir) {
        var i = TABS.indexOf(tab) + dir;
        if (i >= 0 && i < TABS.length) { openTab(TABS[i]); }
    }

    // ------------------------------------------------------------------ remote

    function buttons() { return tabRows(tab); }
    var current = 0;
    function focusCurrent() {
        if (overlayMode) { return; }
        var tabEl = onTabs ? document.querySelector('.tab[data-tab="' + tab + '"]') : null;
        var list = buttons();
        if (!list.length) { $('rail').className = 'rail'; if (tabEl) { tabEl.focus(); } return; }
        if (current >= list.length) { current = list.length - 1; }
        // Scroll so the focused row shows whole, starting at a row's top edge
        var box = $('rows'), first = 0, used = 0;
        for (var i = current; i >= 0; i--) {
            used += list[i].offsetHeight + 14;
            if (used - 14 > box.clientHeight) { break; }
            first = i;
        }
        box.scrollTop = first > 0 ? list[first].offsetTop - list[0].offsetTop : 0;
        // A row that doesn't fit whole is hidden, not cut off, and the rail
        // shows there's more above or below
        var top = box.scrollTop, bottom = top + box.clientHeight, above = false, below = false;
        var shown = 0, firstShown = -1;
        for (var j = 0; j < list.length; j++) {
            var rt = list[j].offsetTop - list[0].offsetTop, rb = rt + list[j].offsetHeight;
            var whole = rt >= top - 1 && rb <= bottom + 1;
            list[j].style.visibility = whole ? '' : 'hidden';
            if (whole) { shown++; if (firstShown < 0) { firstShown = j; } }
            if (!whole && rb <= top + 1) { above = true; }
            if (!whole && rt >= top) { below = true; }
        }
        var rail = $('rail'), more = above || below;
        rail.className = 'rail' + (more ? ' show' : '');
        if (more) {
            var last = list[firstShown + shown - 1];
            var h = last.offsetTop - list[0].offsetTop + last.offsetHeight - top;
            rail.style.top = (box.offsetTop + 22) + 'px';
            rail.style.height = Math.max(h - 44, 60) + 'px';
            var track = rail.clientHeight;
            $('rail-thumb').style.height = Math.max(track * shown / list.length, 24) + 'px';
            $('rail-thumb').style.top = (track * firstShown / list.length) + 'px';
            rail.children[0].className = 'rail-cap up' + (above ? ' lit' : '');
            rail.children[2].className = 'rail-cap down' + (below ? ' lit' : '');
        }
        if (tabEl) { tabEl.focus(); } else { list[current].focus({ preventScroll: true }); }
    }
    function exitApp() {
        if (window.PalmSystem && window.PalmSystem.platformBack) { window.PalmSystem.platformBack(); }
        else { window.close(); }
    }
    function isBack(k) { return k === KEY.BACK || k === KEY.ESC || k === KEY.BACKSPACE; }
    function press(btn) {
        if (btn && !busy && !overlayMode) { actions[btn.getAttribute('data-action')](); }
    }

    document.addEventListener('keydown', function (e) {
        var k = e.keyCode;
        if (overlayMode) {
            e.preventDefault();
            if (overlayMode === 'busy') { return; }
            if (overlayMode === 'pick') {
                if (k === KEY.UP || k === KEY.DOWN) { pickMove(k === KEY.UP ? -1 : 1); }
                else if (k === KEY.ENTER) { var it = pickItems[pickAt]; closeOverlay(); if (it) { it.fn(); } }
                else if (isBack(k)) { closeOverlay(); }
                return;
            }
            if (k === KEY.ENTER && overlayMode === 'confirm' && onConfirm) { var fn = onConfirm; onConfirm = null; fn(); }
            else if (k === KEY.ENTER || isBack(k)) { closeOverlay(); }
            return;
        }
        var list = buttons();
        if (onTabs) {
            if (k === KEY.LEFT) { stepTab(-1); }
            else if (k === KEY.RIGHT) { stepTab(1); }
            else if (k === KEY.DOWN || k === KEY.ENTER) { onTabs = false; current = 0; focusCurrent(); }
            else if (isBack(k)) { exitApp(); }
            e.preventDefault();
            return;
        }
        if (k === KEY.DOWN) { current = Math.min(current + 1, list.length - 1); focusCurrent(); }
        else if (k === KEY.UP && current === 0) { onTabs = true; focusCurrent(); }
        else if (k === KEY.UP) { current = Math.max(current - 1, 0); focusCurrent(); }
        else if (k === KEY.LEFT) { stepTab(-1); }
        else if (k === KEY.RIGHT) { stepTab(1); }
        else if (k === KEY.ENTER) { press(list[current]); }
        else if (isBack(k)) { exitApp(); }
        else { return; }
        e.preventDefault();
    });

    // Magic Remote pointer: hovering moves the focus, clicking acts
    Array.prototype.slice.call(document.querySelectorAll('.btn')).forEach(function (btn) {
        btn.addEventListener('mouseover', function () { if (!overlayMode) { onTabs = false; current = buttons().indexOf(btn); focusCurrent(); } });
        btn.addEventListener('click', function () { current = buttons().indexOf(btn); press(btn); });
    });
    Array.prototype.slice.call(document.querySelectorAll('.tab')).forEach(function (el) {
        el.addEventListener('click', function () { if (!overlayMode) { onTabs = true; openTab(el.getAttribute('data-tab')); } });
    });
    $('overlay').addEventListener('click', function () {
        if (overlayMode === 'confirm' && onConfirm) { var fn = onConfirm; onConfirm = null; fn(); }
        else if (overlayMode === 'message') { closeOverlay(); }
    });

    document.addEventListener('webOSRelaunch', function () { if (!busy) { refresh(); } });
    document.addEventListener('visibilitychange', function () { if (!document.hidden && !busy) { refresh(); } });
    // Check again now and then, so a change made elsewhere (over SSH) shows up
    setInterval(function () { if (!document.hidden && !busy && !overlayMode) { refresh(); } }, 30000);

    if (I18N) { I18N.translatePage(document.body); }
    $('lang-hint').textContent = I18N ? I18N.label() : 'English';
    try {
        if (window.sessionStorage.getItem('fb.focus') === 'lang') {
            window.sessionStorage.removeItem('fb.focus');
            tab = 'more';
            fitRows();
            current = buttons().indexOf(document.querySelector('[data-action="lang"]'));
        }
    } catch (e) { /* first row */ }
    // The layout is drawn for 1920x1080.  webOS scales it for the screen
    // (appinfo's resolution), but where the browser doesn't, scale it here so
    // nothing runs off a smaller screen
    function fitScreen() {
        var w = window.innerWidth || 1920, h = window.innerHeight || 1080;
        var z = Math.min(w / 1920, h / 1080);
        document.body.style.zoom = (z > 0.3 && z < 0.98) ? String(z) : '';
    }
    fitScreen();
    window.addEventListener('resize', fitScreen);
    fitRows();
    focusCurrent();
    refresh(function () {
        updateHint();
        var lp = launchParams();
        if (lp.updated && /^[0-9.]+$/.test(lp.updated)) { showUpdated(lp.updated); }
        // A newer FW Block?  Asked once each time the app opens
        if (!window.FB_DEMO_NO_UPDATE) { checkUpdate(); }
    });
}());
