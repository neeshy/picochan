#!/usr/bin/luajit
-- Picochan CGI Frontend

local status, err = pcall(require, "pico")
if not status then
  if db then db:close() end
  io.write("Status: 500 Internal Server Error\r\n" ..
           "Content-Type: text/plain; charset=utf-8\r\n" ..
           "\r\n" ..
           (err and (tostring(err) .. "\n") or "") ..
           debug.traceback() .. "\n")
end
