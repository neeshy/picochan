-- Miscellaneous io functions.

function io.fileexists(path)
  local f = io.open(path, "r")

  if f ~= nil then
    f:close()
    return true
  else
    return false
  end
end

function io.readall(file, n)
  -- guarantee n bytes are read or EOF is reached
  local read
  while n > 0 do
    local r = file:read(n)
    if r then
      if read then
        read = read .. r
      else
        read = r
      end
      n = n - #r
    else
      break
    end
  end
  return read
end

function io.readuntil(file, buf, delimiter, chunksize, out)
  if delimiter == "" then
    return nil
  end

  file = file or io.input()
  buf = buf or file:read(chunksize)
  delimiter = delimiter or " "

  local pos = 1
  local first, last
  while buf do
    first, last = buf:find(delimiter, pos, true)
    if first then
      out(buf:sub(pos, first - 1))
      return buf:sub(last + 1)
    else
      -- Read in enough to determine if delmiter exists.
      -- This is required for the case where the delimiter is
      -- a multi-character string present between two chunks.
      local read = io.readall(file, #delimiter)
      if read then
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
          read = file:read(chunksize - #buf)
          if read then
            buf = buf .. read
          end
        end
      else
        out(buf:sub(pos))
        return nil
      end
    end
  end
end
