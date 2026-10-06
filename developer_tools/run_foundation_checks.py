"""Focused v0.12.1 validation; not a complete rerun of old UI/config features."""
import ctypes as c
from pathlib import Path
import os
root = Path(__file__).resolve().parent.parent
os.chdir(root)
lib=c.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=c.c_void_p
lib.luaL_openlibs.argtypes=[c.c_void_p]
lib.luaL_loadbufferx.argtypes=[c.c_void_p,c.c_char_p,c.c_size_t,c.c_char_p,c.c_char_p]
lib.lua_pcallk.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_longlong,c.c_void_p]
lib.lua_tolstring.argtypes=[c.c_void_p,c.c_int,c.POINTER(c.c_size_t)];lib.lua_tolstring.restype=c.c_char_p
lib.lua_close.argtypes=[c.c_void_p]
def run(source,label,execute=True):
    state=lib.luaL_newstate();lib.luaL_openlibs(state);data=source.encode()
    status=lib.luaL_loadbufferx(state,data,len(data),label.encode(),None)
    if not status and execute:status=lib.lua_pcallk(state,0,-1,0,0,None)
    error=lib.lua_tolstring(state,-1,None) if status else None
    lib.lua_close(state)
    if error:raise AssertionError(label+': '+error.decode())
for path in Path('my_best_friend').rglob('*.lua'):run(path.read_text(),str(path),False)
print('PASS all Lua syntax (Lua 5.4 only, not a DST engine run)',flush=True)
for name in ['test_foundation.lua','test_needs.lua','test_work_core.lua','test_work_chat.lua']:
    path=Path('tests')/name
    if path.exists():run(path.read_text(),name)
