#!/usr/local/bin/luajit
-- Picochan CGI Frontend

local status, err = pcall(require, "pico")
if not status then
  if db then
    db:close()
  end
  io.write("Status: 500 Server Error\r\n" ..
           "Content-Type: text/plain; charset=utf-8\r\n" ..
           "\r\n" ..
           err .. "\n" ..
           debug.traceback() .. "\n")
end
