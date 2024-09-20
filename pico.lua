-- Picochan HTML Frontend
-- HAPAS ARE MENTALLY ILL DEGENERATES

local pico = require("picoengine")
local cgi = require("lib.cgi")

require("lib.stringext")
require("lib.ioext")

local html = {}
      html.table = {}
      html.list = {}
      html.container = {}
      html.form = {}
local views = {
  THREAD = 0,
  INDEX = 1,
  RECENT = 2,
  MOD_ACTION = 3,
}

--
-- INITIALIZATION
--

if jit.os == "BSD" then
  local openbsd = require("lib.openbsd")
  openbsd.unveil("./picochan.db", "rw")
  openbsd.unveil("./picochan.db-journal", "rwc")
  openbsd.unveil("./Media/", "rwxc")
  openbsd.unveil("./Static/", "rx")
  openbsd.unveil("/dev/urandom", "r")
  openbsd.unveil("/tmp/", "rwc")
  openbsd.unveil("/bin/sh", "x")
  openbsd.pledge("stdio rpath wpath cpath fattr flock proc exec prot_exec")
end

pico.initialize()
local sitename = pico.global.get("sitename", "Picochan")
local defaultpostname = pico.global.get("defaultpostname", "Anonymous")
local defaultboardview = pico.global.get("defaultboardview", "catalog")
local theme = pico.global.get("theme", "picochan")
local threadpagesize = pico.global.get("threadpagesize", 50)

cgi.initialize()
pico.account.register_login(cgi.COOKIE.session_key)

local function printf(...)
  cgi.outputbuf[#cgi.outputbuf + 1] = string.format(...)
end

local function thumbsize(w, h, mw, mh)
  return math.min(w, mw, math.floor(w / h * mh + 0.5)), math.min(h, mh, math.floor(h / w * mw + 0.5))
end

local function permit(board)
  return pico.account.current and (not pico.account.current.Board or pico.account.current.Board == board)
end

--
-- HTML FUNCTIONS
--

function html.begin(...)
  local title = string.format(...)
  title = title and (title .. " - ") or ""
  local theme = (cgi.COOKIE.theme and io.exists("./Static/" .. cgi.COOKIE.theme .. ".css"))
                and cgi.COOKIE.theme or theme

  printf("<!DOCTYPE html>\r\n")
  printf("<html>")
  printf(  "<head>")
  printf(    "<title>%s%s</title>", title, sitename)
  printf(    "<link rel='stylesheet' type='text/css' href='/Static/style.css' />")
  printf(    "<link rel='stylesheet' type='text/css' href='/Static/%s.css' />", theme)
  printf(    "<link rel='shortcut icon' type='image/png' href='/Static/favicon.png' />")
  printf(    "<meta charset='utf-8' />")
  printf(    "<meta name='viewport' content='width=device-width, initial-scale=1.0' />")
  printf(  "</head>")
  printf(  "<body>")
  printf(    "<nav>")
  printf(      "<a href='/' accesskey='`'>main</a> ")
  printf(      "<a href='/Mod' accesskey='1'>mod</a> ")
  printf(      "<a href='/Log' accesskey='2'>log</a> ")
  printf(      "<a href='/Boards' accesskey='3'>boards</a> ")
  printf(      "<a href='/Overboard' accesskey='4'>overboard</a> ")
  printf(      "<a href='/Theme' accesskey='5'>theme</a>")

  local boards = pico.board.list()
  for i = 1, #boards do
    local board = boards[i]
    printf(" <a href='/%s/' title='%s'>/%s/</a>",
           board.Name, html.striphtml(board.Title), board.Name)
  end

  if pico.account.current then
    printf(" <span id='logged-in-notification'>Logged in as <b>%s</b> <a href='/Mod/logout'>[Logout]</a></span>", pico.account.current.Name)
  end

  printf(      "<a href='' accesskey='r'></a>")
  printf(      "<a href='#postform' accesskey='p'></a>")
  printf(    "</nav>")
end

function html.finish()
  printf("</body></html>\r\n")
  printf("<!-- %d ms generation time -->\r\n", os.clock() * 1000)
end

function html.error(title, ...)
  cgi.outputbuf = {}
  html.brc("error", title)
  printf(...)
  html.cfinish()
  pico.finalize()
  cgi.finalize()
end

function html.redheader(...)
  printf("<h1 class='redheader'>%s</h1>", string.format(...))
end

function html.announcement()
  printf("<div id='announcement'>%s</div>", pico.global.get("announcement", ""))
end

function html.container.begin(width)
  printf("<div class='container %s'>", width or "narrow")
end

function html.container.finish()
  printf("</div>")
end

function html.container.barheader(...)
  printf("<h2 class='barheader'>%s</h2>", string.format(...))
end

function html.brc(title, redheader, width)
  html.begin(title)
  html.redheader(redheader)
  html.container.begin(width)
end

function html.cfinish()
  html.container.finish()
  html.finish()
end

function html.list.begin()
  printf("<ul>")
end

function html.list.finish()
  printf("</ul>")
end

function html.list.entry(...)
  printf("<li>%s</li>", string.format(...))
end

function html.table.begin(...)
  printf("<table><tr>")
  for i = 1, select("#", ...) do
    printf("<th>%s</th>", select(i, ...))
  end
  printf("</tr>")
end

function html.table.entry(...)
  printf("<tr>")
  for i = 1, select("#", ...) do
    printf("<td>%s</td>", select(i, ...))
  end
  printf("</tr>")
end

function html.table.finish()
  printf("</table>")
end

function html.date(timestamp, reldisplay)
  local difftime = os.time() - timestamp
  local unit, multiple
  local decimal = false
  local reltime

  if difftime >= (60 * 60 * 24 * 365) then
    unit = "year"
    multiple = difftime / (60 * 60 * 24 * 365)
    decimal = true
  elseif difftime >= (60 * 60 * 24 * 30) then
    unit = "month"
    multiple = difftime / (60 * 60 * 24 * 30)
    decimal = true
  elseif difftime >= (60 * 60 * 24 * 7) then
    unit = "week"
    multiple = difftime / (60 * 60 * 24 * 7)
  elseif difftime >= (60 * 60 * 24) then
    unit = "day"
    multiple = difftime / (60 * 60 * 24)
  elseif difftime >= (60 * 60) then
    unit = "hour"
    multiple = difftime / (60 * 60)
  elseif difftime >= (60) then
    unit = "minute"
    multiple = difftime / (60)
  else
    unit = "second"
    multiple = difftime
  end

  if decimal then
    reltime = ("%.1f %s%s ago"):format(multiple, unit, multiple == 1 and "" or "s")
  else
    multiple = math.floor(multiple)
    reltime = ("%d %s%s ago"):format(multiple, unit, multiple == 1 and "" or "s")
  end

  return ("<time datetime='%s' title='%s'>%s</time>"):format(
    os.date("!%F %T", timestamp),
    reldisplay and os.date("!%F %T %Z %z", timestamp) or reltime,
    reldisplay and reltime or os.date("!%F %T", timestamp))
end

function html.striphtml(s)
  s = tostring(s)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub("'", "&#39;")
    :gsub("\"", "&quot;")
  return s
end

function html.unstriphtml(s)
  s = tostring(s)
    :gsub("&quot;", "\"")
    :gsub("&#39;", "'")
    :gsub("&gt;", ">")
    :gsub("&lt;", "<")
    :gsub("&amp;", "&")
  return s
end

function html.picofmt(post_tbl)
  local email = post_tbl.Email
  if email and (email == "nofo" or email:match("^nofo ") or email:match(" nofo$") or email:match(" nofo ")) then
    local s = html.striphtml(post_tbl.Comment)
      :gsub("[\1-\8\11-\31\127]", "")
      :gsub("^\n+", "")
      :gsub("%s+$", "")
      :gsub("\n", "<br />")
    return s
  end

  local function handle_refs(number, append)
    number = tonumber(number)
    local ref_post_tbl = pico.post.tbl(post_tbl.Board, number, true)

    if ref_post_tbl then
      return ("<a href='/%s/%d#%d'>\2\2%d</a>%s"):format(
        ref_post_tbl.Board, ref_post_tbl.Parent or number, number, number, append)
    else
      return ("<s><a>\2\2%d</a></s>%s"):format(number, append)
    end
  end

  local function handle_xbrefs(board, number, append)
    if number == "" then
      return ("<a href='/%s/'>\2\2\2/%s/</a>%s"):format(board, board, append)
    else
      number = tonumber(number)
    end

    local ref_post_tbl = pico.post.tbl(board, number, true)

    if ref_post_tbl then
      return ("<a href='/%s/%d#%d'>\2\2\2/%s/%d</a>%s"):format(
        board, ref_post_tbl.Parent or number, number, board, number, append)
    else
      return ("<s><a>\2\2\2/%s/%d</a></s>%s"):format(board, number, append)
    end
  end

  local function handle_url(prev, url)
    local balance_tbl = {
      ["("] = ")",
      ["\1"] = "\2",
      ["{"] = "}",
      ["["] = "]",
      ["\3"] = "\3",
      ["\4"] = "\4",
    }
    local balance = balance_tbl[prev]
    local append = ""
    if balance then
      local first, second = (prev .. url):match("^(%b" .. prev .. balance .. ")(.-)$")
      if first then
        url = first:sub(2, -2)
        append = balance .. second
      end
    else
      local last = url:match("[!,%.:;%?]$")
      if last then
        url = url:sub(1, -2)
        append = last
      end
    end
    return ("%s<a href='%s'>%s</a>%s"):format(prev, url, url, append)
  end

  local blocks = {}
  local iblocks = {}

  local function handle_code(b, c, t, e)
    return function(block)
      b[#b + 1] = t .. block .. e
      return c
    end
  end

  local function insert_escaped(t)
    return function()
      if #t > 0 then
        return table.remove(t, 1)
      end
      return ""
    end
  end

  local punct = "!\4#%$%%&\3%(%)%*%+,%-%./:;\1=\2%?@%[\\%]%^_`{|}~"

  local s = ("\n" .. post_tbl.Comment .. "\n")
    :gsub("[\1-\8\11-\31\127]", "")

    :gsub("&", "&amp;")
    :gsub("<", "\1")
    :gsub(">", "\2")
    :gsub("'", "\3")
    :gsub("\"", "\4")

    :gsub("```\n*(.-)\n*```", handle_code(blocks, "\5", "<code>", "</code>"))
    :gsub("([^\n])\5", "%1\n\5")
    :gsub("\5([^\n])", "\5\n%1")
    :gsub("`([^\n]-)`", handle_code(iblocks, "\6", "<span class='code'>", "</span>"))

    :gsub("\2\2\2/([%l%d]+)/(%d-)([%s" .. punct .. "])", handle_xbrefs)
    :gsub("\2\2(%d+)([%s" .. punct .. "])", handle_refs)

    :gsub("\3\3\3([^\n]-)\3\3\3", "<b>%1</b>")
    :gsub("\3\3([^\n]-)\3\3", "<i>%1</i>")
    :gsub("~~([^\n]-)~~", "<s>%1</s>")
    :gsub("__([^\n]-)__", "<u>%1</u>")
    :gsub("==([^\n]-)==", "<span class='redtext'>%1</span>")
    :gsub("%*%*([^\n]-)%*%*", "<span class='spoiler'>%1</span>")
    :gsub("%(%(%([^\n]-%)%)%)", "<span class='kiketext'>%1</span>")
    :gsub("\n(\2[^\n]*)", "\n<span class='greentext'>%1</span>")
    :gsub("\n(\1[^\n]*)", "\n<span class='pinktext'>%1</span>")

    :gsub("(.)(https?://[%w" .. punct .. "]+)", handle_url)

    :gsub("\6", insert_escaped(iblocks))
    :gsub("\5", insert_escaped(blocks))

    :gsub("\4", "&quot;")
    :gsub("\3", "&#39;")
    :gsub("\2", "&gt;")
    :gsub("\1", "&lt;")

    :gsub("^\n+", "")
    :gsub("%s+$", "")
    :gsub("\n", "<br />")

  return s
end

function html.threadflags(post_tbl)
  printf("%s%s%s%s",
         post_tbl.Sticky   == 1 and " <a title='Sticky'>&#x1f4cc;</a>"  or "",
         post_tbl.Lock     == 1 and " <a title='Lock'>&#x1f512;</a>"    or "",
         post_tbl.Autosage == 1 and " <a title='Autosage'>&#x2693;</a>" or "",
         post_tbl.Cycle    == 1 and " <a title='Cycle'>&#x1f503;</a>"   or "")
end

function html.renderpostfiles(post_tbl, unprivileged)
  local function formatfilesize(size)
    if size > (1024 * 1024) then
      return ("%.2f MiB"):format(size / 1024 / 1024)
    elseif size > 1024 then
      return ("%.2f KiB"):format(size / 1024)
    else
      return ("%d B"):format(size)
    end
  end

  local board = post_tbl.Board
  local number = post_tbl.Number
  local file_tbl = post_tbl.Files

  for i = 1, #file_tbl do
    local file = file_tbl[i]
    local filename = file.Name
    local downloadname = file.DownloadName
    local spoiler = file.Spoiler == 1
    local extension = pico.file.extension(filename)
    local class = pico.file.class(extension)

    printf("<div class='post-attachment%s'>", #file_tbl == 1 and "-single" or "")
    printf("<div class='post-attachment-info'>")
    printf("<a href='/Media/%s' title='Open file in new tab' target='_blank'>%s</a><br />%s%s",
           filename, html.striphtml(downloadname),
           formatfilesize(file.Size), file.Width and (" " .. file.Width .. "x" .. file.Height) or "")
    printf(" <a href='/Media/%s' title='Download file' download='%s'>(dl)</a>", filename, html.striphtml(downloadname))

    if not unprivileged and permit(board) then
      printf(" <a href='/Mod/post/unlink/%s/%d/%s' title='Unlink File'>[U]</a>", board, number, filename)
      printf("<a href='/Mod/post/spoiler/%s/%d/%s' title='Spoiler File'>[S]</a>", board, number, filename)

      if not pico.account.current.Board then
        printf("<a href='/Mod/file/delete/%s' title='Delete File'>[D]</a>", filename)
      end
    end

    printf("</div>")

    if class == "image" and extension ~= "svg" then
      printf("<label>")
      printf("<input class='invisible' type='checkbox' />", board, number, i)
      if spoiler then
        printf("<img class='post-thumbnail' src='/Static/spoiler.png' width='100' height='70' alt='[SPL]' />")
      else
        printf("<img class='post-thumbnail' src='/Media/thumb/%s' width='%d' height='%d' alt='[THUMB]' />",
               filename, thumbsize(file.Width or 0, file.Height or 0, 200, 200))
      end
      printf("<img class='post-file' src='/Media/%s' alt='[IMG]' loading='lazy' />", filename)
      printf("</label>")
    elseif spoiler then
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Static/spoiler.png' width='100' height='70' alt='[SPL]' /></a>", filename)
    elseif extension == "svg" then
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Media/thumb/%s' alt='[SVG]' /></a>", filename, filename)
    elseif extension == "pdf" or extension == "ps" then
      local width, height = thumbsize(file.Width or 200, file.Height or 200, 200, 200)
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Media/thumb/%s' width='%d' height='%d' alt='[%s]' /></a>",
             filename, filename, width, height, extension:upper())
    elseif extension == "epub" then
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Static/epub.png' width='100' height='70' alt='[EPUB]' /></a>", filename)
    elseif extension == "txt" then
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Static/txt.png' width='100' height='70' alt='[TXT]' /></a>", filename)
    elseif class == "archive" then
      printf("<a href='/Media/%s' target='_blank'><img class='post-thumbnail' src='/Static/archive.png' width='100' height='70' alt='[ARCH]' /></a>", filename)
    elseif class == "video" or class == "audio" then
      if file.Width and file.Height then
        printf("<video class='post-file' controls loop preload='none' src='/Media/%s' poster='/Media/thumb/%s'></video>", filename, filename)
      else
        printf("<audio class='post-file' controls loop preload='none' src='/Media/%s'></audio>", filename)
      end
    end

    printf("</div>")
  end
end

function html.renderpost(post_tbl, overboard, view)
  local separate = view == views.RECENT or view == views.MOD_ACTION
  local board = post_tbl.Board
  local number = post_tbl.Number
  local parent = post_tbl.Parent

  printf("<div%s class='post-container'>", overboard and "" or (" id='%d'"):format(number))
  printf("<div class='post%s'>", (separate or parent) and "" or " thread")
  printf("<div class='post-header'>")

  if separate or (overboard and not parent) then
    printf(" <span class='post-thread-link'>")
    if parent then
      printf("<a href='/%s/%d'>/%s/%d</a>", board, parent, board, parent)
    else
      printf("<a href='/%s/'>/%s/</a>", board, board)
    end
    printf("</span> -&gt;")
  end

  if post_tbl.Subject and post_tbl.Subject ~= "" then
    printf(" <span class='post-subject'>%s</span>", html.striphtml(post_tbl.Subject))
  end

  printf(" <span class='post-name'>")
  if post_tbl.Email and post_tbl.Email ~= "" then
    printf("<a href='mailto:%s'>%s</a>",
           html.striphtml(post_tbl.Email), html.striphtml(post_tbl.Name or defaultpostname))
  else
    printf("%s", html.striphtml(post_tbl.Name or defaultpostname))
  end
  printf("</span>")

  if post_tbl.Capcode then
    local capcode

    if post_tbl.Capcode == "admin" then
      capcode = "Administrator"
    elseif post_tbl.Capcode == "bo" then
      capcode = "Board Owner (" .. post_tbl.CapcodeBoard .. ")"
    elseif post_tbl.Capcode == "gvol" then
      capcode = "Global Volunteer"
    elseif post_tbl.Capcode == "lvol" then
      capcode = "Board Volunteer (" .. post_tbl.CapcodeBoard .. ")"
    end

    printf(" <span class='post-capcode'>## %s</span>", capcode)
  end

  printf(" <span class='post-date'>%s</span>", html.date(post_tbl.Date))
  printf(" <span class='post-number'><a href='/%s/%d#%d'>No.</a><a href='/%s/%d#postform'>%d</a></span>",
         board, parent or number, number, board, parent or number, number)

  html.threadflags(post_tbl)
  if view ~= views.MOD_ACTION and permit(board) then
    if parent then
      printf(" <a href='/Mod/post/delete/%s/%d' title='Delete Post'>[D]</a>", board, number)
    else
      printf(" <a href='/Mod/post/delete/%s/%d' title='Delete Thread'>[D]</a>", board, number)
      printf("<a href='/Mod/post/move/%s/%d' title='Move Thread'>[M]</a>", board, number)
      printf("<a href='/Mod/post/merge/%s/%d' title='Merge Thread'>[R]</a>", board, number)
      printf("<a href='/Mod/post/sticky/%s/%d' title='Sticky Thread'>[S]</a>", board, number)
      printf("<a href='/Mod/post/lock/%s/%d' title='Lock Thread'>[L]</a>", board, number)
      printf("<a href='/Mod/post/autosage/%s/%d' title='Autosage Thread'>[A]</a>", board, number)
      printf("<a href='/Mod/post/cycle/%s/%d' title='Cycle Thread'>[C]</a>", board, number)
    end
  end
  if view == views.INDEX and not parent then
    printf(" <a href='/%s/%d' title='Open Thread'>[Open]</a>", board, number)
    printf(" <a href='/%s/%d/%d' title='Last %d Posts'>[Last]</a>",
           board, number, post_tbl.PageCount, threadpagesize)
  end

  local reflist = pico.post.refs(board, number)
  if #reflist > 0 then
    printf("<span class='referrer'>")
    for i = 1, #reflist do
      local ref = reflist[i]
      printf(" <a href='/%s/%d#%d'>&gt;&gt;%d</a>", board, parent or number, ref, ref)
    end
    printf("</span>")
  end

  printf("</div>")
  html.renderpostfiles(post_tbl, view == views.MOD_ACTION)
  printf("<div class='post-comment'>%s</div>", html.picofmt(post_tbl))
  printf("</div></div>")
end

function html.rendercatalog(catalog_tbl)
  printf("<div class='catalog-container'>")

  for i = 1, #catalog_tbl do
    local post_tbl = catalog_tbl[i]
    local board = post_tbl.Board
    local number = post_tbl.Number

    printf("<div class='catalog-thread'>")
    printf("<a href='/%s/%d'>", board, number)
    if post_tbl.File then
      if post_tbl.Spoiler == 1 then
        printf("<img alt='***' src='/Static/spoiler.png' width='100' height='70' />")
      else
        local extension = pico.file.extension(post_tbl.File)
        local class = pico.file.class(extension)

        if class == "image" or class == "video" or extension == "pdf" or extension == "ps" or
            (class == "audio" and post_tbl.FileWidth and post_tbl.FileHeight) then
          if post_tbl.FileWidth and post_tbl.FileHeight then
            printf("<img alt='***' src='/Media/icon/%s' width='%d' height='%d' />",
                   post_tbl.File, thumbsize(post_tbl.FileWidth, post_tbl.FileHeight, 100, 70))
          else
            printf("<img alt='***' src='/Media/icon/%s' />", post_tbl.File)
          end
        elseif class == "audio" then
          printf("<img alt='***' src='/Static/audio.png' width='100' height='70' />")
        elseif class == "archive" then
          printf("<img alt='***' src='/Static/archive.png' width='100' height='70' />")
        elseif extension == "epub" then
          printf("<img alt='***' src='/Static/epub.png' width='100' height='70' />")
        elseif extension == "txt" then
          printf("<img alt='***' src='/Static/txt.png' width='100' height=70 />")
        end
      end
    else
      printf("***")
    end
    printf("</a>")

    printf("<div class='catalog-thread-info'>")
    printf("<a href='/%s/'>/%s/</a> R:%d", board, board, post_tbl.ReplyCount)
    html.threadflags(post_tbl)
    printf("</div>")

    printf("<div class='catalog-thread-lastbumpdate'>Bump: %s</div>", html.date(post_tbl.LastBumpDate, true))
    if post_tbl.Subject and post_tbl.Subject ~= "" then
      printf("<div class='catalog-thread-subject'>%s</div>", html.striphtml(post_tbl.Subject))
    end
    printf("<div class='catalog-thread-comment'>%s</div>", html.picofmt(post_tbl))

    printf("</div>")

    printf("<hr class='invisible' />")
  end

  printf("</div>")
end

function html.renderindex(index_tbl, overboard)
  for i = 1, #index_tbl do
    local thread_tbl = index_tbl[i]
    local op_tbl = thread_tbl[1]

    html.renderpost(op_tbl, overboard, views.INDEX)
    printf("<hr class='invisible' />")

    printf("<span class='index-thread-summary'>")
    if op_tbl.RepliesOmitted > 0 then
      printf("%d %s omitted. ", op_tbl.RepliesOmitted, op_tbl.RepliesOmitted == 1 and "reply" or "replies")
    end
    printf("<a href='/%s/%d'>View full thread</a>", op_tbl.Board, op_tbl.Number)
    printf("</span>")

    for j = 2, #thread_tbl do
      printf("<hr class='invisible' />")
      html.renderpost(thread_tbl[j], overboard, views.INDEX)
    end

    if i ~= #index_tbl then
      printf("<hr />")
    end
  end
end

function html.renderrecent(recent_tbl, overboard)
  for i = 1, #recent_tbl do
    if i ~= 1 then
      printf("<hr class='invisible' />")
    end
    html.renderpost(recent_tbl[i], overboard, views.RECENT)
  end
end

function html.renderpages(prefix, page, pagecount)
  -- Always show the first, last, and five nearest pages. Only show an ellipses
  -- if there would be a discontinuity of two or greater pages on either side of
  -- the five page window.
  local start, stop
  if pagecount <= 7 then
    start = 1
    stop = pagecount
  else
    start = math.max(1, page - 2)
    stop = math.min(pagecount, page + 2)
    if start <= 3 then
      start = 1
    end
    if stop + 2 >= pagecount then
      stop = pagecount
    end
    if stop - start <= 3 then
      if start == 1 then
        stop = 5
      else -- stop == pagecount
        start = pagecount - 4
      end
    end
  end

  printf("<div class='page-switcher'>")
  if page > 1 then
    printf("<a href='%s/%d'>&lt;&lt;</a> ", prefix, page - 1)
  end
  if start > 1 then
    printf("<a href='%s/1'>[1]</a> ... ", prefix)
  end
  for i = start, stop do
    if i ~= start then
      printf(" ")
    end
    if i == page then
      printf("[%d]", i)
    else
      printf("<a href='%s/%d'>[%d]</a>", prefix, i, i)
    end
  end
  if stop < pagecount then
    printf(" ... <a href='%s/%d'>[%d]</a> ", prefix, pagecount, pagecount)
  end
  if page < pagecount then
    printf(" <a href='%s/%d'>&gt;&gt;</a>", prefix, page + 1)
  end
  printf("</div>")
end

function html.form.postform(board_tbl, parent)
  printf("<form id='postform' action='/Post' method='post' enctype='multipart/form-data'>")
  printf(  "<input name='board' value='%s' type='hidden' />", board_tbl.Name)

  if parent then
    printf("<input name='parent' value='%d' type='hidden' />", parent)
  end

  printf(  "<a href='##' accesskey='w'>[X]</a>")
  printf(  "<br class='invisible' />")
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' maxlength='64' placeholder='%s' /><br />", defaultpostname)
  printf(  "<label for='email'>Email</label><input id='email' name='email' type='text' maxlength='64' /><br />")
  printf(  "<label for='subject'>Subject</label><input id='subject' name='subject' type='text' maxlength='64' />")
  printf(  "<input type='submit' value='Post' accesskey='s' /><br />")
  printf(  "<label for='comment'>Comment</label><textarea id='comment' name='comment' rows='5' cols='35' maxlength='%d'></textarea><br />", board_tbl.PostMaxLength)

  for i = 1, board_tbl.PostMaxFiles do
    printf("<label for='file%d'>File %d</label><input id='file%d' name='file%d' type='file' />" ..
           "<label for='spoiler%d'>Spoiler</label><input id='spoiler%d' name='spoiler%d' type='checkbox' value='1' />%s",
           i, i, i, i, i, i, i, i ~= board_tbl.PostMaxFiles and "<br />" or "")
  end

  if (not parent and board_tbl.ThreadCaptcha == 1
      or parent and board_tbl.PostCaptcha == 1)
      and not permit(board_tbl.Name) then
    local captchaid, captcha = pico.captcha.create()
    printf("<input name='captchaid' value='%s' type='hidden' />", captchaid)
    printf("<br /><label for='captcha'>Captcha</label><input id='captcha' name='captcha' type='text' pattern='[a-zA-Z]{6}' maxlength='6' required /><br />")
    printf("<img src='data:image/jpeg;base64,%s' />", captcha:base64())
  end

  printf("</form>")
end

function html.form.board_selection(default)
  local boards = pico.board.list()
  for i = 1, #boards do
    local board = boards[i]
    printf("<option value='%s'%s>/%s/ - %s</option>", board.Name, board.Name == default and " selected" or "", board.Name, board.Title)
  end
end

function html.form.account_selection(default)
  local accounts = pico.account.list()
  for i = 1, #accounts do
    local account = accounts[i]
    printf("<option value='%s'%s>%s</option>", account, account == default and " selected" or "", account)
  end
end

function html.form.theme_selection(default)
  local themes = io.popen("ls ./Static/*.css | awk -F/ '!/^\\.\\/Static\\/style\\.css/{sub(/\\.css$/, \"\"); print $3}'")
  for theme in themes:lines() do
    printf("<option value='%s'%s>%s</option>", theme, theme == default and " selected" or "", theme)
  end
end

function html.form.board_config_select()
  printf("<form method='post'>")
  printf(  "<label for='Name'>Name</label>")
  printf(  "<select id='Name' name='Name' autofocus>")
  html.form.board_selection(pico.account.current.Board)
  printf(  "</select><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")
end

function html.form.board_config(board)
  local board_tbl = pico.board.tbl(board)

  printf("<form method='post'>")
  printf(  "<input type='hidden' name='Name' value='%s' />", board)
  printf(  "<label for='Title'>Title</label><input id='Title' name='Title' type='text' value='%s' maxlength='32' required /><br />", html.striphtml(board_tbl.Title))
  printf(  "<label for='Subtitle'>Subtitle</label><input id='Subtitle' name='Subtitle' type='text' value='%s' maxlength='64' /><br />", html.striphtml(board_tbl.Subtitle or ""))
  printf(  "<label for='Lock'>Lock</label><input id='Lock' name='Lock' type='checkbox' value='1' %s/><br />", board_tbl.Lock == 1 and "checked " or "")
  printf(  "<label for='DisplayOverboard'>DisplayOverboard</label><input id='DisplayOverboard' name='DisplayOverboard' type='checkbox' value='1' %s/><br />", board_tbl.DisplayOverboard == 1 and "checked " or "")
  printf(  "<label for='PostMaxFiles'>PostMaxFiles</label><input id='PostMaxFiles' name='PostMaxFiles' type='number' value='%d' min='0' required /><br />", board_tbl.PostMaxFiles)
  printf(  "<label for='ThreadMinLength'>ThreadMinLength</label><input id='ThreadMinLength' name='ThreadMinLength' type='number' value='%d' min='0' required /><br />", board_tbl.ThreadMinLength)
  printf(  "<label for='PostMaxLength'>PostMaxLength</label><input id='PostMaxLength' name='PostMaxLength' type='number' value='%d' min='0' required /><br />", board_tbl.PostMaxLength)
  printf(  "<label for='PostMaxNewlines'>PostMaxNewlines</label><input id='PostMaxNewlines' name='PostMaxNewlines' type='number' value='%d' min='0' required /><br />", board_tbl.PostMaxNewlines)
  printf(  "<label for='PostMaxDblNewlines'>PostMaxDblNewlines</label><input id='PostMaxDblNewlines' name='PostMaxDblNewlines' type='number' value='%d' min='0' required /><br />", board_tbl.PostMaxDblNewlines)
  printf(  "<label for='TPHLimit'>TPHLimit</label><input id='TPHLimit' name='TPHLimit' type='number' value='%s' min='1' /><br />", board_tbl.TPHLimit or "")
  printf(  "<label for='PPHLimit'>PPHLimit</label><input id='PPHLimit' name='PPHLimit' type='number' value='%s' min='1' /><br />", board_tbl.PPHLimit or "")
  printf(  "<label for='ThreadCaptcha'>ThreadCaptcha</label><input id='ThreadCaptcha' name='ThreadCaptcha' type='checkbox' value='1' %s/><br />", board_tbl.ThreadCaptcha == 1 and "checked " or "")
  printf(  "<label for='PostCaptcha'>PostCaptcha</label><input id='PostCaptcha' name='PostCaptcha' type='checkbox' value='1' %s/><br />", board_tbl.PostCaptcha == 1 and "checked " or "")
  printf(  "<label for='CaptchaTriggerTPH'>CaptchaTriggerTPH</label><input id='CaptchaTriggerTPH' name='CaptchaTriggerTPH' type='number' value='%s' min='1' /><br />", board_tbl.CaptchaTriggerTPH or "")
  printf(  "<label for='CaptchaTriggerPPH'>CaptchaTriggerPPH</label><input id='CaptchaTriggerPPH' name='CaptchaTriggerPPH' type='number' value='%s' min='1' /><br />", board_tbl.CaptchaTriggerPPH or "")
  printf(  "<label for='BumpLimit'>BumpLimit</label><input id='BumpLimit' name='BumpLimit' type='number' value='%s' min='0' /><br />", board_tbl.BumpLimit or "")
  printf(  "<label for='PostLimit'>PostLimit</label><input id='PostLimit' name='PostLimit' type='number' value='%s' min='0' /><br />", board_tbl.PostLimit or "")
  printf(  "<label for='ThreadLimit'>ThreadLimit</label><input id='ThreadLimit' name='ThreadLimit' type='number' value='%s' min='0' /><br />", board_tbl.ThreadLimit or "")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Configure' />")
  printf("</form>")
end

function html.form.banner_delete_select()
  printf("<form method='post'>")
  printf(  "<label for='board'>Board</label>")
  printf(  "<select id='board' name='board' autofocus>")
  html.form.board_selection(pico.account.current.Board)
  printf(  "</select><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")
end

function html.form.banner_delete(board, banners)
  printf("<form method='post'>")
  printf(  "<input type='hidden' name='board' value='%s' />", board)
  printf(  "<label for='file'>File</label><br />")
  for i = 1, #banners do
    local banner = banners[i]
    printf("<input id='%s' name='file' type='radio' value='%s' %s/>", banner, banner, i == 1 and "checked " or "")
    printf("<label for='%s'><img src='/Media/%s' alt='%s' /></label><br />", banner, banner, banner)
  end
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required autofocus /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />")
  printf("</form>")
end

--
-- PAGE DEFINITIONS
--

cgi.headers["Content-Type"] = "text/html; charset=utf-8"
cgi.headers["Cache-Control"] = "no-cache"
cgi.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self';"
cgi.headers["Referrer-Policy"] = "no-referrer"
cgi.headers["X-Content-Type-Options"] = "nosniff"
cgi.headers["X-DNS-Prefetch-Control"] = "off"

local handlers = {}

local function account_check()
  if not pico.account.current then
    cgi.headers.Status = "303 See Other"
    cgi.headers.Location = "/Mod/login"
    pico.finalize()
    cgi.finalize()
  end
end

local function tbl_validate(tbl, ...)
  for i = 1, select("#", ...) do
    local v = tbl[select(i, ...)]
    if v == nil or v == "" then
      return false
    end
  end
  return true
end

handlers["/"] = function()
  html.begin("welcome")
  html.redheader("Welcome to %s", sitename)
  html.container.begin()
  printf("%s", pico.global.get("frontpage", ""))
  html.cfinish()
end

handlers["/Mod"] = function()
  account_check()
  html.brc("dashboard", "Moderation Dashboard")
  printf("You are logged in as <b>%s</b>. Your account type is <b>%s</b>.",
         pico.account.current.Name, pico.account.current.Type)
  html.container.barheader("Global")
  html.list.begin()
  html.list.entry("<a href='/Mod/global/announcement'>Change global announcement</a>")
  html.list.entry("<a href='/Mod/global/sitename'>Change site name</a>")
  html.list.entry("<a href='/Mod/global/frontpage'>Change front-page content</a>")
  html.list.entry("<a href='/Mod/global/theme'>Change default site theme</a>")
  html.list.entry("<a href='/Mod/global/defaultpostname'>Change default post name</a>")
  html.list.entry("<a href='/Mod/global/defaultboardview'>Change default board view</a>")
  html.list.entry("<a href='/Mod/global/threadpagesize'>Change thread page size</a>")
  html.list.entry("<a href='/Mod/global/catalogpagesize'>Change catalog page size</a>")
  html.list.entry("<a href='/Mod/global/overboardpagesize'>Change overboard catalog page size</a>")
  html.list.entry("<a href='/Mod/global/indexpagesize'>Change index page size</a>")
  html.list.entry("<a href='/Mod/global/indexwindowsize'>Change index window size</a>")
  html.list.entry("<a href='/Mod/global/recentpagesize'>Change recent posts page size</a>")
  html.list.entry("<a href='/Mod/global/logpagesize'>Change mod log page size</a>")
  html.list.entry("<a href='/Mod/global/maxfilesize'>Change the maximum file size</a>")
  html.list.finish()
  html.container.barheader("Moderator Tools")
  html.list.begin()
  html.list.entry("<a href='/Mod/tools/multidelete'>Multi-delete by range</a>")
  html.list.entry("<a href='/Mod/tools/pattdelete'>Pattern delete</a>")
  html.list.finish()
  html.container.barheader("Accounts")
  html.list.begin()
  html.list.entry("<a href='/Mod/account/create'>Create an account</a>")
  html.list.entry("<a href='/Mod/account/delete'>Delete an account</a>")
  html.list.entry("<a href='/Mod/account/config'>Configure an account</a>")
  html.list.finish()
  html.container.barheader("Boards")
  html.list.begin()
  html.list.entry("<a href='/Mod/board/create'>Create a board</a>")
  html.list.entry("<a href='/Mod/board/delete'>Delete a board</a>")
  html.list.entry("<a href='/Mod/board/config'>Configure a board</a>")
  html.list.entry("<a href='/Mod/banner/add'>Add a banner to a board</a>")
  html.list.entry("<a href='/Mod/banner/delete'>Delete a banner from a board</a>")
  html.list.finish()
  html.cfinish()
end

handlers["/Mod/login"] = function()
  if pico.account.current then
    cgi.headers.Status = "303 See Other"
    cgi.headers.Location = "/Mod"
    pico.finalize()
    cgi.finalize()
  end

  html.brc("login", "Moderator Login")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "username", "password") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end

    local session_key, errmsg = pico.account.login(cgi.POST.username, cgi.POST.password)
    if session_key then
      cgi.headers["Set-Cookie"] = "session_key=" .. session_key .. "; HttpOnly; Path=/; SameSite=Strict"
      cgi.headers.Status = "303 See Other"
      cgi.headers.Location = "/Mod"
      pico.finalize()
      cgi.finalize()
    else
      printf("Cannot log in: %s", errmsg)
    end
  end

  printf("<form method='post'>")
  printf(  "<label for='username'>Username</label><input id='username' name='username' type='text' required autofocus /><br />")
  printf(  "<label for='password'>Password</label><input id='password' name='password' type='password' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/logout"] = function()
  account_check()
  pico.account.logout(cgi.COOKIE.session_key)
  cgi.headers["Set-Cookie"] = "session_key=; HttpOnly; Path=/; Expires=Thursday, 1 Jan 1970 00:00:00 GMT; SameSite=Strict"
  cgi.headers.Status = "303 See Other"
  cgi.headers.Location = "/Overboard"
  pico.finalize()
  cgi.finalize()
end

handlers["/Mod/global/([%l%d]+)"] = function(varname)
  account_check()
  html.brc("change global configuration", "Change global configuration")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    local result, msg = pico.global.set(cgi.POST.name, cgi.POST.value ~= "" and cgi.POST.value or nil)
    printf("%s: %s", result and "Variable set" or "Cannot set variable", msg)
  end

  printf("<form method='post'>")
  printf("<input type='hidden' name='name' value='%s' />", varname)
  printf("<label for='value'>%s</label>", varname)

  if varname == "frontpage" or varname == "announcement" then
    printf("<textarea id='value' name='value' cols='40' rows='12' autofocus>%s</textarea>",
           html.striphtml(pico.global.get(varname, "")) or "")
  elseif varname == "theme" then
    printf("<select id='value' name='value' autofocus>")
    html.form.theme_selection(theme)
    printf("</select>")
  elseif varname == "defaultboardview" then
    printf("<select id='value' name='value' autofocus>")
    printf("<option value='catalog'%s>catalog</option>", defaultboardview == "catalog" and " selected" or "")
    printf("<option value='index'%s>index</option>", defaultboardview == "index" and " selected" or "")
    printf("<option value='recent'%s>recent</option>", defaultboardview == "recent" and " selected" or "")
    printf("</select>")
  else
    printf("<input id='value' name='value' value='%s' type='text' autofocus />",
           html.striphtml(pico.global.get(varname, "")) or "")
  end
  printf("<br /><label for='submit'>Submit</label><input id='submit' type='submit' value='Set' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/tools/multidelete"] = function()
  account_check()
  html.brc("multidelete", "Multidelete")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "board", "ispec", "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    printf("%s", select(2, pico.post.multidelete(cgi.POST.board, cgi.POST.ispec, cgi.POST.espec ~= "" and cgi.POST.espec or nil, cgi.POST.reason)))
  end

  printf("<form method='post'>")
  printf(  "<label for='board'>Board</label><input id='board' name='board' type='text' required autofocus /><br />")
  printf(  "<label for='ispec'>Include</label><input id='ispec' name='ispec' type='text' required /><br />")
  printf(  "<label for='espec'>Exclude</label><input id='espec' name='espec' type='text' /><br />")
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/tools/pattdelete"] = function()
  account_check()
  html.brc("pattern delete", "Pattern delete")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "pattern", "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    printf("%s", select(2, pico.post.pattdelete(cgi.POST.pattern, cgi.POST.reason)))
  end

  printf("<form method='post'>")
  printf(  "<label for='pattern'>Pattern</label><input id='pattern' name='pattern' type='text' required autofocus /><br />")
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/account/create"] = function()
  account_check()
  html.brc("create account", "Create account")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name", "password", "type") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    printf("%s", select(2, pico.account.create(cgi.POST.name, cgi.POST.password, cgi.POST.type, cgi.POST.board ~= "" and cgi.POST.board or nil)))
  end

  printf("<form method='post'>")
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />")
  printf(  "<label for='password'>Password</label><input id='password' name='password' type='password' pattern='.{6,128}' maxlength='128' required /><br />")
  printf(  "<label for='type'>Type</label>")
  printf(  "<select id='type' name='type'>")
  printf(    "<option value='admin'>Administrator</option>")
  printf(    "<option value='bo'>Board Owner</option>")
  printf(    "<option value='gvol'>Global Volunteer</option>")
  printf(    "<option value='lvol' selected>Local Volunteer</option>")
  printf(  "</select><br />")
  printf(  "<label for='board'>Board</label><input id='board' name='board' type='text' /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Create' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/account/delete"] = function()
  account_check()
  html.brc("delete account", "Delete account")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name", "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    local result, msg = pico.account.delete(cgi.POST.name, cgi.POST.reason)
    printf("%s%s", result and "" or "Cannot delete account: ", msg)
  end

  printf("<form method='post'>")
  printf(  "<label for='name'>Name</label>")
  printf(  "<select id='name' name='name' autofocus />")
  html.form.account_selection(pico.account.current.Name)
  printf(  "</select><br />")
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/account/config"] = function()
  account_check()
  html.brc("configure account", "Configure account")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name", "password") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    printf("%s", select(2, pico.account.changepass(cgi.POST.name, cgi.POST.password)))
  end

  printf("<form method='post'>")
  printf(  "<label for='name'>Account</label>")
  printf(  "<select id='name' name='name' autofocus /><br />")
  html.form.account_selection(pico.account.current.Name)
  printf(  "</select><br />")
  printf(  "<label for='password'>Password</label><input id='password' name='password' type='password' required autofocus /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Change Password' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/board/create"] = function()
  account_check()
  html.brc("create board", "Create board")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name", "title") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    local result, msg = pico.board.create(cgi.POST.name, cgi.POST.title, cgi.POST.subtitle ~= "" and cgi.POST.subtitle or nil)
    printf("%s%s", result and "" or "Cannot create board: ", msg)
  end

  printf("<form method='post'>")
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />")
  printf(  "<label for='title'>Title</label><input id='title' name='title' type='text' required /><br />")
  printf(  "<label for='subtitle'>Subtitle</label><input id='subtitle' name='subtitle' type='text' /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Create' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/board/delete"] = function()
  account_check()
  html.brc("delete board", "Delete board")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "name", "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    local result, msg = pico.board.delete(cgi.POST.name, cgi.POST.reason)
    printf("%s%s", result and "" or "Cannot delete board: ", msg)
  end

  printf("<form method='post'>")
  printf(  "<label for='name'>Name</label>")
  printf(  "<select id='name' name='name' autofocus>")
  html.form.board_selection(pico.account.current.Board)
  printf(  "</select><br />")
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/board/config"] = function()
  account_check()
  html.brc("configure board", "Configure board")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "Name") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    if pico.board.exists(cgi.POST.Name) then
      if tbl_validate(cgi.POST, "Title") then
        cgi.POST.Subtitle = cgi.POST.Subtitle ~= "" and cgi.POST.Subtitle or nil
        cgi.POST.TPHLimit = cgi.POST.TPHLimit ~= "" and cgi.POST.TPHLimit or nil
        cgi.POST.PPHLimit = cgi.POST.PPHLimit ~= "" and cgi.POST.PPHLimit or nil
        cgi.POST.CaptchaTriggerTPH = cgi.POST.CaptchaTriggerTPH ~= "" and cgi.POST.CaptchaTriggerTPH or nil
        cgi.POST.CaptchaTriggerPPH = cgi.POST.CaptchaTriggerPPH ~= "" and cgi.POST.CaptchaTriggerPPH or nil
        cgi.POST.BumpLimit = cgi.POST.BumpLimit ~= "" and cgi.POST.BumpLimit or nil
        cgi.POST.PostLimit = cgi.POST.PostLimit ~= "" and cgi.POST.PostLimit or nil
        cgi.POST.ThreadLimit = cgi.POST.ThreadLimit ~= "" and cgi.POST.ThreadLimit or nil
        local result, msg = pico.board.configure(cgi.POST)
        printf("%s%s", result and "" or "Cannot configure board: ", msg)
      end
      html.form.board_config(cgi.POST.Name)
    else
      printf("Cannot configure board: Board does not exist")
      html.form.board_config_select()
    end
  else
    html.form.board_config_select()
  end

  html.cfinish()
end

handlers["/Mod/banner/add"] = function()
  account_check()
  html.brc("add a banner", "Add a banner")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "board", "file") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    local result, msg = pico.board.banner.add(cgi.POST.board, cgi.POST.file)
    printf("%s%s", result and "" or "Cannot add banner: ", msg)
  end

  printf("<form method='post'>")
  printf(  "<label for='board'>Board</label>")
  printf(  "<select id='board' name='board' autofocus>")
  html.form.board_selection(pico.account.current.Board)
  printf(  "</select><br />")
  printf(  "<label for='file'>File</label><input id='file' name='file' type='text' required /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Add' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/banner/delete"] = function()
  account_check()
  html.brc("delete a banner", "Delete a banner")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "board") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end
    if pico.board.exists(cgi.POST.board) then
      local banners = pico.board.banner.list(cgi.POST.board)
      if #banners > 0 then
        if tbl_validate(cgi.POST, "file", "reason") then
          local result, msg = pico.board.banner.delete(cgi.POST.board, cgi.POST.file, cgi.POST.reason)
          printf("%s%s", result and "" or "Cannot delete banner: ", msg)
        end
        html.form.banner_delete(cgi.POST.board, banners)
      else
        printf("Cannot delete banners: Board contains no banners")
        html.form.banner_delete_select()
      end
    else
      printf("Cannot delete banners: Board does not exist")
      html.form.banner_delete_select()
    end
  else
    html.form.banner_delete_select()
  end

  html.cfinish()
end

handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"] = function(operation, board, number, file)
  account_check()
  html.begin("%s post", operation)
  html.redheader("Modify or Delete a Post")
  html.container.begin()

  local post_tbl = pico.post.tbl(board, number)
  if not post_tbl then
    html.error("Action failed", "Cannot find post %d on board %s", number, board)
  end

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end

    local result, msg
    if operation == "delete" then
      result, msg = pico.post.delete(board, number, cgi.POST.reason)
    elseif operation == "unlink" then
      result, msg = pico.post.unlink(board, number, file, cgi.POST.reason)
    elseif operation == "spoiler" then
      result, msg = pico.post.spoiler(board, number, file, cgi.POST.reason)
    elseif operation == "move" then
      if not tbl_validate(cgi.POST, "destination") then
        cgi.headers.Status = "400 Bad Request"
        html.error("Action failed", "Invalid request")
      end
      result, msg = pico.thread.move(board, number, cgi.POST.destination, cgi.POST.reason)
    elseif operation == "merge" then
      if not (tbl_validate(cgi.POST, "destination") and tonumber(cgi.POST.destination)) then
        cgi.headers.Status = "400 Bad Request"
        html.error("Action failed", "Invalid request")
      end
      result, msg = pico.thread.merge(board, number, tonumber(cgi.POST.destination), cgi.POST.reason)
    else
      result, msg = pico.thread.toggle(operation, board, number, cgi.POST.reason)
    end

    if not result then
      html.error("Action failed", "Backend returned error: %s", msg)
    end

    cgi.headers.Status = "303 See Other"

    if operation == "move" then
      cgi.headers.Location = "/" .. cgi.POST.destination
    elseif operation == "merge" then
      cgi.headers.Location = "/" .. board .. "/" .. cgi.POST.destination
    elseif operation == "delete" then
      cgi.headers.Location =
        post_tbl.Parent and ("/" .. board .. "/" .. post_tbl.Parent)
                         or ("/" .. board)
    else
      cgi.headers.Location =
        post_tbl.Parent and ("/" .. board .. "/" .. post_tbl.Parent)
                         or ("/" .. board .. "/" .. post_tbl.Number)
    end

    pico.finalize()
    cgi.finalize()
  end

  local thread = operation == "sticky" or
                 operation == "lock" or
                 operation == "autosage" or
                 operation == "cycle"
  local toggle = thread or operation == "spoiler"
  thread = (thread or operation == "move" or operation == "merge" or operation == "delete") and
           not post_tbl.Parent

  printf("You are about to %s%s the following %s:",
         toggle and ("toggle the <b>" .. operation .. "</b> attribute for")
                 or ("<b>" .. operation .. "</b>"),
         file and (" " .. file .. " from") or "",
         thread and "thread" or "post")
  html.renderpost(post_tbl, true, views.MOD_ACTION)

  printf("<form method='post'>")
  if operation == "move" then
    printf("<label for='destination'>Destination</label><input id='destination' name='destination' type='text' required autofocus /><br />")
    printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  elseif operation == "merge" then
    printf("<label for='destination'>Destination</label><input id='destination' name='destination' type='number' min='1' required autofocus /><br />")
    printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />")
  else
    printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required autofocus /><br />")
  end
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Mod/post/(unlink)/([%l%d]+)/(%d+)/([%l%d.]+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(spoiler)/([%l%d]+)/(%d+)/([%l%d.]+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(move)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(merge)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(sticky)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(lock)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(autosage)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]
handlers["/Mod/post/(cycle)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"]

handlers["/Mod/file/delete/([%l%d.]+)"] = function(file)
  account_check()
  html.brc("delete file", "Delete file")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "reason") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end

    local result, msg = pico.file.delete(file, cgi.POST.reason)
    if not result then
      html.error("Action failed", "Backend returned error: %s", msg)
    end

    cgi.headers.Status = "303 See Other"
    cgi.headers.Location = "/Overboard"
    pico.finalize()
    cgi.finalize()
  end

  printf("You are about to <b>delete</b> the file %s from <i>all boards</i>.", file)
  printf("<form method='post'>")
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required autofocus /><br />")
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Log"] = function(page)
  html.brc("logs", "Moderation Logs", "wide")

  page = tonumber(page) or 1
  if page <= 0 then
    cgi.headers.Status = "404 Not Found"
    html.error("Page not found", "Page number too low: %s", page)
  end

  local log_tbl, pagecount = pico.log.retrieve(page)
  if page > pagecount then
    cgi.headers.Status = "404 Not Found"
    html.error("Page not found", "Page number too high: %s", page)
  end

  if pagecount > 1 then
    html.renderpages("/Log", page, pagecount)
    printf("<hr />")
  end

  html.table.begin("Account", "Board", "Date", "Description")
  for i = 1, #log_tbl do
    local entry = log_tbl[i]
    html.table.entry(entry.Account or "<i>SYSTEM</i>",
                     not entry.Board and "<i>GLOBAL</i>" or ("<a href='/%s/'>/%s/</a>"):format(entry.Board, entry.Board),
                     html.date(entry.Date),
                     html.striphtml(entry.Description))
  end
  html.table.finish()

  if pagecount > 1 then
    printf("<hr />")
    html.renderpages("/Log", page, pagecount)
  end
  html.cfinish()
end

handlers["/Log/(%d+)"] = handlers["/Log"]

handlers["/Boards"] = function()
  html.brc("boards", "Board List", "wide")
  html.table.begin("Board", "Title", "Subtitle", "TPW (7d)", "TPD (1d)", "PPD (7d)", "PPD (1d)", "PPH (1h)", "Total Posts", "Last Activity")

  local g_tpw7d = 0
  local g_tpd1d = 0
  local g_ppd7d = 0
  local g_ppd1d = 0
  local g_pph1h = 0
  local g_total = 0
  local g_last = nil
  local board_list_tbl = pico.board.list()
  for i = 1, #board_list_tbl do
    local board_tbl = board_list_tbl[i]
    local board = board_tbl.Name
    local title = html.striphtml(board_tbl.Title)
    local subtitle = html.striphtml(board_tbl.Subtitle or "")
    local tpw7d = pico.board.stats.threadrate(board, 24 * 7, 1)
    local tpd1d = pico.board.stats.threadrate(board, 24, 1)
    local ppd7d = pico.board.stats.postrate(board, 24, 7)
    local ppd1d = pico.board.stats.postrate(board, 24, 1)
    local pph1h = pico.board.stats.postrate(board, 1, 1)
    local total = pico.board.stats.totalposts(board)
    local last = pico.board.stats.lastbumpdate(board)

    g_tpw7d = g_tpw7d + tpw7d
    g_tpd1d = g_tpd1d + tpd1d
    g_ppd7d = g_ppd7d + ppd7d
    g_ppd1d = g_ppd1d + ppd1d
    g_pph1h = g_pph1h + pph1h
    g_total = g_total + total
    if not g_last then
      g_last = last
    elseif last then
      g_last = math.max(g_last, last)
    end

    html.table.entry(("<a href='/%s/' title='%s'>/%s/</a>"):format(board, title, board),
                     title, subtitle, tpw7d, tpd1d, ppd7d, ppd1d, pph1h, total, last and html.date(last, true) or "")
  end

  html.table.entry("<i>GLOBAL</i>", "", "", g_tpw7d, g_tpd1d, g_ppd7d, g_ppd1d, g_pph1h, g_total, g_last and html.date(g_last, true) or "")
  html.table.finish()
  html.cfinish()
end

local function overboard_header()
  html.begin("overboard")
  html.redheader("%s Overboard", sitename)
  html.announcement()
  printf("<a href='/Overboard/catalog'>[Catalog]</a> ")
  printf("<a href='/Overboard/index'>[Index]</a> ")
  printf("<a href='/Overboard/recent'>[Recent]</a> ")
  printf("<a class='float-right' href=''>[Update]</a><hr />")
end

local function board_header(board_tbl)
  if not board_tbl then
    cgi.headers.Status = "404 Not Found"
    html.error("Board Not Found", "The board you specified does not exist.")
  end

  local board = board_tbl.Name

  html.begin("/%s/", board)
  local banner = pico.board.banner.get(board)
  if banner then
    printf("<img id='banner' src='/Media/%s' height='100' alt='[BANNER]' />", banner)
  end
  printf("<h1 id='boardtitle'><a href='/%s/'>/%s/</a> - %s</h1>",
         board, board, html.striphtml(board_tbl.Title))
  printf("<h2 id='boardsubtitle'>%s</h2>", html.striphtml(board_tbl.Subtitle or ""))
  html.announcement()
  if board_tbl.Lock ~= 1 or permit(board) then
    printf("<a id='new-post' href='#postform'>[Start a New Thread]</a>")
    html.form.postform(board_tbl)
  end
  printf("<a href='/%s/catalog'>[Catalog]</a> ", board)
  printf("<a href='/%s/index'>[Index]</a> ", board)
  printf("<a href='/%s/recent'>[Recent]</a> ", board)
  printf("<a class='float-right' href=''>[Update]</a><hr />")
end

local function board_view(board_func, render_func, view)
  return function(board, page)
    local overboard = board == "Overboard"
    local boardval = not overboard and board or nil

    page = tonumber(page) or 1
    if page <= 0 then
      cgi.headers.Status = "404 Not Found"
      html.error("Page not found", "Page number too low: %s", page)
    end

    local tbl, pagecount, msg = board_func(boardval, page)
    if not tbl then
      cgi.headers.Status = "404 Not Found"
      html.error("Page not found", "Cannot display %s: %s", view, msg)
    elseif page > pagecount then
      cgi.headers.Status = "404 Not Found"
      html.error("Page not found", "Page number too high: %s", page)
    end

    if overboard then
      overboard_header()
    else
      board_header(pico.board.tbl(board))
    end
    render_func(tbl, overboard)
    if pagecount > 1 then
      printf("<hr />")
      html.renderpages(("/%s/%s"):format(board, view), page, pagecount)
    end
    html.finish()
  end
end

handlers["/(Overboard)/catalog"] = board_view(pico.board.catalog, html.rendercatalog, "catalog")
handlers["/(Overboard)/catalog/(%d)"] = handlers["/(Overboard)/catalog"]
handlers["/([%l%d]+)/catalog"] = handlers["/(Overboard)/catalog"]
handlers["/([%l%d]+)/catalog/(%d)"] = handlers["/(Overboard)/catalog"]

handlers["/(Overboard)/index"] = board_view(pico.board.index, html.renderindex, "index")
handlers["/(Overboard)/index/(%d+)"] = handlers["/(Overboard)/index"]
handlers["/([%l%d]+)/index"] = handlers["/(Overboard)/index"]
handlers["/([%l%d]+)/index/(%d+)"] = handlers["/(Overboard)/index"]

handlers["/(Overboard)/recent"] = board_view(pico.board.recent, html.renderrecent, "recent")
handlers["/(Overboard)/recent/(%d+)"] = handlers["/(Overboard)/recent"]
handlers["/([%l%d]+)/recent"] = handlers["/(Overboard)/recent"]
handlers["/([%l%d]+)/recent/(%d+)"] = handlers["/(Overboard)/recent"]

if defaultboardview == "index" then
  handlers["/(Overboard)"] = handlers["/(Overboard)/index"]
  handlers["/(Overboard)/(%d+)"] = handlers["/(Overboard)/index"]
  handlers["/([%l%d]+)/?"] = handlers["/([%l%d]+)/index"]
elseif defaultboardview == "recent" then
  handlers["/(Overboard)"] = handlers["/(Overboard)/recent"]
  handlers["/(Overboard)/(%d+)"] = handlers["/(Overboard)/recent"]
  handlers["/([%l%d]+)/?"] = handlers["/([%l%d]+)/recent"]
else
  handlers["/(Overboard)"] = handlers["/(Overboard)/catalog"]
  handlers["/(Overboard)/(%d+)"] = handlers["/(Overboard)/catalog"]
  handlers["/([%l%d]+)/?"] = handlers["/([%l%d]+)/catalog"]
end

handlers["/([%l%d]+)/(%d+)"] = function(board, number, page)
  local board_tbl = pico.board.tbl(board)

  if not board_tbl then
    cgi.headers.Status = "404 Not Found"
    html.error("Board Not Found", "The board you specified does not exist.")
  end

  if page then
    page = tonumber(page)
    if page <= 0 then
      cgi.headers.Status = "404 Not Found"
      html.error("Page not found", "Page number too low: %s", page)
    end
  end

  local thread_tbl, pagecount, msg = pico.thread.tbl(board, number, page)

  if not thread_tbl then
    local post_tbl = pico.post.tbl(board, number)

    if not post_tbl then
      cgi.headers.Status = "404 Not Found"
      html.error("Thread Not Found", "Cannot display thread: %s", msg)
    end

    cgi.headers.Status = "301 Moved Permanently"
    cgi.headers.Location = ("/%s/%d#%d"):format(board, post_tbl.Parent, post_tbl.Number)
    pico.finalize()
    cgi.finalize()
  end

  if page then
    if page > pagecount then
      cgi.headers.Status = "404 Not Found"
      html.error("Page not found", "Page number too high: %s", page)
    end
  end

  local op_tbl = thread_tbl[1]
  html.begin("/%s/ - %s", board, (op_tbl.Subject and op_tbl.Subject ~= "")
                                 and html.striphtml(op_tbl.Subject)
                                  or html.striphtml(op_tbl.Comment:sub(1, 64)))
  local banner = pico.board.banner.get(board)
  if banner then
    printf("<img id='banner' src='/Media/%s' height='100' alt='[BANNER]' />", banner)
  end
  printf("<h1 id='boardtitle'><a href='/%s/'>/%s/</a> - %s</h1>",
         board, board, html.striphtml(board_tbl.Title))
  printf("<h2 id='boardsubtitle'>%s</h2>", html.striphtml(board_tbl.Subtitle or ""))
  html.announcement()
  local replyable = (board_tbl.Lock ~= 1 and op_tbl.Lock ~= 1) or permit(board_tbl.Name)
  if replyable then
    printf("<a id='new-post' href='#postform'>[Make a Post]</a>")
    html.form.postform(board_tbl, number)
  end
  printf("<hr />")

  for i = 1, #thread_tbl do
    if i ~= 1 then
      printf("<hr class='invisible' />")
    end
    html.renderpost(thread_tbl[i], false, views.THREAD)
  end

  printf("<hr />")
  if page then
    html.renderpages(("/%s/%d"):format(board, number), page, pagecount)
  end
  printf("<a href='/%s/catalog'>[Catalog]</a> ", board)
  printf("<a href='/%s/index'>[Index]</a> ", board)
  printf("<a href='/%s/recent'>[Recent]</a> ", board)

  printf("<span class='float-right'>")
  printf("<a href=''>[Update]</a> ")
  if replyable then
    printf("<a href='#postform'>[Reply]</a> ")
  end
  local reply_count = op_tbl.ReplyCount
  printf("%d %s", reply_count, reply_count == 1 and "reply" or "replies")
  printf("</span>")

  html.finish()
end

handlers["/([%l%d]+)/(%d+)/(%d+)"] = handlers["/([%l%d]+)/(%d+)"]

handlers["/Theme"] = function()
  html.brc("change theme configuration", "Change theme configuration")

  if os.getenv("REQUEST_METHOD") == "POST" then
    if not tbl_validate(cgi.POST, "theme") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Action failed", "Invalid request")
    end

    if not io.exists("./Static/" .. cgi.POST.theme .. ".css") then
      cgi.headers.Status = "400 Bad Request"
      html.error("Theme not found", "Cannot find theme file: %s", cgi.POST.theme)
    end

    cgi.headers["Set-Cookie"] = "theme=" .. cgi.POST.theme .. "; HttpOnly; Path=/; SameSite=Strict"
    cgi.headers.Status = "303 See Other"
    cgi.headers.Location = "/"
    pico.finalize()
    cgi.finalize()
  end

  printf("<form method='post'>")
  printf(  "<label for='theme'>theme</label>")
  printf(  "<select id='theme' name='theme' autofocus>")
  html.form.theme_selection(cgi.COOKIE.theme or theme)
  printf(  "</select>")
  printf(  "<br /><label for='submit'>Submit</label><input id='submit' type='submit' value='Set' />")
  printf("</form>")

  html.cfinish()
end

handlers["/Post"] = function()
  if os.getenv("REQUEST_METHOD") ~= "POST" then
    cgi.headers.Status = "400 Bad Request"
    html.error("Action failed", "Invalid request")
  end

  local board_tbl = pico.board.tbl(cgi.POST.board)
  if not board_tbl then
    cgi.headers.Status = "400 Bad Request"
    html.error("Board Not Found", "The board you specified does not exist.")
  end

  local files = {}
  for i = 1, board_tbl.PostMaxFiles do
    local file = cgi.FILE["file" .. i]
    if file then
      local hash, msg = pico.file.add(file.file)
      if not hash then
        cgi.headers.Status = "400 Bad Request"
        html.error("File Upload Error", "Cannot add file #%d: %s", i, msg)
      end
      files[#files + 1] = { Name = file.filename, Hash = hash, Spoiler = cgi.POST["spoiler" .. i] and 1 or 0 }
    end
  end

  local number, msg = pico.post.create(
    cgi.POST.board, tonumber(cgi.POST.parent),
    cgi.POST.name ~= "" and cgi.POST.name or nil,
    cgi.POST.email ~= "" and cgi.POST.email or nil,
    cgi.POST.subject ~= "" and cgi.POST.subject or nil,
    cgi.POST.comment, files,
    cgi.POST.captchaid, cgi.POST.captcha
  )

  if not number then
    cgi.headers.Status = "400 Bad Request"
    html.error("Posting Error", "Cannot make post: %s", msg)
  end

  cgi.headers.Status = "303 See Other"

  if cgi.POST.parent then
    cgi.headers.Location = "/" .. cgi.POST.board .. "/" .. cgi.POST.parent .. "#" .. number
  else
    cgi.headers.Location = "/" .. cgi.POST.board .. "/" .. number
  end
end

local path_info = os.getenv("PATH_INFO")
if not path_info then
  cgi.headers.Status = "500 Internal Server Error"
  html.error("Internal Server Error", "Request path was not provided")
end

for patt, func in pairs(handlers) do
  patt = "^" .. patt .. "$"

  if path_info:match(patt) then
    path_info:gsub(patt, func)
    pico.finalize()
    cgi.finalize()
  end
end

cgi.headers.Status = "404 Not Found"
html.error("Page Not Found", "The specified page does not exist.")
