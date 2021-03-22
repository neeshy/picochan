-- Picochan-specific CGI functions

require("picoaux.stringmisc");
local cgi = {};

function cgi.initialize()
  cgi.outputbuf = {};
  cgi.headers = {};
end

function cgi.finalize()
  for k, v in pairs(cgi.headers) do
    io.write(k, ": ", v, "\r\n");
  end

  io.write("\r\n");

  io.write(table.concat(cgi.outputbuf));
  os.exit(0);
end

return cgi;
