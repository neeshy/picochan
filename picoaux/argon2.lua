-- Argon2 FFI bindings for LuaJIT.

require("picoaux.stringmisc")
local ffi = require("ffi")
      ffi.argon2 = ffi.load("argon2")
local argon2 = {}

-- this is the replacement to the enum "argon2_type" in argon2.h
argon2.type_d = 0
argon2.type_i = 1
argon2.type_id = 2

-- argon2_version
argon2.version_10 = 0x10
argon2.version_13 = 0x13
argon2.version = argon2.version_13

ffi.cdef([[
  typedef int argon2_type;

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
]])

local hashtype_lut = {
  ["argon2d"] = 0,
  ["argon2i"] = 1,
  ["argon2id"] = 2
}

local errcode_lut = {
  [0] = "(0) ARGON2_OK",
  [-1] = "(-1) ARGON2_OUTPUT_PTR_NULL",
  [-2] = "(-2) ARGON2_OUTPUT_TOO_SHORT",
  [-3] = "(-3) ARGON2_OUTPUT_TOO_LONG",
  [-4] = "(-4) ARGON2_PWD_TOO_SHORT",
  [-5] = "(-5) ARGON2_PWD_TOO_LONG",
  [-6] = "(-6) ARGON2_SALT_TOO_SHORT",
  [-7] = "(-7) ARGON2_SALT_TOO_LONG",
  [-8] = "(-8) ARGON2_AD_TOO_SHORT",
  [-9] = "(-9) ARGON2_AD_TOO_LONG",
  [-10] = "(-10) ARGON2_SECRET_TOO_SHORT",
  [-11] = "(-11) ARGON2_SECRET_TOO_LONG",
  [-12] = "(-12) ARGON2_TIME_TOO_SMALL",
  [-13] = "(-13) ARGON2_TIME_TOO_LARGE",
  [-14] = "(-14) ARGON2_MEMORY_TOO_LITTLE",
  [-15] = "(-15) ARGON2_MEMORY_TOO_MUCH",
  [-16] = "(-16) ARGON2_LANES_TOO_FEW",
  [-17] = "(-17) ARGON2_LANES_TOO_MANY",
  [-18] = "(-18) ARGON2_PWD_PTR_MISMATCH",
  [-19] = "(-19) ARGON2_SALT_PTR_MISMATCH",
  [-20] = "(-20) ARGON2_SECRET_PTR_MISMATCH",
  [-21] = "(-21) ARGON2_AD_PTR_MISMATCH",
  [-22] = "(-22) ARGON2_MEMORY_ALLOCATION_ERROR",
  [-23] = "(-23) ARGON2_FREE_MEMORY_CBK_NULL",
  [-24] = "(-24) ARGON2_ALLOCATE_MEMORY_CBK_NULL",
  [-25] = "(-25) ARGON2_INCORRECT_PARAMETER",
  [-26] = "(-26) ARGON2_INCORRECT_TYPE",
  [-27] = "(-27) ARGON2_OUT_PTR_MISMATCH",
  [-28] = "(-28) ARGON2_THREADS_TOO_FEW",
  [-29] = "(-29) ARGON2_THREADS_TOO_MANY",
  [-30] = "(-30) ARGON2_MISSING_ARGS",
  [-31] = "(-31) ARGON2_ENCODING_FAIL",
  [-32] = "(-32) ARGON2_DECODING_FAIL",
  [-33] = "(-33) ARGON2_THREAD_FAIL",
  [-34] = "(-34) ARGON2_DECODING_LENGTH_FAIL",
  [-35] = "(-35) ARGON2_VERIFY_MISMATCH"
}

-- only the password parameter is mandatory, the others are optional and will have
-- sensible defaults set if they are not provided
function argon2.digest(password, argon2_type, salt, params)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'")
  assert(argon2_type == nil or hashtype_lut[argon2_type] ~= nil, "invalid value for parameter 'argon2_type'")
  assert(salt == nil or type(salt) == "string", "invalid datatype for parameter 'salt'")
  assert(params == nil or type(params) == "table", "invalid datatype for parameter 'params'")

  argon2_type = argon2_type or "argon2id"
  salt = salt or string.random(16)
  params = params or {}
  params.t_cost = params.t_cost or 16
  params.m_cost = params.m_cost or 2^16
  params.parallelism = params.parallelism or 4
  params.version = params.version or argon2.version

  local errcode, result, resultlen

  resultlen = ffi.argon2.argon2_encodedlen(params.t_cost, params.m_cost, params.parallelism,
                                           #salt, 64, hashtype_lut[argon2_type])
  result = ffi.new("char[?]", resultlen)
  errcode = ffi.argon2.argon2_hash(params.t_cost, params.m_cost, params.parallelism,
                                   password, #password, salt, #salt, nil, 64,
                                   result, resultlen, hashtype_lut[argon2_type], params.version)

  if errcode == 0 then
    return ffi.string(result, resultlen)
  else
    return nil, errcode_lut[errcode]
  end
end

function argon2.verify(password, hash, argon2_type)
  assert(type(password) == "string", "incorrect datatype for parameter 'password'")
  assert(type(hash) == "string", "incorrect datatype for parameter 'hash'")
  assert(argon2_type == nil or hashtype_lut[argon2_type] ~= nil, "invalid value for parameter 'argon2_type'")

  argon2_type = argon2_type or "argon2id"
  local errcode = ffi.argon2.argon2_verify(hash, password, #password, hashtype_lut[argon2_type])
  return (errcode == 0), errcode_lut[errcode]
end

return argon2
