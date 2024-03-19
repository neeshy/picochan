-- io extension functions

local file = getmetatable(io.stdin)

-- guarantee n bytes are read or EOF is reached
function file:readall(n)
  local read
  while n > 0 do
    local r = self:read(n)
    if not r then
      break
    end
    if read then
      read = read .. r
    else
      read = r
    end
    n = n - #r
  end
  return read
end

function file:readuntil(buf, delimiter, chunksize, out)
  if delimiter == "" then
    return nil
  end

  self = self or io.input()
  buf = buf or self:read(chunksize)
  delimiter = delimiter or " "

  local pos = 1
  local first, last
  while buf do
    first, last = buf:find(delimiter, pos, true)
    if first then
      out(buf:sub(pos, first - 1))
      return buf:sub(last + 1)
    end

    -- Read in enough to determine if delmiter exists.
    -- This is required for the case where the delimiter is
    -- a multi-character string present between two chunks.
    local read = self:readall(#delimiter)
    if not read then
      out(buf:sub(pos))
      return nil
    end

    local tmp = buf .. read
    first, last = tmp:find(delimiter, pos, true)
    if first then
      out(tmp:sub(pos, first - 1))
      return tmp:sub(last + 1)
    end

    out(buf:sub(pos))
    buf = read
    pos = 1
    if #buf < chunksize then
      read = self:read(chunksize - #buf)
      if read then
        buf = buf .. read
      end
    end
  end
end

function io.readall(file, n)
  return file:readall(n)
end

function io.readuntil(file, buf, delimiter, chunksize, out)
  return file:readuntil(buf, delimiter, chunksize, out)
end

function io.exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end
