-- Picochan-specific CGI functions

require("picoaux.stringmisc");
local brotli = require("picoaux.brotli");
local zlib = require("picoaux.zlib");
local cgi = {};

local function httpencodinglist(s)
  local ret = {};
  local list = string.tokenize(s:gsub(" ", ""):gsub(";q=%n-\\.?%n-", ""), ",");

  for i = 1, #list do
    ret[list[i]] = true;
  end

  return ret;
end

local function write_headers()
  for k, v in pairs(cgi.headers) do
    io.write(k, ": ", v, "\n");
  end

  io.write("\n");
end

function cgi.initialize()
  cgi.outputbuf = {};
  cgi.headers = {};
  cgi.encodings = ENV["HTTP_ACCEPT_ENCODING"] and httpencodinglist(ENV["HTTP_ACCEPT_ENCODING"]) or {};
end

function cgi.finalize()
  local outputbuf = table.concat(cgi.outputbuf);

  if cgi.encodings["br"] then
    cgi.headers["Content-Encoding"] = "br";
    outputbuf = brotli.compress(outputbuf, 2, "text");
  elseif cgi.encodings["gzip"] then
    cgi.headers["Content-Encoding"] = "gzip";
    outputbuf = zlib.compress(outputbuf, 1, 31, 9);
  elseif cgi.encodings["deflate"] then
    cgi.headers["Content-Encoding"] = "deflate";
    outputbuf = zlib.compress(outputbuf, 1, -15, 9);
  else
    cgi.headers["Content-Encoding"] = "identity";
  end

  write_headers();
  io.write(outputbuf);
  os.exit(0);
end

return cgi;
