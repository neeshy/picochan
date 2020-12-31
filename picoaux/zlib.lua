-- zlib FFI bindings for LuaJIT.
-- Currently only includes compression, but could easily be extended in the
-- future if that is desired.

local ffi = require("ffi");
      ffi.z = ffi.load("z");

local zlib = {};

ffi.cdef[[
  typedef void *(*z_alloc_func)(void* opaque, unsigned items, unsigned size);
  typedef void (*z_free_func)(void* opaque, void *address );

  typedef struct z_stream_s {
    const char *next_in;
    unsigned avail_in;
    unsigned long total_in;
    char *next_out;
    unsigned avail_out;
    unsigned long total_out;
    char *msg;
    void *state;
    z_alloc_func zalloc;
    z_free_func zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
  } z_stream;

  const char *zlibVersion(void);

  int deflateInit2_(z_stream *strm, int complevel, int method, int windowbits, int memlevel, int strategy, const char *version, int strm_size);
  unsigned long deflateBound(z_stream *strm, unsigned long sourcelen);
  int deflate(z_stream *strm, int flush);
  int deflateEnd(z_stream *strm);
]];

local zlib_version = ffi.z.zlibVersion();

local zlib_stream = ffi.typeof("z_stream[1]");

local zlib_error_lut = {
  [0] = "Z_OK",
  [1] = "Z_STREAM_END",
  [2] = "Z_NEED_DICT",
  [-1] = "Z_ERRNO",
  [-2] = "Z_STREAM_ERROR",
  [-3] = "Z_DATA_ERROR",
  [-4] = "Z_MEM_ERROR",
  [-5] = "Z_BUF_ERROR",
  [-6] = "Z_VERSION_ERROR"
};

function zlib.compress(data, complevel, windowbits, memlevel)
  assert(type(data) == "string", "incorrect datatype for parameter 'data'");
  complevel = complevel and assert(tonumber(complevel), "incorrect datatype for parameter 'complevel'") or -1;
  windowbits = windowbits and assert(tonumber(windowbits), "incorrect datatype for parameter 'windowbits'") or 15;
  memlevel = memlevel and assert(tonumber(memlevel), "incorrect datatype for parameter 'memlevel'") or 8;

  local err;
  local strm = zlib_stream();
  strm[0].zalloc = nil;
  strm[0].zfree = nil;
  strm[0].opaque = nil;

  err = ffi.z.deflateInit2_(strm, complevel, 8, windowbits, memlevel, 0, zlib_version, ffi.sizeof(strm));
  if err ~= 0 then
    error(zlib_error_lut[err]);
  end

  ffi.gc(strm, ffi.z.deflateEnd);
  local bufsize = ffi.z.deflateBound(strm, #data);
  local buf = ffi.new("char[?]", bufsize);
  strm[0].next_in = data;
  strm[0].avail_in = #data;
  strm[0].next_out = buf;
  strm[0].avail_out = bufsize;

  err = ffi.z.deflate(strm, 4);
  if not (err == 0 or err == 1) then
    error(zlib_error_lut[err]);
  end

  local output = ffi.string(buf, bufsize - strm[0].avail_out);
  return output;
end

return zlib;
