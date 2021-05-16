-- LibreSSL/OpenSSL SHA FFI bindings for LuaJIT.

local ffi = require("ffi")
      ffi.ssl = ffi.load("ssl")
local sha = {}

ffi.cdef([[
  unsigned char *SHA1(const unsigned char *d, size_t n, unsigned char *md);
  unsigned char *SHA224(const unsigned char *d, size_t n, unsigned char *md);
  unsigned char *SHA256(const unsigned char *d, size_t n, unsigned char *md);
  unsigned char *SHA384(const unsigned char *d, size_t n, unsigned char *md);
  unsigned char *SHA512(const unsigned char *d, size_t n, unsigned char *md);
]])

local hashfunc_lut = {
  ["sha1"] = ffi.ssl.SHA1,
  ["sha224"] = ffi.ssl.SHA224,
  ["sha256"] = ffi.ssl.SHA256,
  ["sha384"] = ffi.ssl.SHA384,
  ["sha512"] = ffi.ssl.SHA512
}

local hashlen_lut = {
  ["sha1"] = 20,
  ["sha224"] = 28,
  ["sha256"] = 32,
  ["sha384"] = 48,
  ["sha512"] = 64
}

local function hex(data)
  local byte = string.byte
  local sub = string.sub
  local result = {}

  for i = 1, #data do
    result[#result + 1] = string.format("%02x", byte(sub(data, i, i)))
  end

  return table.concat(result)
end

function sha.hash(hashtype, data)
  assert(type(hashtype) == "string", "incorrect datatype for parameter 'hashtype'")
  assert(type(data) == "string", "incorrect datatype for parameter 'data'")
  local hashfunc = assert(hashfunc_lut[hashtype], "invalid hash type")
  return hex(ffi.string(hashfunc(data, #data, nil), hashlen_lut[hashtype]))
end

return sha
