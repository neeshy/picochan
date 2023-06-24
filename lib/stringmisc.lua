-- Miscellaneous string functions.

require("lib.mathmisc")

local ascii = {}
for i = 0, 255 do
  ascii[#ascii + 1] = string.char(i)
end
ascii = table.concat(ascii)

function string.random(length, pattern)
  length = length or 64
  pattern = pattern or "%w"
  local result = ""

  local dict = ascii:gsub("[^" .. pattern .. "]", "")
  while #result < length do
    local randidx = math.csrandom(1, #dict)
    local randbyte = dict:byte(randidx)
    result = result .. string.char(randbyte)
  end

  return result
end

function string:tokenize(delimiter, max)
  if self == nil or delimiter == "" then
    return nil
  end

  delimiter = delimiter or " "

  local result = {}
  local pos = 1
  local first, last = self:find(delimiter, pos, true)
  while first and (not max or #result < max) do
    result[#result + 1] = self:sub(pos, first - 1)
    pos = last + 1
    first, last = self:find(delimiter, pos, true)
  end
  result[#result + 1] = self:sub(pos)

  return result
end

local bs = { [0] =
  "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P",
  "Q","R","S","T","U","V","W","X","Y","Z","a","b","c","d","e","f",
  "g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v",
  "w","x","y","z","0","1","2","3","4","5","6","7","8","9","+","/",
}

local AND = bit.band
local OR = bit.bor
local RSHIFT = bit.rshift
local LSHIFT = bit.lshift

function string:base64()
  local pad = 2 - ((#self - 1) % 3)
  self = (self .. ("\0"):rep(pad)):gsub("...", function(cs)
    local a, b, c = cs:byte(1, 3)
    return bs[RSHIFT(a, 2)] .. bs[OR(LSHIFT(AND(a, 3), 4), RSHIFT(b, 4))] ..
           bs[OR(LSHIFT(AND(b, 15), 2), RSHIFT(c, 6))] .. bs[AND(c, 63)]
  end)
  return self:sub(1, #self - pad) .. ("="):rep(pad)
end
