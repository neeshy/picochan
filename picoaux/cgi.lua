-- Picochan-specific CGI functions

require("picoaux.stringmisc");
local brotli = require("picoaux.brotli");
local zlib = require("picoaux.zlib");
local cgi = {};

function cgi.initialize()
  cgi.outputbuf = {};
  cgi.headers = {};
end

function cgi.finalize()
  local outputbuf = table.concat(cgi.outputbuf);

  local encodings = {};
  local accept_encoding = os.getenv("HTTP_ACCEPT_ENCODING");
  if accept_encoding then
    local list = accept_encoding:gsub(" ", ""):gsub(";q=%n-\\.?%n-", ""):tokenize(",");
    for i = 1, #list do
      encodings[list[i]] = true;
    end
  end

  if encodings["br"] then
    cgi.headers["Content-Encoding"] = "br";
    outputbuf = brotli.compress(outputbuf, 2, "text");
  elseif encodings["gzip"] then
    cgi.headers["Content-Encoding"] = "gzip";
    outputbuf = zlib.compress(outputbuf, 1, 31, 9);
  elseif encodings["deflate"] then
    cgi.headers["Content-Encoding"] = "deflate";
    outputbuf = zlib.compress(outputbuf, 1, -15, 9);
  else
    cgi.headers["Content-Encoding"] = "identity";
  end

  for k, v in pairs(cgi.headers) do
    io.write(k, ": ", v, "\r\n");
  end

  io.write("\r\n");

  io.write(outputbuf);
  os.exit(0);
end

return cgi;
