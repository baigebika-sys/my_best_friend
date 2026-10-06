import ctypes as c
from pathlib import Path
import os
lib=c.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=c.c_void_p
lib.luaL_openlibs.argtypes=[c.c_void_p]
lib.luaL_loadbufferx.argtypes=[c.c_void_p,c.c_char_p,c.c_size_t,c.c_char_p,c.c_char_p]
lib.lua_pcallk.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_longlong,c.c_void_p]
lib.lua_tolstring.argtypes=[c.c_void_p,c.c_int,c.POINTER(c.c_size_t)];lib.lua_tolstring.restype=c.c_char_p
lib.lua_close.argtypes=[c.c_void_p]
def run(source,label,execute=True):
 state=lib.luaL_newstate();lib.luaL_openlibs(state)
 b=source.encode();code=lib.luaL_loadbufferx(state,b,len(b),label.encode(),None)
 if not code and execute:code=lib.lua_pcallk(state,0,-1,0,0,None)
 if code:
  err=lib.lua_tolstring(state,-1,None)
  lib.lua_close(state)
  raise AssertionError(label+': '+err.decode())
 lib.lua_close(state)
root=Path(__file__).resolve().parent.parent
os.chdir(root)
for p in Path('my_best_friend').rglob('*.lua'):run(p.read_text(),str(p),False)
print('PASS syntax: all mod Lua files (Lua 5.4 parser; DST Lua 5.1 engine not available)')
run(Path('tests/test_game_adapter.lua').read_text(),'chat integration')
run(Path('tests/test_chat_ui.lua').read_text(),'chat UI and bounded history')
