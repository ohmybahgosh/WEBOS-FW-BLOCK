// FW Block: tries LG's update path the way the updater would, for
// "fw-block.sh test".  Prints one line per name or address:
//
//   node probe.js lookup NAME...      NAME sink | fail | open ADDRESS
//   node probe.js connect HOST:PORT... HOST:PORT open | blocked,
//                                      plus "control open|blocked" (GitHub,
//                                      to tell a block from no network)
//
// Nothing is sent: a connection that opens is closed right away.  Runs on
// the TV's own Node.js (v16), ES5 style like update.js.
//
// FB_PROBE_SIM (the tests only) stands in for the network: "name=result,..."
// and FB_PROBE_HOSTS, a hosts file the lookups read instead.
'use strict';
var dns = require('dns');
var net = require('net');
var fs = require('fs');

var SINK = /^(0\.0\.0\.0|::|::1|127\.\d+\.\d+\.\d+)$/;
var CONTROL = 'github.com:443';
var TIMEOUT = 4000;

var sim = null;
if (process.env.FB_PROBE_SIM !== undefined) {
    sim = {};
    process.env.FB_PROBE_SIM.split(',').forEach(function (kv) {
        var i = kv.indexOf('=');
        if (i > 0) { sim[kv.slice(0, i)] = kv.slice(i + 1); }
    });
}

function simLookup(name, cb) {
    if (sim[name]) { cb(sim[name]); return; }
    var file = process.env.FB_PROBE_HOSTS, found = null;
    try {
        fs.readFileSync(file, 'utf8').split('\n').forEach(function (l) {
            var f = l.replace(/#.*/, '').trim().split(/\s+/);
            if (f.length > 1 && f.slice(1).indexOf(name) >= 0 && found === null) { found = f[0]; }
        });
    } catch (e) { /* no file */ }
    cb(found === null ? 'open 203.0.113.9' : (SINK.test(found) ? 'sink' : 'open ' + found));
}

function lookup(name, cb) {
    if (sim) { simLookup(name, cb); return; }
    dns.lookup(name, { all: true }, function (err, addrs) {
        if (err || !addrs || !addrs.length) { cb('fail'); return; }
        var open = addrs.filter(function (a) { return !SINK.test(a.address); });
        cb(open.length ? 'open ' + open[0].address : 'sink');
    });
}

function connect(target, cb) {
    if (sim) { cb(sim[target] || 'blocked'); return; }
    var i = target.lastIndexOf(':'), done = false;
    var sock = net.connect({ host: target.slice(0, i), port: +target.slice(i + 1) });
    function end(r) {
        if (done) { return; }
        done = true;
        sock.destroy();
        cb(r);
    }
    sock.setTimeout(TIMEOUT, function () { end('blocked'); });
    sock.on('connect', function () { end('open'); });
    sock.on('error', function () { end('blocked'); });
}

function all(list, fn, done) {
    var out = new Array(list.length), left = list.length;
    if (!left) { done(out); return; }
    list.forEach(function (x, i) {
        fn(x, function (r) { out[i] = x + ' ' + r; if (--left === 0) { done(out); } });
    });
}

var mode = process.argv[2], args = process.argv.slice(3);
function print(lines) { process.stdout.write(lines.join('\n') + '\n'); }
if (mode === 'lookup') {
    all(args, lookup, print);
} else if (mode === 'connect') {
    all(args.concat([CONTROL]), connect, function (lines) {
        lines[lines.length - 1] = lines[lines.length - 1].replace(CONTROL, 'control');
        print(lines);
    });
} else {
    process.stderr.write('Usage: node probe.js lookup NAME... | connect HOST:PORT...\n');
    process.exit(2);
}
