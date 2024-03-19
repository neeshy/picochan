-- Random functions

local ffi = require("ffi")
local random = {}

function random.data(n)
  local f = assert(io.open("/dev/urandom"))
  local data = f:read(n)
  f:close()
  return data
end

function random.int(min, max)
  local random_data = random.data(8)
  local n = ffi.cast("uint64_t *", ffi.new("uint8_t[8]", random_data))[0]
  return tonumber(n % (max - min + 1)) + min
end

local ascii = {}
for i = 0, 255 do
  ascii[#ascii + 1] = string.char(i)
end
ascii = table.concat(ascii)

function random.string(length, pattern)
  length = length or 64
  pattern = pattern or "%w"
  local result = ""

  local dict = ascii:gsub("[^" .. pattern .. "]", "")
  while #result < length do
    local randidx = random.int(1, #dict)
    local randbyte = dict:byte(randidx)
    result = result .. string.char(randbyte)
  end

  return result
end

return random
