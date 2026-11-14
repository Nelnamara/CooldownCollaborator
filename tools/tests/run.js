// usage: node run.js <src dir> <toc number> <harness.lua> [toc file] [extra arg]
// Copied from cdtl3-dev's tools/tests/run.js. fengari comes from cdtl3-dev's
// tools/spell-list-check/node_modules (a sibling checkout), or FENGARI_DIR.
const path = require('path');
const fs = require('fs');
const VM = process.env.FENGARI_DIR ||
  path.join(__dirname, '..', '..', '..', 'cdtl3-dev', 'tools', 'spell-list-check', 'node_modules', 'fengari');
const { lua, lauxlib, lualib, to_luastring } = require(VM);
const [, , srcDir, toc, harness, tocFile, extra] = process.argv;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const setS = (k, v) => { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setglobal(L, to_luastring(k)); };
setS('HARNESS_SRC', srcDir.replace(/\\/g, '/'));
setS('HARNESS_DIR', path.dirname(path.resolve(harness)).replace(/\\/g, '/'));
setS('HARNESS_TOCFILE', tocFile || '');
setS('HARNESS_ARG', extra || '');
lua.lua_pushinteger(L, parseInt(toc, 10));
lua.lua_setglobal(L, to_luastring('HARNESS_TOC'));
lua.lua_pushjsfunction(L, (L) => {
  const p = lua.lua_tojsstring(L, 1);
  if (!fs.existsSync(p)) { lua.lua_pushnil(L); return 1; }
  lua.lua_pushstring(L, new Uint8Array(fs.readFileSync(p)));
  return 1;
});
lua.lua_setglobal(L, to_luastring('HARNESS_READ'));

const code = fs.readFileSync(harness);
if (lauxlib.luaL_loadbuffer(L, code, null, to_luastring('@harness/' + path.basename(harness))) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.log('LUA ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
