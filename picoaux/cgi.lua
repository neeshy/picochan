-- Picochan-specific CGI functions

require("picoaux.stringmisc")
require("picoaux.iomisc")
local cgi = {}
      cgi.headers = {}
      cgi.outputbuf = {}
      cgi.GET = {}
      cgi.POST = {}
      cgi.FILE = {}
      cgi.COOKIE = {}

local maxinput = 268435456
local chunksize = 131072

local function emptyinput()
  while io.read(chunksize) do end
end

local function unescape(s)
  local A = ("A"):byte()
  local zero = ("0"):byte()
  return s:gsub("%%(%x%x)", function(x)
    local digit = 0
    for i = 1, 2 do
      local xb = x:byte(i, i + 1)
      if xb >= A then
        digit = digit + xb - A + 10
      else
        digit = digit + xb - zero
      end
    end
    return string.char(digit)
  end)
end

local function parsequery(s)
  -- Convert pluses to spaces, and split on both & and 
  local query = s:gsub("%+", " "):gsub(";", "&"):tokenize("&")
  local ret = {}
  for i = 1, #query do
    local kv = query[i]:tokenize("=", 1)
    if #kv == 2 then
      kv[1] = unescape(kv[1])
      kv[2] = unescape(kv[2])
      ret[kv[1]] = kv[2]
    end
  end
  return ret
end

local function parseform(boundary, maxread)
  local post = {}
  local file = {}
  local bytesread = 0
  local lineboundary = "\r\n" .. boundary

  local function checklength()
    if bytesread > maxread then
      emptyinput()
      error("sent data length exceeds allowed upload limit")
    end
  end

  local function discard(s)
    bytesread = bytesread + #s
    checklength()
  end

  local function collect(t)
    return function(s)
      bytesread = bytesread + #s
      checklength()
      t[#t + 1] = s
    end
  end

  local function output(f)
    return function(s)
      bytesread = bytesread + #s
      checklength()
      f:write(s)
    end
  end

  local buf
  local function readandcheck(delimiter, func)
    buf = io.readuntil(io.input(), buf, delimiter, chunksize, func)
    if buf then
      bytesread = bytesread + #delimiter
      checklength()
    end
  end

  readandcheck(boundary, discard)
  while buf do
    local headers = {}
    readandcheck("\r\n\r\n", collect(headers))
    if not buf then break end
    headers = table.concat(headers):tokenize("\r\n")
    if headers[1] == "--" then break end
    local disposition = {}
    for i = 2, #headers do -- skip first, will always be empty string
      local kv = headers[i]:tokenize(":", 1)
      if #kv == 2 and kv[1]:lower() == "content-disposition" then
        for k, v in kv[2]:gmatch(";%s*([^%s=]+)=\"(.-)\"") do
          disposition[k] = v
        end
        break
      end
    end
    local name = disposition["name"]
    if name then
      local filename = disposition["filename"]
      if filename then
        local tmpfile = io.tmpfile()
        readandcheck(lineboundary, output(tmpfile))
        if assert(tmpfile:seek("end")) ~= 0 then
          assert(tmpfile:seek("set"))
          file[name] = {["filename"] = filename, ["file"] = tmpfile}
        end
      else
        local value = {}
        readandcheck(lineboundary, collect(value))
        post[name] = table.concat(value)
      end
    else
      readandcheck(lineboundary, discard)
    end
  end
  return post, file
end

function cgi.initialize()
  local cookie = os.getenv("HTTP_COOKIE")
  if cookie then
    local cookies = cookie:tokenize(";")
    for i = 1, #cookies do
      local kv = cookies[i]:gsub("^ +", ""):tokenize("=", 1)
      if #kv == 2 then
        cgi.COOKIE[kv[1]] = kv[2]
      end
    end
  end

  local method = os.getenv("REQUEST_METHOD")
  if method then
    if method == "GET" or method == "DELETE" then
      local query = os.getenv("QUERY_STRING")
      if query then
        cgi.GET = parsequery(query)
      end
    elseif method == "POST" or method == "PUT" then
      local maxread = maxinput

      local content_length = tonumber(os.getenv("CONTENT_LENGTH"))
      if content_length then
        if content_length > maxinput then
          emptyinput()
          error("content length exceeds allowed upload limit")
        end
        maxread = content_length
      end

      local content_type = os.getenv("CONTENT_TYPE")
      if content_type then
        if content_type:sub(1, 19) == "multipart/form-data" then
          local start, stop = content_type:find("boundary=", 20, true)
          if not start then
            emptyinput()
            error("boundary parameter not specified")
          end
          local boundary = content_type:sub(stop + 1)
          if #boundary == 0 then
            emptyinput()
            error("boundary paramter may not be emtpy")
          end
          cgi.POST, cgi.FILE = parseform("--" .. boundary, maxread)
        elseif content_type:sub(1, 33) == "application/x-www-form-urlencoded" then
          local query = io.read(chunksize) -- maximum for query strings
          if io.read(0) then
            emptyinput()
            error("sent data length exceeds allowed query length")
          end
          cgi.POST = parsequery(query)
        else -- some other blob
          emptyinput()
          error("request content type not supported")
        end
      end
    end
  end
end

function cgi.finalize()
  for k, v in pairs(cgi.headers) do
    io.write(k, ": ", v, "\r\n")
  end

  io.write("\r\n")

  io.write(table.concat(cgi.outputbuf))
  os.exit(0)
end

return cgi
