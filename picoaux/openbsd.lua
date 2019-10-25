-- OpenBSD FFI bindings for LuaJIT.

local ffi = require("ffi");
local openbsd = {};
      openbsd.bcrypt = {};

ffi.cdef[[
  uint32_t arc4random_uniform(uint32_t upper_bound);
  int crypt_newhash(const char *password, const char *pref, char *hash, size_t hashsize);
  int crypt_checkpass(const char *password, const char *hash);
  int pledge(const char *promises, const char *execpromises);
  int unveil(const char *path, const char *permissions);
  char *strerror(int errnum);
]];

function openbsd.arc4random(min, max)
  assert(type(min) == "number" or min == nil, "incorrect datatype for parameter 'min'");
  assert(type(max) == "number" or max == nil, "incorrect datatype for parameter 'max'");

  min = min or 0;
  max = (max and (max + 1) or 0xFFFFFFFF) - min;
  return ffi.C.arc4random_uniform(max) + min;
end

function openbsd.bcrypt.digest(password, bcrypt_rounds)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'");
  assert(type(bcrypt_rounds) == "number" or type(bcrypt_rounds) == "nil", "incorrect datatype for parameter 'bcrypt_rounds'");

  local _PASSWORD_LEN = 128;
  local hash = ffi.new("char[?]", _PASSWORD_LEN);
  local retval = ffi.C.crypt_newhash(password, "bcrypt," .. bcrypt_rounds or "a", hash, _PASSWORD_LEN);

  if retval == -1 then
    return nil, ffi.string(ffi.C.strerror(ffi.errno()));
  else
    return ffi.string(hash);
  end
end

function openbsd.bcrypt.verify(password, hash)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'");
  assert(type(hash) == "string" or hash == nil, "incorrect datatype for parameter 'hash'");

  local retval = ffi.C.crypt_checkpass(password, hash);

  if retval == -1 then
    return false, ffi.string(ffi.C.strerror(ffi.errno()));
  else
    return true;
  end
end

function openbsd.pledge(promises, execpromises)
  assert(type(promises) == "string" or promises == nil, "incorrect datatype for parameter 'promises'");
  assert(type(execpromises) == "string" or execpromises == nil, "incorrect datatype for parameter 'execpromises'");

  local retval = ffi.C.pledge(promises, execpromises);

  if retval == -1 then
    return false, ffi.string(ffi.C.strerror(ffi.errno()));
  else
    return true;
  end
end

function openbsd.unveil(path, permissions)
  assert(type(path) == "string" or path == nil, "incorrect datatype for parameter 'path'");
  assert(type(permissions) == "string" or permissions == nil, "incorrect datatype for parameter 'permissions'");

  local retval = ffi.C.unveil(path, permissions)

  if retval == -1 then
    return false, ffi.string(ffi.C.strerror(ffi.errno()));
  else
    return true;
  end
end

return openbsd;
