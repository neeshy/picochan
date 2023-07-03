-- Picochan Backend.
-- HAPAS ARE MENTALLY ILL DEGENERATES

local sqlite3 = require("lib.sqlite3")
local sha = require("lib.sha")
local argon2 = require("lib.argon2")

require("lib.stringmisc")

local pico = {}
      pico.global = {}
      pico.account = {}
      pico.board = {}
      pico.board.stats = {}
      pico.board.banner = {}
      pico.file = {}
      pico.post = {}
      pico.thread = {}
      pico.log = {}
      pico.captcha = {}
      pico.webring = {}
      pico.webring.endpoint = {}

db = assert(sqlite3.open("picochan.db", "w"))
db:e("PRAGMA busy_timeout = 10000")
db:e("PRAGMA foreign_keys = ON")
db:e("PRAGMA recursive_triggers = ON")
db:e("PRAGMA secure_delete = ON")
db:e("PRAGMA case_sensitive_like = ON")

--
-- ACCOUNT MANAGEMENT FUNCTIONS
--

pico.account.current = nil

local function valid_account_name(name)
  return type(name) == "string" and #name <= 16 and #name >= 1 and not name:match("[^%w]")
end

local function valid_account_type(type)
  return type == "admin" or type == "gvol" or type == "bo" or type == "lvol"
end

local function valid_account_password(password)
  return type(password) == "string" and #password >= 6 and #password <= 128
end

-- permclass is a space-separated list of one or more of the following:
--   admin gvol bo lvol
-- targettype may be one of the following:
--   acct board post
local function permit(permclass, targettype, targarg)
  -- STEP 1. Check account type
  if not pico.account.current then
    return false, "Action not permitted (not logged in)"
  elseif not permclass:match(pico.account.current.Type) then
    return false, "Action not permitted (account type not authorized)"
  end

  -- STEP 2. Check targets
  -- If no target, stop here
  if not targettype then
    return true
  end

  -- Special case: Admin can modify any target
  if pico.account.current.Type == "admin" then
    return true
  end

  if targettype == "acct" then
    -- Special case: Anyone can modify their own account (password change)
    if pico.account.current.Name == targarg then
      return true
    end

    if pico.account.current.Type == "gvol" or pico.account.current.Type == "lvol" then
      return false, "Action not permitted (account type not authorized)"
    elseif pico.account.current.Type == "bo" then
      local board = db:r1("SELECT Board FROM Accounts WHERE Name = ?", targarg)
      if board == pico.account.current.Board then
        return true
      else
        return false, "Action not permitted (attempt to modify account outside assigned board)"
      end
    end
  elseif targettype == "board" then
    if pico.account.current.Type == "gvol" or pico.account.current.Type == "lvol" then
      return false, "Action not permitted (account type not authorized)"
    elseif pico.account.current.Type == "bo" then
      if targarg == pico.account.current.Board then
        return true
      else
        return false, "Action not permitted (attempt to modify non-assigned board)"
      end
    end
  elseif targettype == "post" then
    if pico.account.current.Type == "gvol" then
      return true
    elseif (pico.account.current.Type == "bo")
        or (pico.account.current.Type == "lvol") then
      if targarg == pico.account.current.Board then
        return true
      else
        return false, "Action not permitted (attempt to modify post outside assigned board)"
      end
    end
  end

  return false, "Action not permitted (unclassified denial: THIS IS A BUG, REPORT TO ADMINISTRATOR)"
end

function pico.account.create(name, password, type, board)
  local auth, msg = permit("admin bo", "board", board)
  if not auth then return auth, msg end

  if not valid_account_name(name) then
    return false, "Account name is invalid"
  elseif not valid_account_type(type) then
    return false, "Account type is invalid"
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements"
  elseif pico.account.exists(name) then
    return false, "Account already exists"
  elseif (type == "bo" or type == "lvol") then
    if not board then
      return false, "Board was not specified, but the account type requires it"
    elseif not pico.board.exists(board) then
      return false, "Account's specified board does not exist"
    end
  end

  if type == "admin" or type == "gvol" then
    board = nil
  end

  db:e("INSERT INTO Accounts (Name, Type, Board, PwHash) VALUES (?, ?, ?, ?)",
       name, type, board, argon2.digest(password))
  pico.log.insert(board, "Created new %s account '%s'", type, name)
  return true, "Account created successfully"
end

function pico.account.delete(name, reason)
  local auth, msg = permit("admin bo", "acct", name)
  if not auth then return auth, msg end

  local account_tbl = db:r("SELECT Type, Board FROM Accounts WHERE Name = ?", name)
  if not account_tbl then
    return false, "Account does not exist"
  end

  db:e("DELETE FROM Accounts WHERE Name = ?", name)
  pico.log.insert(account_tbl.Board, "Deleted a %s account '%s' for reason: %s",
                  account_tbl.Type, name, reason)
  return true, "Account deleted successfully"
end

function pico.account.changepass(name, password)
  local auth, msg = permit("admin gvol bo lvol", "acct", name)
  if not auth then return auth, msg end

  local account_tbl = db:r("SELECT Board FROM Accounts WHERE Name = ?", name)

  if not account_tbl then
    return false, "Account does not exist"
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements"
  end

  db:e("UPDATE Accounts SET PwHash = ? WHERE Name = ?",
       argon2.digest(password), name)
  pico.log.insert(account_tbl.Board, "Changed password of account '%s'", name)
  return true, "Account password changed successfully"
end

-- log in an account. returns an authentication key which you can use to perform
-- mod-only actions.
function pico.account.login(name, password)
  if not pico.account.exists(name)
      or not argon2.verify(password, db:r1("SELECT PwHash FROM Accounts WHERE Name = ?", name)) then
    return nil, "Invalid username or password"
  end

  local key = string.random(16)
  db:e("INSERT INTO Sessions (Key, Account) VALUES (?, ?)", key, name)

  pico.account.register_login(key)
  return key
end

-- populate the account table using an authentication key (perhaps provided by a
-- session cookie, or by pico.account.login() above)
function pico.account.register_login(key)
  if pico.account.current then
    pico.account.logout(key)
  end

  pico.account.current = db:r("SELECT * FROM Accounts WHERE Name = (SELECT Account FROM Sessions " ..
                              "WHERE Key = ? AND ExpireDate > STRFTIME('%s', 'now'))", key)
  db:e("UPDATE Sessions SET ExpireDate = STRFTIME('%s', 'now') + 86400 WHERE Key = ?", key)
end

function pico.account.logout(key)
  if not pico.account.current then
    return false, "No account logged in"
  end

  db:e("DELETE FROM Sessions WHERE Key = ?", key)
  return true, "Account logged out successfully"
end

function pico.account.list()
  return db:q1("SELECT Name FROM Accounts")
end

function pico.account.exists(name)
  return db:b("SELECT TRUE FROM Accounts WHERE Name = ?", name)
end

--
-- GLOBAL CONFIGURATION FUNCTIONS
--

-- retrieve value of globalconfig variable or the default value if it doesn't exist
function pico.global.get(name, default)
  local value = db:r1("SELECT Value FROM GlobalConfig WHERE Name = ?", name)
  if value ~= nil then
    return value
  end
  return default
end

-- setting a globalconfig variable to nil removes it.
function pico.global.set(name, value)
  local auth, msg = permit("admin")
  if not auth then return auth, msg end

  db:e("DELETE FROM GlobalConfig WHERE Name = ?", name)

  if value ~= nil then
    db:e("INSERT INTO GlobalConfig VALUES (?, ?)", name, value)
  end

  pico.log.insert(nil, "Edited global configuration variable '%s'", name)
  return true, "Global configuration modified"
end

--
-- BOARD MANAGEMENT FUNCTIONS
--

local function valid_board_name(name)
  return type(name) == "string" and #name >= 1 and #name <= 8 and not name:match("[^%l%d]")
end

local function valid_board_title(title)
  return type(title) == "string" and #title >= 1 and #title <= 32
end

local function valid_board_subtitle(subtitle)
  return type(subtitle) == "string" and #subtitle >= 1 and #subtitle <= 64
end

function pico.board.create(name, title, subtitle)
  local auth, msg = permit("admin")
  if not auth then return auth, msg end

  if pico.board.exists(name) then
    return false, "Board already exists"
  elseif not valid_board_name(name) then
    return false, "Invalid board name"
  elseif not valid_board_title(name) then
    return false, "Invalid board title"
  elseif subtitle and not valid_board_subtitle(subtitle) then
    return false, "Invalid board subtitle"
  end

  db:e("INSERT INTO Boards (Name, Title, Subtitle) VALUES (?, ?, ?)",
       name, title, subtitle)
  pico.log.insert(nil, "Created a new board: /%s/ - %s", name, title)
  return true, "Board created successfully"
end

function pico.board.delete(name, reason)
  local auth, msg = permit("admin")
  if not auth then return auth, msg end

  if not pico.board.exists(name) then
    return false, "Board does not exist"
  end

  db:e("DELETE FROM Boards WHERE Name = ?", name)
  pico.log.insert(nil, "Deleted board /%s/ for reason: %s", name, reason)
  pico.file.clean()
  return true, "Board deleted successfully"
end

function pico.board.list()
  return db:q("SELECT Name, Title, Subtitle FROM Boards ORDER BY DisplayOverboard DESC, MaxPostNumber DESC")
end

function pico.board.exists(name)
  return db:b("SELECT TRUE FROM Boards WHERE Name = ?", name)
end

function pico.board.tbl(name)
  return db:r("SELECT * FROM Boards WHERE Name = ?", name)
end

function pico.board.configure(board_tbl)
  local auth, msg = permit("admin bo", "board", board_tbl.Name)
  if not auth then return auth, msg end

  if not board_tbl then
    return false, "Board configuration not supplied"
  elseif not pico.board.exists(board_tbl.Name) then
    return false, "Board does not exist"
  end

  db:e("UPDATE Boards SET Title = ?, Subtitle = ?, Lock = ?, DisplayOverboard = ?, " ..
       "PostMaxFiles = ?, ThreadMinLength = ?, PostMaxLength = ?, PostMaxNewlines = ?, " ..
       "PostMaxDblNewlines = ?, TPHLimit = ?, PPHLimit = ?, ThreadCaptcha = ?, " ..
       "PostCaptcha = ?, CaptchaTriggerTPH = ?, CaptchaTriggerPPH = ?, " ..
       "BumpLimit = ?, PostLimit = ?, ThreadLimit = ? WHERE Name = ?",
       board_tbl.Title,              board_tbl.Subtitle,
       board_tbl.Lock or 0,          board_tbl.DisplayOverboard or 0,
       board_tbl.PostMaxFiles,       board_tbl.ThreadMinLength,
       board_tbl.PostMaxLength,      board_tbl.PostMaxNewlines,
       board_tbl.PostMaxDblNewlines, board_tbl.TPHLimit,
       board_tbl.PPHLimit,           board_tbl.ThreadCaptcha or 0,
       board_tbl.PostCaptcha or 0,   board_tbl.CaptchaTriggerTPH,
       board_tbl.CaptchaTriggerPPH,  board_tbl.BumpLimit,
       board_tbl.PostLimit,          board_tbl.ThreadLimit,
       board_tbl.Name)

  pico.log.insert(board_tbl.Name, "Modified board configuration")
  return true, "Board configured successfully"
end

function pico.board.catalog(name, page)
  if name and not pico.board.exists(name) then
    return nil, nil, "Board does not exist"
  end

  page = tonumber(page) or 1
  local where = name and "Threads.Board = ? "
                      or "Threads.Board IN (SELECT Name FROM Boards WHERE DisplayOverboard) "
  local sql = "SELECT Posts.*, LastBumpDate, Sticky, Lock, Autosage, Cycle, ReplyCount, File, Spoiler, Width AS FileWidth, Height AS FileHeight " ..
              "FROM Threads JOIN Posts USING(Board, Number) LEFT JOIN FileRefs USING(Board, Number) LEFT JOIN Files ON FileRefs.File = Files.Name " ..
              "WHERE (Sequence = 1 OR Sequence IS NULL) AND " ..
              where ..
              "ORDER BY " ..
              (name and "Sticky DESC, LastBumpDate DESC, Threads.Number DESC "
                     or "LastBumpDate DESC ") ..
              "LIMIT ? OFFSET ?"
  local pagecount_sql = "SELECT ((COUNT(*) - 1) / CAST(? AS INTEGER)) + 1 FROM Threads WHERE " .. where

  local catalog_tbl, pagecount
  if name then
    local pagesize = pico.global.get("catalogpagesize", 1000)
    catalog_tbl = db:q(sql, name, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql, pagesize, name)
  else
    local pagesize = pico.global.get("overboardpagesize", 100)
    catalog_tbl = db:q(sql, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql, pagesize)
  end

  return catalog_tbl, pagecount
end

function pico.board.index(name, page)
  if name and not pico.board.exists(name) then
    return nil, nil, "Board does not exist"
  end

  page = tonumber(page) or 1
  local pagesize = pico.global.get("indexpagesize", 10)
  local threadpagesize = pico.global.get("threadpagesize", 50)
  local windowsize = pico.global.get("indexwindowsize", 5)

  local where = name and "WHERE Board = ? " or ""
  local sql = "SELECT Board, Number FROM Threads " ..
              where ..
              "ORDER BY " ..
              (name and "Sticky DESC, LastBumpDate DESC, Threads.Number DESC "
                     or "LastBumpDate DESC ") ..
              "LIMIT ? OFFSET ?"
  local pagecount_sql = "SELECT ((COUNT(*) - 1) / CAST(? AS INTEGER)) + 1"

  local thread_ops, pagecount
  if name then
    thread_ops = db:q(sql, name, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql .. " FROM Threads " .. where, pagesize, name)
  else
    thread_ops = db:q(sql, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql .. " FROM Threads " .. where, pagesize)
  end

  local index_tbl = {}
  for i = 1, #thread_ops do
    local op_tbl = thread_ops[i]
    local thread_tbl = db:q("SELECT Posts.*, LastBumpDate, Sticky, Lock, Autosage, Cycle, ReplyCount, " ..
                            "IIF(ReplyCount > ?, ReplyCount - ?, 0) AS RepliesOmitted, (" ..
                            pagecount_sql .. " FROM Posts WHERE Board = Threads.Board AND Parent = Threads.Number) AS PageCount " ..
                            "FROM Threads JOIN Posts USING(Board, Number) " ..
                            "WHERE Board = ? AND Number = ? " ..
                            "UNION ALL " ..
                            "SELECT * FROM " ..
                            "(SELECT *, " ..
                            "NULL AS LastBumpDate, NULL AS Sticky, NULL AS Lock, " ..
                            "NULL AS Autosage, NULL AS Cycle, NULL AS ReplyCount, " ..
                            "NULL AS RepliesOmitted, NULL AS PageCount " ..
                            "FROM Posts " ..
                            "WHERE Board = ? AND Parent = ? ORDER BY Number DESC LIMIT ?) " ..
                            "ORDER BY Number ASC",
                            windowsize, windowsize, threadpagesize,
                            op_tbl.Board, op_tbl.Number,
                            op_tbl.Board, op_tbl.Number, windowsize)
    for j = 1, #thread_tbl do
      thread_tbl[j].Files = pico.file.list(thread_tbl[j].Board, thread_tbl[j].Number)
    end
    index_tbl[i] = thread_tbl
  end

  return index_tbl, pagecount
end

function pico.board.recent(name, page)
  if name and not pico.board.exists(name) then
    return nil, nil, "Board does not exist"
  end

  page = tonumber(page) or 1
  local pagesize = pico.global.get("recentpagesize", 50)

  local where = name and "WHERE Board = ? " or ""
  local sql = "SELECT * FROM Posts " ..  where ..  "ORDER BY Date DESC LIMIT ? OFFSET ?"
  local pagecount_sql = "SELECT ((COUNT(*) - 1) / CAST(? AS INTEGER)) + 1 FROM Posts " .. where

  local recent_tbl, pagecount
  if name then
    recent_tbl = db:q(sql, name, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql, pagesize, name)
  else
    recent_tbl = db:q(sql, pagesize, (page - 1) * pagesize)
    pagecount = db:r1(pagecount_sql, pagesize)
  end

  for i = 1, #recent_tbl do
    local post_tbl = recent_tbl[i]
    post_tbl.Files = pico.file.list(post_tbl.Board, post_tbl.Number)
  end

  return recent_tbl, pagecount
end

function pico.board.banner.get(board)
  if not pico.board.exists(board) then
    return nil, "Board does not exist"
  end

  local file = db:r1("SELECT File FROM Banners WHERE Board = ? ORDER BY RANDOM() LIMIT 1", board)
  if not file then
    return nil, "Banner does not exist"
  end
  return file
end

function pico.board.banner.list(board)
  if not pico.board.exists(board) then
    return nil, "Board does not exist"
  end

  return db:q1("SELECT File FROM Banners WHERE Board = ?", board)
end

function pico.board.banner.exists(board, file)
  return db:b("SELECT TRUE FROM Banners WHERE Board = ? AND File = ?", board, file)
end

function pico.board.banner.add(board, file)
  local auth, msg = permit("admin bo", "board", board)
  if not auth then return auth, msg end

  if not pico.board.exists(board) then
    return false, "Board does not exist"
  elseif not pico.file.exists(file) then
    return false, "File does not exist"
  elseif pico.board.banner.exists(board, file) then
    return false, "Banner already exists"
  end

  db:e("INSERT INTO Banners (Board, File) VALUES (?, ?)", board, file)
  pico.log.insert(board, "Added banner %s", file)
  return true, "Banner added successfully"
end

function pico.board.banner.delete(board, file, reason)
  local auth, msg = permit("admin bo", "board", board)
  if not auth then return auth, msg end

  if not pico.board.exists(board) then
    return false, "Board does not exist"
  elseif not pico.file.exists(file) then
    return false, "File does not exist"
  elseif not pico.board.banner.exists(board, file) then
    return false, "Banner does not exist"
  end

  db:e("DELETE FROM Banners WHERE Board = ? AND File = ?", board, file)
  pico.log.insert(board, "Deleted banner %s for reason: %s", file, reason)
  pico.file.clean()
  return true, "Banner deleted successfully"
end

-- To get number of posts per hour over the last 12 hours:
--   * interval = 1 (hour)
--   * intervals = 12 (12 hours)
-- To get number of posts per day over 1 week:
--   * interval = 24 (hours)
--   * intervals = 7 (7 * 24 hours = 1 week)
function pico.board.stats.threadrate(board, interval, intervals)
  return math.ceil(db:r1("SELECT (COUNT(*) / ?) FROM Posts WHERE Board = ? AND Parent IS NULL AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
                         intervals, board, interval * intervals))
end

function pico.board.stats.postrate(board, interval, intervals)
  return math.ceil(db:r1("SELECT (COUNT(*) / ?) FROM Posts WHERE Board = ? AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
                         intervals, board, interval * intervals))
end

function pico.board.stats.totalposts(board)
  return db:r1("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)
end

function pico.board.stats.lastbumpdate(board)
  return db:r1("SELECT MAX(LastBumpDate) FROM Threads WHERE Board = ?", board)
end

--
-- FILE MANAGEMENT FUNCTIONS
--

-- return a file's extension based on its contents
local function identify_file(data)
  if not data or #data == 0 then
    return nil
  end

  if data:sub(1,8) == "\x89PNG\x0D\x0A\x1A\x0A" then
    return "png"
  elseif data:sub(1,3) == "\xFF\xD8\xFF" then
    return "jpg"
  elseif data:sub(1,6) == "GIF87a"
      or data:sub(1,6) == "GIF89a" then
    return "gif"
  elseif data:sub(1,4) == "RIFF"
     and data:sub(9,12) == "WEBP" then
    return "webp"
  elseif data:sub(1,4) == "\x1A\x45\xDF\xA3" then
    return "webm"
  elseif data:sub(5,12) == "ftypmp42"
      or data:sub(5,12) == "ftypisom" then
    return "mp4"
  elseif data:sub(1,2) == "\xFF\xFB"
      or data:sub(1,3) == "ID3" then
    return "mp3"
  elseif data:sub(1,4) == "OggS" then
    return "ogg"
  elseif data:sub(1,4) == "fLaC" then
    return "flac"
  elseif data:sub(1,4) == "%PDF" then
    return "pdf"
  elseif data:sub(1,4) == "\x25\x21\x50\x53" then
    return "ps"
  elseif data:sub(1,4) == "PK\x03\x04"
     and data:sub(31,58) == "mimetypeapplication/epub+zip" then
    return "epub"
  elseif data:sub(1,3) == "\x1F\x8B\x08" then
    return "gz"
  elseif data:sub(1,3) == "BZh" then
    return "bz2"
  elseif data:sub(1,5) == "\xFD7zXZ" then
    return "xz"
  elseif data:sub(1,4) == "\x04\x22\x4D\x18" then
    return "lz4"
  elseif data:sub(1,4) == "\x28\xB5\x2F\xFD" then
    return "zst"
  elseif data:sub(258,262) == "ustar" then
    return "tar"
  elseif data:sub(1,4) == "PK\x03\x04" then
    return "zip"
  elseif data:sub(1,6) == "7z\xBC\xAF\x27\x1C" then
    return "7z"
  elseif data:sub(1,6) == "Rar!\x1A\x07" then
    return "rar"
  elseif data:find("DOCTYPE svg", 1, true)
      or data:find("<svg", 1, true) then
    return "svg"
  elseif not data:find("[^%w%s%p]") then
    return "txt"
  end

  return nil
end

-- return a file's extension based on its name
function pico.file.extension(filename)
  return filename:match("%.([^.]-)$")
end

-- return a file's media type based on its extension
function pico.file.class(extension)
  local lookup = {
    ["png"]  = "image",
    ["jpg"]  = "image",
    ["gif"]  = "image",
    ["webp"] = "image",
    ["svg"]  = "image",
    ["webm"] = "video",
    ["mp4"]  = "video",
    ["mp3"]  = "audio",
    ["ogg"]  = "audio",
    ["flac"] = "audio",
    ["pdf"]  = "document",
    ["ps"]   = "document",
    ["epub"] = "document",
    ["txt"]  = "document",
    ["gz"]   = "archive",
    ["bz2"]  = "archive",
    ["xz"]   = "archive",
    ["lz4"]  = "archive",
    ["zst"]  = "archive",
    ["tar"]  = "archive",
    ["zip"]  = "archive",
    ["7z"]   = "archive",
    ["rar"]  = "archive",
  }

  return lookup[extension] or extension
end

-- Add a file to the media directory and return its hash reference.
-- Also add its information to the database.
function pico.file.add(f)
  local size = assert(f:seek("end"))

  if size > pico.global.get("maxfilesize", 16777216) then
    f:close()
    return nil, "File too large"
  end

  assert(f:seek("set"))
  local data = assert(f:read("*a"))
  f:close()

  local extension = identify_file(data)
  if not extension then
    return nil, "Could not identify file type"
  end

  local class = pico.file.class(extension)
  local hash = sha.hash("sha256", data)
  local filename = hash .. "." .. extension

  if pico.file.exists(filename) then
    return filename, "File already existed and was not changed"
  end

  local newf = assert(io.open("Media/" .. filename, "w"))
  assert(newf:write(data))
  newf:close()

  local p, width, height
  if class == "video" or (class == "audio" and os.execute("exec ffmpeg -i Media/" .. filename .. " -map 0:v:0 -f image2 - >/dev/null")) then
    local ffmpeg = "ffmpeg -i Media/" .. filename ..
      (class == "video" and " -ss 00:00:00.500 -vframes 1 -f image2 -"
                         or " -map 0:v:0 -f image2 -")
    os.execute(ffmpeg .. " | exec convert -strip - -filter Catrom -thumbnail 200x200 JPEG:Media/thumb/" .. filename)
    os.execute(ffmpeg .. " | exec convert -strip - -filter Catrom -quality 60 -thumbnail 100x70 JPEG:Media/icon/" .. filename)
    p = io.popen("exec ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 " ..
                 "Media/" .. filename, "r")
  elseif class == "image" or extension == "pdf" or extension == "ps" then
    local prefix = (extension == "pdf" or extension == "ps" or extension == "svg") and "PNG:" or ""
    local frame = (extension == "pdf" or extension == "ps") and "[0]" or ""
    os.execute("exec convert -strip Media/" .. filename .. frame ..
               " -coalesce -filter Catrom -thumbnail 200x200 " .. prefix ..  "Media/thumb/" .. filename)
    os.execute("exec convert -strip Media/" .. filename ..
               "[0] -coalesce -filter Catrom -quality 60 -thumbnail 100x70 " .. prefix .. "Media/icon/" .. filename)
    p = io.popen("exec identify -format '%wx%h' Media/" .. filename .. "[0]", "r")
  end

  if p then
    local dimensions = p:read("*a"):tokenize("x")
    p:close()
    width, height = tonumber(dimensions[1]), tonumber(dimensions[2])
  end

  if (not width) or (not height) then
    width, height = nil, nil
  end

  db:e("INSERT INTO Files VALUES (?, ?, ?, ?)", filename, size, width, height)
  return filename, "File added successfully"
end

-- Delete a file from the media directory and remove its corresponding entries
-- in the database.
function pico.file.delete(filename, reason)
  local auth, msg = permit("admin gvol")
  if not auth then return auth, msg end

  if not pico.file.exists(filename) then
    return false, "File does not exist"
  end

  db:e("DELETE FROM Files WHERE Name = ?", filename)
  os.remove("Media/" .. filename)
  os.remove("Media/icon/" .. filename)
  os.remove("Media/thumb/" .. filename)

  pico.log.insert(nil, "Deleted file %s from all boards for reason: %s", filename, reason)
  return true, "File deleted successfully"
end

function pico.file.clean()
  local files = db:q1("SELECT Name FROM Files EXCEPT SELECT File FROM FileRefs EXCEPT SELECT File FROM Banners")
  for i = 1, #files do
    local file = files[i]
    db:e("DELETE FROM Files WHERE Name = ?", file)
    os.remove("Media/" .. file)
    os.remove("Media/icon/" .. file)
    os.remove("Media/thumb/" .. file)
  end
end

function pico.file.list(board, number)
  return db:q("SELECT Files.*, FileRefs.Name AS DownloadName, Spoiler " ..
              "FROM FileRefs JOIN Files ON FileRefs.File = Files.Name " ..
              "WHERE Board = ? AND Number = ? ORDER BY Sequence ASC",
              board, number)
end

function pico.file.exists(name)
  return db:b("SELECT TRUE FROM Files WHERE Name = ?", name)
end

function pico.file.create_refs(board, number, files)
  if files then
    for i = 1, #files do
      local file = files[i]
      if file.Hash and file.Hash ~= "" then
        db:e("INSERT INTO FileRefs VALUES (?, ?, ?, ?, ?, ?)", board, number, file.Hash, file.Name, file.Spoiler, i)
      end
    end
  end
end

--
-- POST ACCESS, CREATION AND DELETION FUNCTIONS
--

function pico.post.tbl(board, number, omit_files)
  local post_tbl = db:r("SELECT * FROM Posts LEFT JOIN Threads USING(Board, Number) WHERE Board = ? AND Number = ?", board, number)
  if post_tbl and not omit_files then
    post_tbl.Files = pico.file.list(board, number)
  end
  return post_tbl
end

-- Return list of posts which >>reply to the specified post.
function pico.post.refs(board, number)
  return db:q1("SELECT Referrer FROM Refs WHERE Board = ? AND Referee = ?", board, number)
end

-- Create a post and return its number
-- 'files' is an array with a collection of file hashes to attach to the post
function pico.post.create(board, parent, name, email, subject, comment, files, captcha_id, captcha_text)
  local board_tbl = pico.board.tbl(board)
  local is_thread = not parent

  local capcode, capcode_board
  if name == "##" and pico.account.current then
    name = pico.account.current.Name
    capcode = pico.account.current.Type
    capcode_board = pico.account.current.Board
  end

  comment = comment and comment:gsub("[\1-\8\11-\31\127]", ""):gsub("^\n+", ""):gsub("%s+$", "") or ""

  if not board_tbl then
    return nil, "Board does not exist"
  elseif board_tbl.Lock == 1 and not permit("admin gvol bo lvol", "board", board) then
    return nil, "Board is locked"
  elseif board_tbl.PPHLimit and pico.board.stats.postrate(board, 1, 1) > board_tbl.PPHLimit then
    return nil, "Maximum post creation rate exceeded"
  elseif #comment > board_tbl.PostMaxLength then
    return nil, "Post text too long"
  elseif select(2, comment:gsub("\r?\n", "")) > board_tbl.PostMaxNewlines then
    return nil, "Post contained too many newlines"
  elseif select(2, comment:gsub("\r?\n\r?\n", "")) > board_tbl.PostMaxDblNewlines then
    return nil, "Post contained too many double newlines"
  elseif name and #name > 64 then
    return nil, "Name too long"
  elseif email and #email > 64 then
    return nil, "Email too long"
  elseif subject and #subject > 64 then
    return nil, "Subject too long"
  elseif (not files or #files == 0) and #comment == 0 then
    return nil, "Post is blank"
  elseif ((is_thread and board_tbl.ThreadCaptcha == 1) or (not is_thread and board_tbl.PostCaptcha == 1))
         and not permit("admin gvol bo lvol", "post", board)
         and not pico.captcha.check(captcha_id, captcha_text) then
    return nil, "Captcha is required but no valid captcha supplied"
  elseif is_thread then
    if board_tbl.TPHLimit and pico.board.stats.threadrate(board, 1, 1) > board_tbl.TPHLimit then
      return nil, "Maximum thread creation rate exceeded"
    elseif #comment < board_tbl.ThreadMinLength then
      return nil, "Thread text too short"
    end
  else
    local parent_tbl = pico.post.tbl(board, parent)
    if not parent_tbl then
      return nil, "Parent thread does not exist"
    elseif parent_tbl.Parent then
      return nil, "Parent post is not a thread"
    elseif parent_tbl.Lock == 1 and not permit("admin gvol bo lvol", "post", board) then
      return nil, "Parent thread is locked"
    elseif parent_tbl.Cycle ~= 1 and board_tbl.PostLimit
           and parent_tbl.ReplyCount >= board_tbl.PostLimit then
      return nil, "Thread full"
    end
  end

  db:e("BEGIN TRANSACTION")
  db:e("INSERT INTO Posts (Board, Parent, Name, Email, Subject, Capcode, CapcodeBoard, Comment) " ..
       "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", board, parent, name, email, subject, capcode, capcode_board, comment)
  local number = db:r1("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)

  pico.file.create_refs(board, number, files)
  pico.post.create_refs(board, number, parent, email, comment)

  db:e("END TRANSACTION")
  return number
end

function pico.post.set(board, parent, date, name, email, subject, capcode, capcode_board, comment, files)
  local auth, msg = permit("admin gvol")
  if not auth then return auth, msg end

  db:e("BEGIN TRANSACTION")
  db:e("INSERT INTO Posts (Board, Parent, Date, Name, Email, Subject, Capcode, CapcodeBoard, Comment) " ..
       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", board, parent, date, name, email, subject, capcode, capcode_board, comment)
  local number = db:r1("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)

  pico.file.create_refs(board, number, files)
  pico.post.create_refs(board, number, parent, email, comment)

  db:e("END TRANSACTION")
  return number
end

function pico.post.create_refs(board, number, parent, email, comment)
  if not email or not (email == "nofo" or email:match("^nofo ") or email:match(" nofo$") or email:match(" nofo ")) then
    for ref in comment:gmatch(">>(%d+)") do
      ref = tonumber(ref)

      -- 1. Ensure that the reference doesn't already exist.
      -- 2. Ensure that the post being referred to does exist.
      -- 3. Ensure that the post being referred to is in the same thread as the referrer.
      -- 4. Ensure that the post being referred to is not the same as the referrer.
      if ref ~= number then
        db:e("INSERT INTO Refs SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM Refs WHERE Board = ? AND Referee = ? AND Referrer = ?) = 0 " ..
             "AND (SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?) " ..
             "AND ((SELECT Parent FROM Posts WHERE Board = ? AND Number = ?) = ? OR (? = ?))",
             board, ref, number, board, ref, number, board, ref, board, ref, parent, ref, parent)
      end
    end
  end
end

function pico.post.delete(board, number, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board)
  if not auth then return auth, msg end

  if not db:b("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?", board, number) then
    return false, "Post does not exist"
  end

  db:e("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number)
  pico.log.insert(board, "Deleted post /%s/%d for reason: %s", board, number, reason)
  pico.file.clean()
  return true, "Post deleted successfully"
end

-- example: pico.post.multidelete("b", "31-57 459-1000", "33 35 48 466", "spam")
function pico.post.multidelete(board, include, exclude, reason)
  local auth, msg = permit("admin bo", "board", board)
  if not auth then return auth, msg end
  if not include then return false, "Invalid include parameter" end

  if not pico.board.exists(board) then
    return false, "Board does not exist"
  end

  local sql = { "DELETE FROM Posts WHERE Board = ? AND (FALSE" }
  local sqlp = { board }
  local inclist = include:tokenize()

  local function genspec(spec, sql, sqlp)
    if spec:match("-") then
      local spec_tbl = spec:tokenize("-")
      if #spec_tbl ~= 2 then
        return false, "Invalid range specification"
      end

      local start, finish = unpack(spec_tbl)
      start, finish = tonumber(start), tonumber(finish)
      if not start or not finish then
        return false, "Invalid range specification"
      end

      sql[#sql + 1] = "OR Number BETWEEN ? AND ?"
      sqlp[#sqlp + 1] = start
      sqlp[#sqlp + 1] = finish
    else
      local number = tonumber(spec)
      if not number then
        return false, "Invalid single specification"
      end

      sql[#sql + 1] = "OR Number = ?"
      sqlp[#sqlp + 1] = number
    end

    return true
  end

  for i = 1, #inclist do
    local result, msg = genspec(inclist[i], sql, sqlp)
    if not result then return result, msg end
  end
  sql[#sql + 1] = ") AND NOT (FALSE"
  if exclude then
    local exclist = exclude:tokenize()
    for i = 1, #exclist do
      local result, msg = genspec(exclist[i], sql, sqlp)
      if not result then return result, msg end
    end
  end
  sql[#sql + 1] = ")"

  db:e(table.concat(sql, " "), unpack(sqlp))
  pico.log.insert(board, "Deleted posts {%s}%s for reason: %s",
                  include, exclude and (" excluding {" .. exclude .. "}") or "", reason)
  pico.file.clean()
  return true, "Posts deleted successfully"
end

function pico.post.pattdelete(pattern, reason)
  local auth, msg = permit("admin")
  if not auth then return auth, msg end
  if not pattern or #pattern < 6 then return false, "Invalid or too short include pattern" end

  db:e("DELETE FROM Posts WHERE Comment LIKE ? ESCAPE '$'", pattern)
  pico.log.insert(nil, "Deleted posts matching pattern '%s' for reason: %s", pattern, reason)
  pico.file.clean()
  return true, "Posts deleted successfully"
end

-- remove a file from a post without deleting it
function pico.post.unlink(board, number, file, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board)
  if not auth then return auth, msg end

  if not db:b("SELECT TRUE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?",
              board, number, file) then
    return false, "No such file in that particular post"
  end

  db:e("DELETE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?", board, number, file)
  pico.log.insert(board, "Unlinked file %s from /%s/%d for reason: %s",
                  file, board, number, reason)
  pico.file.clean()
  return true, "File unlinked successfully"
end

function pico.post.spoiler(board, number, file, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board)
  if not auth then return auth, msg end

  if not db:b("SELECT TRUE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?",
              board, number, file) then
    return false, "No such file in the given post"
  end

  db:e("UPDATE FileRefs SET Spoiler = NOT Spoiler WHERE Board = ? AND Number = ? AND File = ?",
       board, number, file)
  pico.log.insert(board, "Toggled spoiler on file %s from /%s/%d for reason: %s",
                  file, board, number, reason)
  return true, "Spoiler toggled on file sucessfully"
end

--
-- THREAD ACCESS AND MODIFICATION FUNCTIONS
--

-- Return entire thread (parent + all replies + all file info) as a table
function pico.thread.tbl(board, number, page)
  if not pico.thread.exists(board, number) then
    return nil, nil, "Post is not a thread or does not exist"
  end

  db:e("BEGIN TRANSACTION")
  local thread_tbl, pagecount
  if page then
    local pagesize = pico.global.get("threadpagesize", 50)
    thread_tbl = db:q("SELECT Posts.*, LastBumpDate, Sticky, Lock, Autosage, Cycle, ReplyCount " ..
                      "FROM Threads JOIN Posts USING(Board, Number) " ..
                      "WHERE Board = ? AND Number = ? " ..
                      "UNION ALL " ..
                      "SELECT * FROM " ..
                      "(SELECT *, " ..
                      "NULL AS LastBumpDate, NULL AS Sticky, NULL AS Lock, " ..
                      "NULL AS Autosage, NULL AS Cycle, NULL AS ReplyCount " ..
                      "FROM Posts " ..
                      "WHERE Board = ? AND Parent = ? ORDER BY Number ASC " ..
                      "LIMIT ? OFFSET ?)",
                      board, number,
                      board, number, pagesize, (page - 1) * pagesize)
    pagecount = db:r1("SELECT ((COUNT(*) - 1) / CAST(? AS INTEGER)) + 1 FROM Posts WHERE Board = ? AND Parent = ?",
                      pagesize, board, number)

  else
    thread_tbl = db:q("SELECT * FROM Posts LEFT JOIN Threads USING(Board, Number) " ..
                      "WHERE Board = ? AND (Number = ? OR Parent = ?) ORDER BY Number ASC",
                      board, number, number)
  end
  for i = 1, #thread_tbl do
    local post_tbl = thread_tbl[i]
    post_tbl.Files = pico.file.list(post_tbl.Board, post_tbl.Number)
  end
  db:e("END TRANSACTION")

  return thread_tbl, pagecount
end

-- toggle sticky, lock, autosage, or cycle
function pico.thread.toggle(attribute, board, number, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board)
  if not auth then return auth, msg end

  if not pico.thread.exists(board, number) then
    return false, "Thread does not exist"
  end

  if attribute == "sticky" then
    db:e("UPDATE Threads SET Sticky = NOT Sticky WHERE Board = ? AND Number = ?", board, number)
  elseif attribute == "lock" then
    db:e("UPDATE Threads SET Lock = NOT Lock WHERE Board = ? AND Number = ?", board, number)
  elseif attribute == "autosage" then
    db:e("UPDATE Threads SET Autosage = NOT Autosage WHERE Board = ? AND Number = ?", board, number)
  elseif attribute == "cycle" then
    db:e("UPDATE Threads SET Cycle = NOT Cycle WHERE Board = ? AND Number = ?", board, number)
  else
    return false, "Invalid attribute"
  end

  pico.log.insert(board, "Toggled attribute '%s' on /%s/%d for reason: %s",
                  attribute, board, number, reason)
  return true, "Attribute toggled successfully"
end

-- 1. Fetch all contents of the thread.
-- 2. For each post of the thread, including the OP:
--    1. Rewrite references in the post's comment using the old->new lookup table.
--    2. Repost the post to the new board.
--    3. Keep a lookup table of the old post number and the new post number.
-- 3. Delete the old thread.
function pico.thread.move(board, number, newboard, reason)
  local auth, msg = permit("admin gvol", "post", board)
  if not auth then return auth, msg end

  if not pico.thread.exists(board, number) then
    return false, "Post does not exist or is not a thread"
  elseif not pico.board.exists(newboard) then
    return false, "Destination board does not exist"
  end

  local thread_tbl = pico.thread.tbl(board, number)
  local number_lut = {}
  local newthread

  for i = 1, #thread_tbl do
    local post_tbl = thread_tbl[i]
    post_tbl.Comment = post_tbl.Comment:gsub(">>(%d+)", number_lut)
    post_tbl.Parent = post_tbl.Parent and newthread

    for j = 1, #post_tbl.Files do
      post_tbl.Files[j] = { Name = post_tbl.Files[j].DownloadName,
                            Hash = post_tbl.Files[j].Name,
                            Spoiler = post_tbl.Files[j].Spoiler }
    end

    local newnumber = pico.post.set(newboard, post_tbl.Parent, post_tbl.Date,
                                    post_tbl.Name, post_tbl.Email, post_tbl.Subject,
                                    post_tbl.Capcode, post_tbl.CapcodeBoard,
                                    post_tbl.Comment, post_tbl.Files)
    number_lut[tostring(post_tbl.Number)] = ">>" .. tostring(newnumber)

    if i == 1 then
      newthread = newnumber
    end
  end

  db:e("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number)
  pico.log.insert(nil, "Moved thread /%s/%d to /%s/%d for reason: %s", board, number, newboard, newthread, reason)
  return true, "Thread moved successfully"
end

function pico.thread.merge(board, number, newthread, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board)
  if not auth then return auth, msg end

  if not pico.thread.exists(board, number) then
    return false, "Source thread does not exist"
  elseif not pico.thread.exists(board, newthread) then
    return false, "Destination thread does not exist"
  end

  db:e("BEGIN TRANSACTION")
  db:e("UPDATE Posts SET Parent = ? WHERE Board = ? AND (Number = ? OR Parent = ?)", newthread, board, number, number)
  db:e("DELETE FROM Threads WHERE Board = ? AND Number = ?", board, number)
  db:e("END TRANSACTION")
  pico.log.insert(board, "Merged thread /%s/%d into /%s/%d for reason: %s", board, number, board, newthread, reason)
  return true, "Thread merged successfully"
end

function pico.thread.exists(board, number)
  return db:b("SELECT TRUE FROM Threads WHERE Board = ? AND Number = ?", board, number)
end

--
-- LOG FUNCTIONS
--

-- Use nil for the board parameter if the action applies to all boards.
function pico.log.insert(board, ...)
  local account = pico.account.current and pico.account.current.Name
  db:e("INSERT INTO Logs (Account, Board, Description) VALUES (?, ?, ?)",
       account, board, string.format(...))
end

function pico.log.retrieve(page)
  page = tonumber(page) or 1
  local pagesize = pico.global.get("logpagesize", 50)
  return db:q("SELECT * FROM Logs ORDER BY ROWID DESC LIMIT ? OFFSET ?", pagesize, (page - 1) * pagesize),
         db:r1("SELECT ((COUNT(*) - 1) / CAST(? AS INTEGER)) + 1 FROM Logs", pagesize)
end

--
-- CAPTCHA FUNCTIONS
--

-- return a captcha image (jpeg) and its associated id
function pico.captcha.create()
  local xx, yy, rr, ss, cc, bx, by = {},{},{},{},{},{},{}

  for i = 1, 6 do
    xx[i] = ((48 * i - 168) + math.csrandom(-5, 5))
    yy[i] = math.csrandom(-15, 15)
    rr[i] = math.csrandom(-30, 30)
    ss[i] = math.csrandom(-30, 30)
    cc[i] = string.random(1, "%l")
    bx[i] = (150 + 1.1 * xx[i])
    by[i] = (40 + 2 * yy[i])
  end

  local p = assert(io.popen((
    "convert -size 290x70 xc:white -bordercolor black -border 5 " ..
    "-fill black -stroke black -strokewidth 1 -pointsize 40 -font Courier-New " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-fill none -strokewidth 3 " ..
    "-draw 'bezier %f,%d %f,%d %f,%d %f,%d' " ..
    "-draw 'polyline %f,%d %f,%d %f,%d' -quality 1 JPEG:-"):format(
    xx[1], yy[1], rr[1], ss[1], cc[1],
    xx[2], yy[2], rr[2], ss[2], cc[2],
    xx[3], yy[3], rr[3], ss[3], cc[3],
    xx[4], yy[4], rr[4], ss[4], cc[4],
    xx[5], yy[5], rr[5], ss[5], cc[5],
    xx[6], yy[6], rr[6], ss[6], cc[6],
    bx[1], by[1], bx[2], by[2], bx[3], by[3], bx[4], by[4],
    bx[4], by[4], bx[5], by[5], bx[6], by[6]
  ), "r"))

  local captcha_data = p:read("*a")
  p:close()

  local captcha_id = string.random(16)
  db:e("INSERT INTO Captchas VALUES (?, ?, STRFTIME('%s', 'now') + 1200)", captcha_id, table.concat(cc))

  return captcha_id, captcha_data
end

function pico.captcha.check(id, text)
  if db:b("SELECT TRUE FROM Captchas WHERE Id = ? AND Text = LOWER(?) AND ExpireDate > STRFTIME('%s', 'now')", id, text) then
    db:e("DELETE FROM Captchas WHERE Id = ?", id)
    return true
  end
  return false
end

return pico
