-- Argon2 FFI bindings

local random = require("lib.random")
local ffi = require("ffi")
      ffi.argon2 = ffi.load("argon2")
local argon2 = {}

ffi.cdef[[
  typedef enum Argon2_type {
    Argon2_d = 0,
    Argon2_i = 1,
    Argon2_id = 2
  } argon2_type;

  typedef enum Argon2_version {
    ARGON2_VERSION_10 = 0x10,
    ARGON2_VERSION_13 = 0x13,
    ARGON2_VERSION_NUMBER = ARGON2_VERSION_13
  } argon2_version;

  size_t argon2_encodedlen(uint32_t t_cost, uint32_t m_cost,
                           uint32_t parallelism, uint32_t saltlen,
                           uint32_t hashlen, argon2_type type);
  int argon2_hash(const uint32_t t_cost, const uint32_t m_cost,
                  const uint32_t parallelism, const void *pwd,
                  const size_t pwdlen, const void *salt,
                  const size_t saltlen, void *hash,
                  const size_t hashlen, char *encoded,
                  const size_t encodedlen, argon2_type type,
                  const uint32_t version);
  int argon2_verify(const char *encoded, const void *pwd,
                    const size_t pwdlen, argon2_type type);
]]

local hashtype_lut = {
  argon2d = ffi.argon2.Argon2_d,
  argon2i = ffi.argon2.Argon2_i,
  argon2id = ffi.argon2.Argon2_id,
}

-- only the password parameter is mandatory, the others are optional and will have
-- sensible defaults set if they are not provided
function argon2.digest(password, argon2_type, salt, params)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'")
  assert(argon2_type == nil or hashtype_lut[argon2_type], "invalid value for parameter 'argon2_type'")
  assert(type(salt) == "string" or salt == nil, "invalid datatype for parameter 'salt'")
  assert(type(params) == "table" or params == nil, "invalid datatype for parameter 'params'")

  params = params or {}
  assert(type(params.t_cost) == "number" or params.t_cost == nil, "invalid datatype for parameter 'params.t_cost'")
  assert(type(params.m_cost) == "number" or params.m_cost == nil, "invalid datatype for parameter 'params.m_cost'")
  assert(type(params.parallelism) == "number" or params.parallelism == nil, "invalid datatype for parameter 'params.parallelism'")
  assert(type(params.hashlen) == "number" or params.hashlen == nil, "invalid datatype for parameter 'params.hashlen'")
  assert(type(params.version) == "number" or params.version == nil, "invalid datatype for parameter 'params.version'")

  argon2_type = argon2_type and hashtype_lut[argon2_type] or ffi.argon2.Argon2_id
  salt = salt or random.string(16)
  params.t_cost = params.t_cost or 16
  params.m_cost = params.m_cost or 2^16
  params.parallelism = params.parallelism or 4
  params.hashlen = params.hashlen or 64
  params.version = params.version or ffi.argon2.ARGON2_VERSION_NUMBER

  local resultlen = ffi.argon2.argon2_encodedlen(params.t_cost, params.m_cost, params.parallelism,
                                                 #salt, params.hashlen, argon2_type)
  local result = ffi.new("char[?]", resultlen)
  local errcode = ffi.argon2.argon2_hash(params.t_cost, params.m_cost, params.parallelism,
                                         password, #password, salt, #salt, nil, params.hashlen,
                                         result, resultlen, argon2_type, params.version)
  if errcode ~= 0 then
    return nil, errcode
  end
  return ffi.string(result, resultlen)
end

function argon2.verify(password, hash, argon2_type)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'")
  assert(type(hash) == "string", "incorrect datatype for parameter 'hash'")
  assert(argon2_type == nil or hashtype_lut[argon2_type], "invalid value for parameter 'argon2_type'")

  argon2_type = argon2_type and hashtype_lut[argon2_type] or ffi.argon2.Argon2_id
  local errcode = ffi.argon2.argon2_verify(hash, password, #password, argon2_type)
  if errcode ~= 0 then
    return false, errcode
  end
  return true
end

return argon2
