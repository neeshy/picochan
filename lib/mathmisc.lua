-- Math extension functions

local ffi = require("ffi")

function math.csrandom(min, max)
  local random_data = math.urandom(8)
  local n = ffi.cast("uint64_t *", ffi.new("uint8_t[8]", random_data))[0]
  return tonumber((n % (max - min + 1)) + min)
end

function math.urandom(n)
  local f = assert(io.open("/dev/urandom"))
  local data = f:read(n)
  f:close()
  return data
end
