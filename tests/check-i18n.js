// Every text the TV app shows is translated in each language of
// webos-app/src/i18n.js, with the same {placeholders}, and every message the
// script prints for an action comes out translated.
//
//   node tests/check-i18n.js
'use strict';
var fs = require('fs');
var path = require('path');
var vm = require('vm');

var SRC = path.join(__dirname, '../webos-app/src');
var app = fs.readFileSync(path.join(SRC, 'app.js'), 'utf8');
var html = fs.readFileSync(path.join(SRC, 'index.html'), 'utf8');
var sh = fs.readFileSync(path.join(__dirname, '../fw-block.sh'), 'utf8');

var box = { window: {}, navigator: { language: 'en-US' }, document: {} };
box.window.localStorage = { getItem: function () { return null; }, setItem: function () {} };
vm.runInNewContext(fs.readFileSync(path.join(SRC, 'i18n.js'), 'utf8'), box);
var I = box.window.FB_I18N;

function unq(s) { return s.replace(/\\'/g, "'").replace(/\\n/g, '\n'); }
var used = {};
var m;
var lit = /\bT\(\s*'((?:[^'\\]|\\.)*)'/g;
while ((m = lit.exec(app))) { used[unq(m[1])] = 1; }
used['Auto ({lang})'] = 1;
html.replace(/<script[\s\S]*?<\/script>/g, '').replace(/>([^<>]+)</g, function (all, t) {
    t = t.trim();
    if (t && /[A-Za-z]/.test(t) && !/^(OK|BACK|FW Block|fw-block status|root@lgtv:~#|github\.com\/\S+)$/.test(t)) { used[t] = 1; }
    return all;
});
var texts = Object.keys(used);
var bad = 0;

function ph(s) { return (s.match(/\{\w+\}/g) || []).sort().join(','); }
Object.keys(I.dicts).forEach(function (lang) {
    var d = I.dicts[lang];
    texts.forEach(function (t) {
        if (!Object.prototype.hasOwnProperty.call(d, t)) { console.log('missing ' + lang + ': ' + JSON.stringify(t)); bad++; }
        else if (ph(t) !== ph(d[t])) { console.log('placeholders differ ' + lang + ': ' + JSON.stringify(t)); bad++; }
    });
    Object.keys(d).forEach(function (t) { if (!used[t]) { console.log('unused ' + lang + ': ' + JSON.stringify(t)); bad++; } });
    console.log(lang + ': ' + texts.length + ' texts');
});

// Every message an action prints (say "..." in the script, outside status
// and report) matches a pattern in each language
var msgs = [];
var sre = /\bsay "((?:[^"\\]|\\.)*)"/g;
var body = sh.split('# ------------------------------------------------------------- status')[0];
while ((m = sre.exec(body))) {
    var s = m[1];
    if (/\$\(date\)/.test(s) || s === '$*') { continue; }
    s = s.replace(/\$UPD_IP/g, '156.147.69.32').replace(/\$_miss/g, 'snu.lge.com nsu.lge.com')
        .replace(/\$RS_IPS/g, '165.244.62.249 165.244.99.174').replace(/\$\{_bad\}/g, ' 156.147.69.32');
    if (s.indexOf('$3') >= 0) { msgs.push(s.replace('$3', 'update servers')); s = s.replace('$3', 'LG Remote Support servers'); }
    msgs.push(s);
}
Object.keys(I.scripts).forEach(function (lang) {
    msgs.forEach(function (s) {
        if (I.scripts[lang].every(function (p) { return !p[0].test(s); })) { console.log('script message not translated ' + lang + ': ' + JSON.stringify(s)); bad++; }
    });
});
console.log(msgs.length + ' script messages');
if (bad) { console.log(bad + ' problems'); process.exit(1); }
console.log('All translated.');
