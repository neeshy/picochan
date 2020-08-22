-- libbsd FFI bindings for LuaJIT.

local ffi = require("ffi");
      ffi.bsd = ffi.load("bsd");
local bsd = {};

ffi.cdef[[
  uint32_t arc4random_uniform(uint32_t upper_bound);
]];

function bsd.arc4random(min, max)
  assert(type(min) == "number" or min == nil, "incorrect datatype for parameter 'min'");
  assert(type(max) == "number" or max == nil, "incorrect datatype for parameter 'max'");

  min = min or 0;
  max = (max and (max + 1) or 0xFFFFFFFF) - min;
  return ffi.bsd.arc4random_uniform(max) + min;
end

return bsd;
