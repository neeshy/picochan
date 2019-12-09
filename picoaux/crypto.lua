-- Cryptographic FFI bindings for LuaJIT.
-- On OpenBSD native bindings are used
-- On Linux libbsd is used for arc4random
-- and bcrypt is supported by lua-bcrypt

local ffi = require("ffi");
local crypto = {};
      crypto.bcrypt = {};

ffi.cdef[[
  uint32_t arc4random_uniform(uint32_t upper_bound);
]];

local interface;
if jit.os == "BSD" then
  ffi.cdef[[
    int crypt_newhash(const char *password, const char *pref, char *hash, size_t hashsize);
    int crypt_checkpass(const char *password, const char *hash);
    char *strerror(int errnum);
  ]];

  interface = ffi.C;

  function crypto.bcrypt.digest(password, bcrypt_rounds)
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

  function crypto.bcrypt.verify(password, hash)
    assert(type(password) == "string", "incorrect datatype for parameter 'password'");
    assert(type(hash) == "string" or hash == nil, "incorrect datatype for parameter 'hash'");

    local retval = ffi.C.crypt_checkpass(password, hash);

    if retval == -1 then
      return false, ffi.string(ffi.C.strerror(ffi.errno()));
    else
      return true;
    end
  end
else
  ffi.bsd = ffi.load("bsd");
  interface = ffi.bsd;

  local bcrypt = require("bcrypt");
  crypto.bcrypt.digest = bcrypt.digest;
  crypto.bcrypt.verify = bcrypt.verify;
end

function crypto.arc4random(min, max)
  assert(type(min) == "number" or min == nil, "incorrect datatype for parameter 'min'");
  assert(type(max) == "number" or max == nil, "incorrect datatype for parameter 'max'");

  min = min or 0;
  max = (max and (max + 1) or 0xFFFFFFFF) - min;
  return interface.arc4random_uniform(max) + min;
end

return crypto;
