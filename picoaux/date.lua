-- Functions which manipulate dates

local date = {}

function date.iso8601(d)
  if type(d) ~= "string" then
    return nil
  end

  -- ISO8601 extended formats
  local datetime = "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)"
  local msec = "%.%d%d%d"
  local offsets = { "(Z)$", "([+-]%d%d)$", "([+-]%d%d:%d%d)$" }
  local patterns = {}

  for i = 1, #offsets do
    patterns[#patterns + 1] = datetime .. offsets[i]
    patterns[#patterns + 1] = datetime .. msec .. offsets[i]
  end

  -- ISO8601 basic formats
  for i = 1, #patterns do
    patterns[#patterns + 1] = patterns[i]:gsub("%%%-", ""):gsub(":", "")
  end

  local year, month, day, hour, min, sec, off
  for i = 1, #patterns do
    year, month, day, hour, min, sec, off = d:match(patterns[i])
    if year then
      break
    end
  end

  if not year then
    return nil
  end

  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  hour = tonumber(hour)
  min = tonumber(min)
  sec = tonumber(sec)

  local function offset(o)
    local sign = o:sub(1, 1)
    local h = tonumber(sign .. o:sub(2, 3))
    local m = #o == 5 and tonumber(sign .. o:sub(4, 5)) or 0
    return h, m
  end

  local offh, offm
  if off == "Z" then
    offh, offm = 0, 0
  else
    offh, offm = offset(off:gsub(":", ""))
  end
  local loffh, loffm = offset(os.date("%z"))

  return os.time { year = year, month = month, day = day,
                   hour = hour - offh + loffh,
                   min = min - offm + loffm,
                   sec = sec }
end

return date
