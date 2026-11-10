#!/usr/bin/env node
// Checks CooldownCollaborator's Data.lua against each client's game data (wago.tools).
// See README.md. Usage: node check.js [forever|retail ...] [--src <addon folder>] [--refresh]
// Exit 0 clean, 1 findings, 2 error.
'use strict';

const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const HERE = __dirname;
const CACHE = path.join(HERE, 'cache');
const { clients: CLIENTS } = JSON.parse(fs.readFileSync(path.join(HERE, 'builds.json'), 'utf8'));
const TABLES = ['SpellName', 'SpellMisc', 'SpellCooldowns', 'SpellClassOptions', 'SpellDuration',
	'ItemEffect'];
const FOREVER_TABLES = ['Talent'];

const CLASS_BY_FAMILY = { 3: 'MAGE', 4: 'WARRIOR', 5: 'WARLOCK', 6: 'PRIEST', 7: 'DRUID', 8: 'ROGUE', 9: 'HUNTER',
	10: 'PALADIN', 11: 'SHAMAN', 15: 'DEATHKNIGHT', 53: 'MONK', 107: 'DEMONHUNTER', 224: 'EVOKER' };

// ---------- arguments ----------
let src = path.resolve(HERE, '..', '..');
let refresh = false;
const wanted = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
	if (argv[i] === '--src') src = path.resolve(argv[++i]);
	else if (argv[i] === '--refresh') refresh = true;
	else if (argv[i] === '-h' || argv[i] === '--help') {
		console.log('usage: node check.js [' + CLIENTS.map((c) => c.key).join('|') + ' ...] [--src <addon folder>] [--refresh]');
		process.exit(0);
	} else wanted.push(argv[i]);
}
for (const k of wanted) {
	if (!CLIENTS.some((c) => c.key === k)) {
		console.error('unknown client "' + k + '"; builds.json has: ' + CLIENTS.map((c) => c.key).join(', '));
		process.exit(2);
	}
}

// ---------- wago.tools tables ----------
async function fetchTables(build, tables) {
	const dir = path.join(CACHE, build);
	fs.mkdirSync(dir, { recursive: true });
	for (const t of tables) {
		const file = path.join(dir, t + '.csv');
		if (fs.existsSync(file) && !refresh) continue;
		const url = 'https://wago.tools/db2/' + t + '/csv?build=' + encodeURIComponent(build);
		process.stderr.write('downloading ' + t + ' (' + build + ')\n');
		const res = await fetch(url);
		if (!res.ok || !(res.headers.get('content-type') || '').includes('csv')) {
			throw new Error('wago.tools returned ' + res.status + ' for ' + url);
		}
		fs.writeFileSync(file + '.part', Buffer.from(await res.arrayBuffer()));
		fs.renameSync(file + '.part', file);
	}
	return dir;
}

// RFC 4180 rows (quoted fields may hold commas, quotes and newlines), one callback per row
function parseCSV(text, onRow) {
	const n = text.length;
	let i = text.charCodeAt(0) === 0xFEFF ? 1 : 0;
	let row = [];
	while (i < n) {
		if (text.charCodeAt(i) === 34) {
			let out = '';
			let j = i + 1;
			for (;;) {
				const q = text.indexOf('"', j);
				if (q < 0) throw new Error('unterminated quoted field');
				out += text.slice(j, q);
				if (text.charCodeAt(q + 1) === 34) {
					out += '"';
					j = q + 2;
				} else {
					j = q + 1;
					break;
				}
			}
			row.push(out);
			i = j;
		} else {
			let j = i;
			while (j < n) {
				const c = text.charCodeAt(j);
				if (c === 44 || c === 10 || c === 13) break;
				j++;
			}
			row.push(text.slice(i, j));
			i = j;
		}
		if (text.charCodeAt(i) === 44) {
			i++;
		} else {
			if (text.charCodeAt(i) === 13) i++;
			if (text.charCodeAt(i) === 10) i++;
			onRow(row);
			row = [];
		}
	}
}

function eachRow(dir, table, fn) {
	const file = path.join(dir, table + '.csv');
	if (!fs.existsSync(file)) return;
	let col = null;
	parseCSV(fs.readFileSync(file, 'utf8'), (row) => {
		if (!col) {
			col = {};
			row.forEach((h, k) => { col[h] = k; });
			return;
		}
		fn((name) => row[col[name]]);
	});
}

const int = (v) => { const x = parseInt(v, 10); return Number.isFinite(x) ? x : 0; };

function loadGame(dir, client) {
	const g = { name: new Map(), icon: new Map(), cd: new Map(), itemCd: new Map(), duration: new Map(),
		family: new Map(), talent: new Set() };
	const durMs = new Map();
	eachRow(dir, 'SpellDuration', (r) => durMs.set(int(r('ID')), int(r('Duration'))));
	eachRow(dir, 'SpellName', (r) => g.name.set(int(r('ID')), r('Name_lang')));
	// difficulty 0, else the lowest difficulty listed
	const seen = new Map();
	eachRow(dir, 'SpellMisc', (r) => {
		const id = int(r('SpellID'));
		const d = int(r('DifficultyID'));
		if (seen.has(id) && d >= seen.get(id)) return;
		seen.set(id, d);
		g.icon.set(id, int(r('SpellIconFileDataID')));
		g.duration.set(id, durMs.get(int(r('DurationIndex'))));
	});
	eachRow(dir, 'SpellCooldowns', (r) => {
		if (int(r('DifficultyID')) !== 0) return;
		g.cd.set(int(r('SpellID')), Math.max(int(r('RecoveryTime')), int(r('CategoryRecoveryTime'))));
	});
	// item-use spells: the item's own cooldown (or its shared category cooldown)
	eachRow(dir, 'ItemEffect', (r) => {
		const sid = int(r('SpellID'));
		const cd = Math.max(int(r('CoolDownMSec')), int(r('CategoryCoolDownMSec')));
		if (sid && cd > 0) g.itemCd.set(sid, Math.max(g.itemCd.get(sid) || 0, cd));
	});
	eachRow(dir, 'SpellClassOptions', (r) => g.family.set(int(r('SpellID')), int(r('SpellClassSet'))));
	if (client.isForever) {
		eachRow(dir, 'Talent', (r) => {
			for (const k of ['SpellID'].concat([0, 1, 2, 3, 4, 5, 6, 7, 8].map((n) => 'SpellRank_' + n))) {
				const sid = int(r(k));
				if (sid) g.talent.add(sid);
			}
		});
	}
	return g;
}

// ---------- the addon's lists, from the real Data.lua ----------
const HARNESS = `
CC = { isForever = HARNESS_FOREVER }
dofile(HARNESS_SRC .. "/Data.lua")
local function str(s)
	s = tostring(s):gsub("[%c\\"\\\\]", function(c) return string.format("\\\\u%04x", c:byte()) end)
	return '"' .. s .. '"'
end
local function ids(t)
	local out = {}
	for _, v in ipairs(t or {}) do out[#out + 1] = tostring(v) end
	return "[" .. table.concat(out, ",") .. "]"
end
local spells = {}
for id, d in pairs(CC.SpellData) do
	spells[#spells + 1] = '{"id":' .. id .. ',"name":' .. str(d.name) .. ',"duration":' .. tostring(d.duration)
		.. ',"icon":' .. tostring(d.icon) .. ',"class":' .. str(d.class) .. ',"talent":' .. tostring(d.talent == true)
		.. ',"ranks":' .. ids(d.ranks) .. '}'
end
local cons = {}
for id, d in pairs(CC.BuiltinConsumables) do
	cons[#cons + 1] = '{"id":' .. id .. ',"name":' .. str(d.name) .. ',"duration":' .. tostring(d.duration)
		.. ',"icon":' .. tostring(d.icon) .. ',"category":' .. str(d.category) .. '}'
end
local caps = {}
for key, c in pairs(CC.CAPABILITIES) do
	local classes = {}
	for cls, list in pairs(c.classes) do classes[#classes + 1] = str(cls) .. ":" .. ids(list) end
	caps[#caps + 1] = str(key) .. ":{" .. table.concat(classes, ",") .. "}"
end
local order = {}
for _, k in ipairs(CC.CAPABILITY_ORDER) do order[#order + 1] = str(k) end
local alias = {}
for rank, canon in pairs(CC.SpellAlias) do alias[#alias + 1] = '"' .. rank .. '":' .. canon end
HARNESS_OUT = '{"spells":[' .. table.concat(spells, ",") .. '],"consumables":[' .. table.concat(cons, ",")
	.. '],"capabilities":{' .. table.concat(caps, ",") .. '},"order":[' .. table.concat(order, ",")
	.. '],"alias":{' .. table.concat(alias, ",") .. '}}'
`;

function loadLists(client) {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);
	lua.lua_pushstring(L, to_luastring(src.replace(/\\/g, '/')));
	lua.lua_setglobal(L, to_luastring('HARNESS_SRC'));
	lua.lua_pushboolean(L, client.isForever ? 1 : 0);
	lua.lua_setglobal(L, to_luastring('HARNESS_FOREVER'));
	const code = to_luastring(HARNESS);
	if (lauxlib.luaL_loadbuffer(L, code, code.length, to_luastring('harness')) !== lua.LUA_OK ||
		lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
		throw new Error('Lua error loading ' + path.join(src, 'Data.lua') + ' (' + client.key + '): ' + lua.lua_tojsstring(L, -1));
	}
	lua.lua_getglobal(L, to_luastring('HARNESS_OUT'));
	return JSON.parse(lua.lua_tojsstring(L, -1));
}

// ---------- checks ----------
const KINDS = [
	['missing', 'spell IDs missing from the game'],
	['name', 'name mismatches'],
	['cooldown', 'cooldown mismatches'],
	['icon', 'icon mismatches'],
	['rank', 'ranks that are not the same spell'],
	['class', 'class mismatches'],
	['talent', 'talent flag mismatches'],
	['cmissing', 'consumable IDs missing from the game'],
	['cduration', 'consumable duration mismatches'],
	['cap', 'capability IDs that are not canonical spell IDs'],
];

function check(client, g, lists) {
	const r = {};
	for (const [k] of KINDS) r[k] = [];
	const relax = client.relaxed || {};
	const canon = new Map(lists.spells.map((s) => [s.id, s]));

	for (const s of lists.spells) {
		const tag = `${s.id} ${s.name}`;
		if (!g.name.has(s.id)) {
			r.missing.push(tag);
			continue;
		}
		const alias = (client.nameAliases || {})[s.id];
		if (g.name.get(s.id) !== s.name && alias !== s.name) r.name.push(`${tag}: game name "${g.name.get(s.id)}"`);
		if (relax.icons !== false && g.icon.get(s.id) !== s.icon) r.icon.push(`${tag}: list ${s.icon}, game ${g.icon.get(s.id)}`);
		const cls = CLASS_BY_FAMILY[g.family.get(s.id)];
		if (cls && cls !== s.class) r.class.push(`${tag}: list ${s.class}, game ${cls}`);
		if (client.isForever && g.talent.has(s.id) !== s.talent) {
			r.talent.push(`${tag}: list talent=${s.talent}, game ${g.talent.has(s.id) ? 'is' : 'is not'} a talent`);
		}
		// the canonical ID and every rank
		for (const rid of [s.id].concat(s.ranks)) {
			const rtag = rid === s.id ? tag : `${rid} (rank of ${tag})`;
			if (!g.name.has(rid)) {
				r.missing.push(rtag);
				continue;
			}
			if (rid !== s.id && g.name.get(rid) !== g.name.get(s.id)) {
				r.rank.push(`${rtag}: game name "${g.name.get(rid)}"`);
			}
			const ms = g.cd.has(rid) ? g.cd.get(rid) : (g.itemCd.get(rid) || 0);
			// retail: short or missing cooldowns in SpellCooldowns are set at runtime, not data
			if (ms !== s.duration * 1000 && (ms >= (relax.minCooldownMs || 0) || ms === 0 && !relax.minCooldownMs)) r.cooldown.push(`${rtag}: list ${s.duration} s, game ${ms / 1000} s`);
		}
	}
	for (const c of lists.consumables) {
		const tag = `${c.id} ${c.name}`;
		if (!g.name.has(c.id)) {
			r.cmissing.push(tag);
			continue;
		}
		const ms = g.duration.get(c.id);
		if (relax.consumableDurationIfKnown && !ms) continue;
		if (ms !== c.duration * 1000) r.cduration.push(`${tag}: list ${c.duration} s, game ${ms === undefined ? 'none' : ms / 1000} s`);
	}
	for (const key of lists.order) {
		const cap = lists.capabilities[key];
		if (!cap) {
			r.cap.push(`${key}: in the order list but not defined`);
			continue;
		}
		for (const cls of Object.keys(cap)) {
			if (cap[cls].length === 0) r.cap.push(`${key} [${cls}]: no spell IDs`);
			for (const id of cap[cls]) {
				const s = canon.get(id);
				if (!s) r.cap.push(`${key} [${cls}]: ${id} is not a canonical spell ID in the list`);
				else if (s.class !== cls) r.cap.push(`${key} [${cls}]: ${id} ${s.name} belongs to ${s.class}`);
			}
		}
	}
	return r;
}

async function main() {
	console.log('Data.lua: ' + path.join(src, 'Data.lua'));
	let total = 0;
	const summary = [];
	for (const client of CLIENTS.filter((c) => !wanted.length || wanted.includes(c.key))) {
		const dir = await fetchTables(client.build, TABLES.concat(client.isForever ? FOREVER_TABLES : []));
		const g = loadGame(dir, client);
		const lists = loadLists(client);
		const res = check(client, g, lists);
		console.log(`\n== ${client.name} (build ${client.build})`);
		console.log(`   ${lists.spells.length} spells, ${lists.consumables.length} consumables checked`);
		for (const [k, title] of KINDS) {
			console.log(`   ${title}: ${res[k].length}`);
			for (const line of res[k]) console.log('      ' + line);
			total += res[k].length;
		}
		summary.push([client.key, lists.spells.length, lists.consumables.length, KINDS.reduce((n, [k]) => n + res[k].length, 0)]);
	}
	console.log('\nclient    spells  consumables  findings');
	for (const s of summary) console.log(s[0].padEnd(10) + String(s[1]).padStart(6) + String(s[2]).padStart(13) + String(s[3]).padStart(10));
	process.exit(total ? 1 : 0);
}

main().catch((e) => {
	console.error(e.message || e);
	process.exit(2);
});
