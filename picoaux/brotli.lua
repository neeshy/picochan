-- Brotli FFI bindings for LuaJIT.
-- Currently only includes compression support.

local ffi = require("ffi");
      ffi.brotlienc = ffi.load("brotlienc");

local brotli = {};

ffi.cdef[[
  int BrotliEncoderCompress(int quality, int lgwin, int mode, size_t input_size, const uint8_t *input_buffer, size_t *encoded_size, uint8_t *encoded_buffer);
  size_t BrotliEncoderMaxCompressedSize(size_t input_size);
]];

local size_t = ffi.typeof("size_t[1]");

local mode_lut = {
  ["generic"] = 0,
  ["text"] = 1,
  ["woff"] = 2
}

-- quality: from 2 to 11, higher is better but slower
function brotli.compress(data, quality, mode)
  assert(type(data) == "string", "incorrect data type for parameter 'data'");
  quality = assert(tonumber(quality or 2), "incorrect data type for parameter 'quality'");
  assert(quality >= 2, "value of parameter 'quality' must >= 2");
  mode = assert(mode_lut[mode or "generic"], "incorrect data type for parameter 'mode'");

  local bufsize = size_t();
  bufsize[0] = ffi.brotlienc.BrotliEncoderMaxCompressedSize(#data);
  local buf = ffi.new("uint8_t[?]", ffi.cast("int", bufsize[0]));
  local ret = ffi.brotlienc.BrotliEncoderCompress(quality, 22, mode, #data, data, bufsize, buf);

  if ret ~= 1 then
    error("brotli encoder returned error code", 2);
  end

  return ffi.string(buf, bufsize[0]);
end

return brotli;
