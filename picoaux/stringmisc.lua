-- Miscellaneous string functions.

require("picoaux.mathmisc");

function string.random(length, pattern)
  local length = length or 64;
  local pattern = pattern or "%w";
  local result = "";
  local ascii = {};
  local dict = "";

  for i = 0, 255 do
    ascii[#ascii + 1] = string.char(i);
  end

  ascii = table.concat(ascii);
  dict = ascii:gsub("[^" .. pattern .. "]", "");

  while string.len(result) < length do
    local randidx = math.csrandom(1, string.len(dict));
    local randbyte = dict:byte(randidx);
    result = result .. string.char(randbyte);
  end

  return result;
end

function string.tokenize(input, delimiter)
  local result = {};
  delimiter = delimiter or " ";

  if delimiter == "" then
    return nil;
  end
  if input == nil then
    return {};
  end

  local pos = 1;
  while true do
    local first, last = input:find(delimiter, pos, true);
    if first then
      result[#result + 1] = input:sub(pos, first - 1);
      pos = last + 1;
    else
      result[#result + 1] = input:sub(pos);
      break;
    end
  end

  return result;
end

local AND = bit.band;
local OR = bit.bor;
local RSHIFT = bit.rshift;
local LSHIFT = bit.lshift;

function string.base64(s)
  local bs = { [0] =
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/',
  };

  local byte, rep = string.byte, string.rep;
  local pad = 2 - ((#s-1) % 3);
  s = (s..rep('\0', pad)):gsub("...", function(cs)
      local a, b, c = byte(cs, 1, 3);
      return bs[RSHIFT(a, 2)] .. bs[OR(LSHIFT(AND(a, 3), 4), RSHIFT(b, 4))] ..
             bs[OR(LSHIFT(AND(b, 15), 2), RSHIFT(c, 6))] .. bs[AND(c, 63)];
  end);
  return s:sub(1, #s-pad) .. rep('=', pad);
end
