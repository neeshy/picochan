-- OpenBSD FFI bindings for LuaJIT.

local ffi = require("ffi")
local openbsd = {}

ffi.cdef[[
  int pledge(const char *promises, const char *execpromises);
  int unveil(const char *path, const char *permissions);
  char *strerror(int errnum);
]]

function openbsd.pledge(promises, execpromises)
  assert(type(promises) == "string" or promises == nil, "incorrect datatype for parameter 'promises'")
  assert(type(execpromises) == "string" or execpromises == nil, "incorrect datatype for parameter 'execpromises'")

  local retval = ffi.C.pledge(promises, execpromises)
  if retval == -1 then
    return false, ffi.string(ffi.C.strerror(ffi.errno()))
  end
  return true
end

function openbsd.unveil(path, permissions)
  assert(type(path) == "string" or path == nil, "incorrect datatype for parameter 'path'")
  assert(type(permissions) == "string" or permissions == nil, "incorrect datatype for parameter 'permissions'")

  local retval = ffi.C.unveil(path, permissions)
  if retval == -1 then
    return false, ffi.string(ffi.C.strerror(ffi.errno()))
  end
  return true
end

return openbsd
