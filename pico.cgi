#!/usr/local/bin/luajit
-- Picochan CGI Frontend

cgi = require("picoaux.cgi")

local function try(...)
  local status, err = pcall(...)
  if not status then
    cgi.headers = {["Status"] = "500 Server Error", ["Content-Type"] = "text/plain; charset=utf-8"}
    cgi.outputbuf = {err, "\r\n", debug.traceback()}
    cgi.finalize()
  end
end

try(cgi.initialize)
try(require, "pico")

cgi.finalize()
