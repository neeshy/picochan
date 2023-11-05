#!/usr/bin/luajit
-- Picochan CGI Frontend

xpcall(require, function(err)
  if db then db:close() end
  io.write("Status: 500 Internal Server Error\r\n" ..
           "Content-Type: text/plain; charset=utf-8\r\n" ..
           "\r\n" ..
           (err and (tostring(err) .. "\n\n") or "") ..
           debug.traceback() .. "\n")
end, "pico")
