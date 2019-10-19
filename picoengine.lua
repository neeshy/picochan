-- Picochan Backend.

local sqlite3 = require("lsqlite3");
local bcrypt = require("bcrypt");
local openssl = {};
      openssl.rand = require("openssl.rand");
      openssl.digest = require("openssl.digest");

local pico = {};
      pico.global = {};
      pico.account = {};
      pico.board = {};
      pico.board.stats = {};
      pico.file = {};
      pico.post = {};
      pico.log = {};
      pico.captcha = {};

local db, errcode, errmsg = sqlite3.open("picochan.db", sqlite3.OPEN_READWRITE);
assert(db, errmsg);
db:exec("PRAGMA busy_timeout = 10000");
db:exec("PRAGMA foreign_keys = ON");
db:exec("PRAGMA recursive_triggers = ON");

local bcrypt_rounds = 14;           -- reduce if logins are too slow
local max_filesize = 16777216;      -- 16 MiB

--
-- DATABASE HELPER FUNCTIONS
--

-- query database and return result rows
local function dbq(sql, ...)
  local stmt = db:prepare(sql);
  local rows = {};
  assert(stmt, db:errmsg());

  stmt:bind_values(...);

  for row in stmt:nrows() do
    rows[#rows + 1] = row;
  end

  stmt:finalize();
  return rows;
end

-- query database and return first result row
local function db1(sql, ...)
  return dbq(sql, ...)[1];
end

-- query database and return true or false depending on existence of result rows
local function dbb(sql, ...)
  return (db1(sql, ...) ~= nil);
end

--
-- MISCELLANEOUS FUNCTIONS
--

function string.random(length, pattern)
  local length = length or 64;
  local pattern = pattern or "a-zA-Z0-9"
  local result = "";
  local ascii = {};
  local dict = "";

  for i = 0, 255 do
    ascii[#ascii + 1] = string.char(i);
  end

  ascii = table.concat(ascii);
  dict = ascii:gsub("[^" .. pattern .. "]", "");

  while string.len(result) < length do
    local randidx = openssl.rand.uniform(string.len(dict)) + 1;
    local randbyte = dict:byte(randidx);
    result = result .. string.char(randbyte);
  end

  return result;
end

function string.tokenize(input, delimiter)
  local result = {};
  delimiter = delimiter or " ";

  if input == nil then
    return {};
  end

  for match in (input .. delimiter):gmatch("(.-)" .. delimiter) do
    result[#result + 1] = match;
  end

  return result;
end

function string.base64(s)
  local bs = { [0] =
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/',
  };

  local byte, rep = string.byte, string.rep;
  local pad = 2 - ((#s-1) % 3);
  s = (s..rep('\0', pad)):gsub("...", function(cs)
      local a, b, c = byte(cs, 1, 3);
      return bs[a>>2] .. bs[(a&3)<<4|(b>>4)] .. bs[(b&15)<<2|(c>>6)] .. bs[c&63];
  end);
  return s:sub(1, #s-pad) .. rep('=', pad);
end

function io.fileexists(path)
  local f = io.open(filename, "r");

  if f ~= nil then
    f:close();
    return true;
  else
    return false;
  end
end

local function sha512(data)
  local bstring = openssl.digest.new("sha512"):final(data);
  local result = {};

  for i = 1, #bstring do
    result[#result + 1] = string.format("%02x", string.byte(bstring:sub(i,i)));
  end

  return table.concat(result);
end

local function checkcaptcha(id, text)
  if dbb("SELECT TRUE FROM Captchas WHERE Id = ? AND Text = LOWER(?) AND ExpireDate > STRFTIME('%s', 'now')", id, text) then
    dbq("DELETE FROM Captchas WHERE ExpireDate <= STRFTIME('%s', 'now') OR Id = ?", id);
    return true;
  else
    return false;
  end
end

-- Use nil for the board parameter if the action applies to all boards.
-- system_action is a boolean describing whether the action was performed by
-- the system or by a logged-in account.
local function log(system_action, board, ...)
  local account = system_action and nil or pico.account.current["Name"];
  dbq("INSERT INTO Logs (Account, Board, Description) VALUES (?, ?, ?)",
      account or 'SYSTEM', board or 'GLOBAL', string.format(...));
end

--
-- ACCOUNT MANAGEMENT FUNCTIONS
--

pico.account.current = nil;

local function valid_account_name(name)
  return (type(name) == "string") and (#name <= 16 and #name >= 1) and (not name:match("[^a-zA-Z0-9]"))
         and name ~= "SYSTEM";
end

local function valid_account_type(type)
  return (type == "admin" or type == "gvol" or type == "bo" or type == "lvol");
end

local function valid_account_password(password)
  return (type(password) == "string") and (#password >= 6 and #password <= 128);
end

function pico.account.create(name, password, type, board)
  if not pico.account.current
     or (pico.account.current["Type"] ~= "admin"
         and pico.account.current["Type"] ~= "bo")
     or (pico.account.current["Type"] == "bo"
         and type ~= "lvol")
     or (pico.account.current["Type"] == "bo"
         and board ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  end

  if not valid_account_name(name) then
    return false, "Account name is invalid";
  elseif not valid_account_type(type) then
    return false, "Account type is invalid";
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements";
  elseif dbb("SELECT TRUE FROM Accounts WHERE Name = ?", name) then
    return false, "Account already exists";
  elseif (type == "bo" or type == "lvol") then
    if not board then
      return false, "Board was not specified, but the account type requires it";
    elseif not dbb("SELECT TRUE FROM Boards WHERE Name = ?", board) then
      return false, "Account's specified board does not exist";
    end
  end

  if type == "admin" or type == "gvol" then
    board = nil;
  end

  dbq("INSERT INTO Accounts (Name, Type, Board, PwHash) VALUES (?, ?, ?, ?)",
      name, type, board, bcrypt.digest(password, bcrypt_rounds));
  log(false, board, "Created new %s account '%s'", type, name);
  return true, "Account created successfully";
end

function pico.account.delete(name, reason)
  local account_tbl = db1("SELECT * FROM Accounts WHERE Name = ?", name);

  if not account_tbl then
    return false, "Account does not exist";
  elseif not pico.account.current
         or (pico.account.current["Type"] ~= "admin"
             and pico.account.current["Type"] ~= "bo")
         or (pico.account.current["Type"] == "bo"
             and account_tbl["Type"] ~= "lvol")
         or (pico.account.current["Type"] == "bo"
             and board ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  end

  dbq("DELETE FROM Accounts WHERE Name = ?", name);
  log(false, account_tbl["Board"], "Deleted a %s account '%s' for reason: %s",
                  account_tbl["Type"], account_tbl["Name"], reason);
  return true, "Account deleted successfully";
end

function pico.account.changepass(name, password)
  local account_tbl = db1("SELECT * FROM Accounts WHERE Name = ?", name);

  if not account_tbl then
    return false, "Account does not exist";
  elseif not pico.account.current
         or (pico.account.current["Type"] ~= "admin"
             and pico.account.current["Type"] ~= "bo"
             and account_tbl["Name"] ~= pico.account.current["Name"])
         or (pico.account.current["Type"] == "bo"
             and account_tbl["Board"] ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements";
  end

  dbq("UPDATE Accounts SET PwHash = ? WHERE Name = ?",
      bcrypt.digest(password, bcrypt_rounds), name);
  log(false, account_tbl["Board"], "Changed password of account '%s'", name);
  return true, "Account password changed successfully";
end

-- log in an account. returns an authentication key which you can use to perform
-- mod-only actions.
function pico.account.login(name, password)
  if not dbb("SELECT TRUE FROM Accounts WHERE Name = ?", name)
  or not bcrypt.verify(password, db1("SELECT PwHash FROM Accounts WHERE Name = ?", name)["PwHash"]) then
    return nil, "Invalid username or password";
  end

  local key = string.random(16, "a-zA-Z0-9");
  dbq("INSERT INTO Sessions (Key, Account) VALUES (?, ?)", key, name);

  pico.account.register_login(key);
  return key;
end

-- populate the account table using an authentication key (perhaps provided by a
-- session cookie, or by pico.account.login() above)
function pico.account.register_login(key)
  if pico.account.current ~= nil then
    pico.account.logout();
  end

  pico.account.current = db1("SELECT * FROM Accounts WHERE Name = (SELECT Account FROM Sessions " ..
                             "WHERE Key = ? AND ExpireDate > STRFTIME('%s', 'now'))", key);
  dbq("UPDATE Sessions SET ExpireDate = STRFTIME('%s', 'now') + 86400 WHERE Key = ?", key);
end

function pico.account.logout()
  if not pico.account.current then
    return false, "No account logged in";
  end

  dbq("DELETE FROM Sessions WHERE Key = ?", key);
  return true, "Account logged out successfully";
end

function pico.account.exists(name)
  return dbb("SELECT TRUE FROM Accounts WHERE Name = ?", name);
end

--
-- GLOBAL CONFIGURATION FUNCTIONS
-- 

-- retrieve value of globalconfig variable or empty string if it doesn't exist
function pico.global.get(name)
  local row = db1("SELECT Value FROM GlobalConfig WHERE Name = ?", name);
  return row and row["Value"] or "";
end

-- setting a globalconfig variable to nil removes it.
function pico.global.set(name, value)
  if not pico.account.current
     or pico.account.current["Type"] ~= "admin" then
    return false, "Action not permitted";
  end

  dbq("DELETE FROM GlobalConfig WHERE Name = ?", name);

  if value ~= nil then
    dbq("INSERT INTO GlobalConfig VALUES (?, ?)", name, value);
  end

  log(false, nil, "Edited global configuration variable '%s'", name);
  return true, "Global configuration modified";
end

--
-- BOARD MANAGEMENT FUNCTIONS
--

local function valid_board_name(name)
  return (type(name) == "string") and (not name:match("[^a-z0-9]"))
         and (#name >= 1 and #name <= 8);
end

local function valid_board_title(title)
  return (type(title) == "string") and (#title >= 1 and #title <= 32);
end

local function valid_board_subtitle(subtitle)
  return (type(subtitle) == "string") and (#subtitle >= 0 and #subtitle <= 64);
end

function pico.board.create(name, title, subtitle)
  subtitle = subtitle or "";

  if not pico.account.current
     or pico.account.current["Type"] ~= "admin" then
    return false, "Action not permitted";
  elseif dbb("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return false, "Board already exists";
  elseif not valid_board_name(name) then
    return false, "Invalid board name";
  elseif not valid_board_title(name) then
    return false, "Invalid board title";
  elseif not valid_board_subtitle(subtitle) then
    return false, "Invalid board subtitle";
  end

  dbq("INSERT INTO Boards (Name, Title, Subtitle) VALUES (?, ?, ?)",
      name, title, subtitle);
  log(false, nil, "Created a new board: /%s/ - %s", name, title);
  return true, "Board created successfully";
end

function pico.board.delete(name, reason)
  if not pico.account.current
     or pico.account.current["Type"] ~= "admin" then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return false, "Board does not exist";
  end

  dbq("DELETE FROM Boards WHERE Name = ?", name);
  log(false, nil, "Deleted board /%s/ for reason: %s", name, reason);
  return true, "Board deleted successfully";
end

function pico.board.list()
  return dbq("SELECT Name, Title, Subtitle FROM Boards ORDER BY MaxPostNumber DESC");
end

function pico.board.exists(name)
  return dbb("SELECT TRUE FROM Boards WHERE Name = ?", name);
end

function pico.board.tbl(name)
  return db1("SELECT * FROM Boards WHERE Name = ?", name);
end

function pico.board.configure(board_tbl)
  if not pico.account.current
     or (pico.account.current["Type"] ~= "admin"
         and pico.account.current["Type"] ~= "bo")
     or (pico.account.current["Type"] == "bo"
         and board_tbl["Name"] ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  elseif not board_tbl then
    return false, "Board configuration not supplied";
  elseif not dbb("SELECT TRUE FROM Boards WHERE Name = ?", board_tbl["Name"]) then
    return false, "Board does not exist";
  end

  dbq("UPDATE Boards SET Title = ?, Subtitle = ?, Lock = ?, DisplayOverboard = ?, " ..
      "PostMaxFiles = ?, ThreadMinLength = ?, PostMaxLength = ?, PostMaxNewlines = ?, " ..
      "PostMaxDblNewlines = ?, TPHLimit = ?, PPHLimit = ?, ThreadCaptcha = ?, " ..
      "PostCaptcha = ?, CaptchaTriggerTPH = ?, CaptchaTriggerPPH = ?, " ..
      "BumpLimit = ?, PostLimit = ?, ThreadLimit = ? WHERE Name = ?",
      board_tbl["Title"],		board_tbl["Subtitle"],
      board_tbl["Lock"] or 0,		board_tbl["DisplayOverboard"] or 0,
      board_tbl["PostMaxFiles"],	board_tbl["ThreadMinLength"],	
      board_tbl["PostMaxLength"],	board_tbl["PostMaxNewlines"],
      board_tbl["PostMaxDblNewlines"],	board_tbl["TPHLimit"],
      board_tbl["PPHLimit"],		board_tbl["ThreadCaptcha"] or 0,
      board_tbl["PostCaptcha"] or 0,	board_tbl["CaptchaTriggerTPH"],
      board_tbl["CaptchaTriggerPPH"],	board_tbl["BumpLimit"],
      board_tbl["PostLimit"],		board_tbl["ThreadLimit"],
      board_tbl["Name"]);

  log(false, board_tbl["Name"], "Modified board configuration");
  return true, "Board configured successfully";
end

function pico.board.index(name, page)
  if not dbb("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return nil, "Board does not exist";
  end

  page = page or 1;
  local pagesize = pico.global.get("indexpagesize");
  local windowsize = pico.global.get("indexwindowsize");

  local index_tbl = {};
  local thread_ops = dbq("SELECT Board, Number, Date, LastBumpDate, Name, Email, Subject, " ..
                         "Comment, Sticky, Lock, Autosage, Cycle, ReplyCount FROM Posts " ..
                         "WHERE Board = ? AND Parent IS NULL ORDER BY Sticky DESC, LastBumpDate DESC LIMIT ? OFFSET ?",
                         name, pagesize, (page - 1) * pagesize);

  for i = 1, #thread_ops do
    index_tbl[i] = {};
    index_tbl[i][0] = thread_ops[i];
    index_tbl[i]["RepliesOmitted"] = thread_ops[i]["ReplyCount"] - windowsize;

    local tmp_tbl = dbq("SELECT Board, Number, Parent, Date, Name, Email, Subject, Comment FROM Posts " ..
                        "WHERE Board = ? AND Parent = ? ORDER BY Number DESC LIMIT ?",
                        thread_ops[i]["Board"], thread_ops[i]["Number"], windowsize);

    while #tmp_tbl > 0 do
      index_tbl[i][#index_tbl[i] + 1] = table.remove(tmp_tbl);
    end
  end

  return index_tbl;
end

function pico.board.catalog(name)
  if not dbb("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return nil, "Board does not exist";
  end

  return dbq("SELECT Posts.Number, Date, LastBumpDate, Subject, Comment, Sticky, Lock, Autosage, Cycle, ReplyCount, File " ..
             "FROM Posts LEFT JOIN FileRefs ON Posts.Board = FileRefs.Board AND Posts.Number = FileRefs.Number " ..
             "WHERE (Sequence = 1 OR Sequence IS NULL) AND Posts.Board = ? AND Parent IS NULL "..
             "ORDER BY Sticky DESC, LastBumpDate DESC, Posts.Number DESC LIMIT 1000", name);
end

function pico.board.overboard()
  return dbq("SELECT Posts.Board, Posts.Number, Date, LastBumpDate, Subject, Comment, Sticky, Lock, Autosage, Cycle, ReplyCount, File " ..
             "FROM Posts LEFT JOIN FileRefs ON Posts.Board = FileRefs.Board AND Posts.Number = FileRefs.Number " ..
             "WHERE (Sequence = 1 OR Sequence IS NULL) " ..
             "AND Posts.Board IN (SELECT Name FROM Boards WHERE DisplayOverboard = TRUE) " ..
             "AND Parent IS NULL ORDER BY LastBumpDate DESC LIMIT 100");
end

-- for this and the following stats functions, set board to nil (where applicable)
-- to get site-wide statistics.
-- To get number of posts per hour over the last 12 hours:
--   * interval = 1 (hour)
--   * intervals = 12 (12 hours)
-- To get number of posts per day over 1 week:
--   * interval = 24 (hours)
--   * intervals = 7 (7 * 24 hours = 1 week)
function pico.board.stats.threadrate(board, interval, intervals)
  return db1("SELECT (COUNT(*) / ?) AS Rate FROM Posts WHERE Board = ? AND Parent IS NULL AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
             intervals, board, interval * intervals)["Rate"];
end

function pico.board.stats.postrate(board, interval, intervals)
  return db1("SELECT (COUNT(*) / ?) AS Rate FROM Posts WHERE Board = ? AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
             intervals, board, interval * intervals)["Rate"];
end

function pico.board.stats.totalposts(board)
  return db1("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)["MaxPostNumber"];
end

--
-- FILE MANAGEMENT FUNCTIONS
--

-- return a file's extension based on its contents
local function identify_file(path)
  local fd = assert(io.open(path, "r"));
  local data = fd:read(128);
  fd:close();

  if data == nil or #data == 0 then
    return nil;
  end

  if data:sub(1,8) == "\x89PNG\x0D\x0A\x1A\x0A" then
    return "png";
  elseif data:sub(1,3) == "\xFF\xD8\xFF" then
    return "jpg";
  elseif data:sub(1,6) == "GIF87a"
      or data:sub(1,6) == "GIF89a" then
    return "gif";
  elseif data:find("DOCTYPE svg", 1, true)
      or data:find("<svg", 1, true) then
    return "svg";
  elseif data:sub(1,4) == "\x1A\x45\xDF\xA3" then
    return "webm";
  elseif data:sub(5,12) == "ftypmp42"
      or data:sub(5,12) == "ftypisom" then
    return "mp4";
  elseif data:sub(1,2) == "\xFF\xFB"
      or data:sub(1,3) == "ID3" then
    return "mp3";
  elseif data:sub(1,4) == "OggS" then
    return "ogg";
  elseif data:sub(1,4) == "fLaC" then
    return "flac";
  elseif data:sub(1,4) == "%PDF" then
    return "pdf";
  elseif data:sub(1,4) == "PK\x03\x04"
     and data:sub(31,58) == "mimetypeapplication/epub+zip" then
    return "epub";
  else
    return nil;
  end
end

-- return a file's extension based on its name
function pico.file.extension(hash)
  return hash:match("%.(.-)$");
end

-- return a file's media type based on its extension
function pico.file.class(extension)
  local lookup = {
    ["png"]  = "image",
    ["jpg"]  = "image",
    ["gif"]  = "image",
    ["svg"]  = "image",
    ["webm"] = "video",
    ["mp4"]  = "video",
    ["mp3"]  = "audio",
    ["ogg"]  = "audio",
    ["flac"] = "audio",
    ["pdf"]  = "document",
    ["epub"] = "document"
  };

  return lookup[extension] or extension;
end

-- Add a file to the media directory and return its hash reference.
-- Also add its information to the database.
function pico.file.add(path)
  local f = assert(io.open(path, "r"));
  local size = f:seek("end");
  local extension = identify_file(path);
  local class = pico.file.class(extension);
  f:seek("set");

  if size > max_filesize then
    return nil, "File too large";
  elseif not extension then
    return nil, "Could not identify file type";
  end

  local data = assert(f:read("*a"));
  local hash = sha512(data);
  local filename = hash .. "." .. extension;

  if dbb("SELECT TRUE FROM Files WHERE Name = ?", filename) then
    return filename, "File already existed and was not changed";
  end

  local newf = assert(io.open("media/" .. filename, "w"));
  assert(newf:write(data));
  newf:close();

  if class == "video" then
    os.execute("exec ffmpeg -i media/" .. filename .. " -ss 00:00:01.000 -vframes 1 -f image2 - |" ..
               "gm convert -strip - -filter Box -thumbnail 200x200 JPEG:media/thumb/" .. filename);
    os.execute("exec ffmpeg -i media/" .. filename .. " -ss 00:00:01.000 -vframes 1 -f image2 - |" ..
               "gm convert -flatten -strip - -filter Box -quality 60 " ..
               "-thumbnail 100x70 JPEG:media/icon/" .. filename);
  elseif class == "image" or extension == "pdf" then
    os.execute("exec gm convert -strip media/" .. filename .. (extension == "pdf" and "[0]" or "") ..
               " -filter Box -thumbnail 200x200 " .. ((extension == "pdf" or extension == "svg") and "PNG:" or "") ..
               "media/thumb/" .. filename);
    os.execute("exec gm convert -background '#222' -flatten -strip media/" .. filename ..
               "[0] -filter Box -quality 60 -thumbnail 100x70 JPEG:media/icon/" .. filename);
  end

  local width, height;
  if class == "image" or extension == "pdf" then
    local p = io.popen("gm identify -format '%w %h' media/" .. filename .. "[0]", "r");
    local dimensions = string.tokenize(p:read("*a"));
    p:close();

    width, height = tonumber(dimensions[1]), tonumber(dimensions[2]);
  elseif class == "video" then
    local p = io.popen("ffprobe -hide_banner media/" .. filename ..
                       " 2>&1 | grep 'Video:' | head -n1 | grep -o '[1-9][0-9]*x[1-9][0-9]*'", "r");
    local dimensions = string.tokenize(p:read("*a"), "x");
    p:close();

    width, height = tonumber(dimensions[1]), tonumber(dimensions[2]);
  end

  if (not width) or (not height) then
    width, height = nil;
  end

  dbq("INSERT INTO Files VALUES (?, ?, ?, ?)", filename, size, width, height);
  return filename, "File added successfully";
end

-- Delete a file from the media directory and remove its corresponding entries
-- in the database.
function pico.file.delete(hash, reason)
  if not pico.account.current
     or (pico.account.current["Type"] ~= "admin"
         and pico.account.current["Type"] ~= "gvol") then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM Files WHERE Name = ?", hash) then
    return false, "File does not exist";
  end

  dbq("DELETE FROM Files WHERE Name = ?", hash);  
  os.remove("media/" .. hash);
  os.remove("media/icon/" .. hash);
  os.remove("media/thumb/" .. hash);

  log(false, nil, "Deleted file %s from all boards for reason: %s", hash, reason);
  return true, "File deleted successfully";
end

-- list info of files belonging to a particular post
function pico.file.list(board, number)
  dbq("BEGIN TRANSACTION");
  local file_tbl = dbq("SELECT File FROM FileRefs WHERE Board = ? AND Number = ? ORDER BY Sequence ASC", board, number);
  local stmt = db:prepare("SELECT * FROM Files WHERE Name = ?");

  for i = 1, #file_tbl do
    stmt:bind(1, file_tbl[i]["File"]);
    stmt:step();
    file_tbl[i] = stmt:get_named_values();
    stmt:reset();
  end

  stmt:finalize();
  dbq("END TRANSACTION");
  return file_tbl;
end

--
-- POST ACCESS, CREATION AND DELETION FUNCTIONS
--

function pico.post.recent(page)
  page = tonumber(page) or 1;
  local pagesize = pico.global.get("recentpagesize");
  return dbq("SELECT * FROM Posts ORDER BY Date DESC LIMIT ? OFFSET ?", pagesize, (page - 1) * pagesize);
end

function pico.post.tbl(board, number)
  return db1("SELECT * FROM Posts WHERE Board = ? AND Number = ?", board, number);
end

-- Return list of posts which >>reply to the specified post.
function pico.post.refs(board, number)
  local list = dbq("SELECT Referrer FROM Refs WHERE Board = ? AND Referee = ?", board, number);

  for i = 1, #list do
    list[i] = list[i]["Referrer"];
  end

  return list;
end

-- Return entire thread (parent + all replies) as a table
function pico.post.thread(board, number)
  if not dbb("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ? AND Parent IS NULL",
             board, number) then
    return nil, "Post is not a thread or does not exist";
  end

  local thread_tbl = dbq("SELECT Board, Number, Parent, Date, Name, Email, Subject, Comment FROM Posts " ..
                         "WHERE Board = ? AND Parent = ? ORDER BY Number",
                         board, number);
  thread_tbl[0] = db1("SELECT Board, Number, Date, LastBumpDate, Name, Email, Subject, " ..
                      "Comment, Sticky, Lock, Autosage, Cycle, ReplyCount FROM Posts " ..
                      "WHERE Board = ? AND Number = ?", board, number);
  return thread_tbl;
end

-- Create a post and return its number
-- 'files' is an array with a collection of file hashes to attach to the post
function pico.post.create(board, parent, name, email, subject, comment, files, captcha_id, captcha_text, bypasschecks)
  if bypasschecks == true
     and not (pico.account.current and pico.account.current["Board"] == nil) then
    return nil, "Action not permitted";
  end

  local board_tbl = pico.board.tbl(board);
  local parent_tbl = pico.post.tbl(board, parent);
  local is_thread = (not parent);

  name = (name ~= "") and name or pico.global.get("defaultpostname");
  email = email or "";
  subject = subject or "";
  comment = comment or "";

  if not bypasschecks then
    if not board_tbl then
      return nil, "Board does not exist";
    elseif not is_thread and not parent_tbl then
      return nil, "Parent thread does not exist";
    elseif not is_thread and parent_tbl["Parent"] then
      return nil, "Parent post is not a thread";
    elseif not is_thread and parent_tbl["Lock"] == 1
           and not (pico.account.current and (pico.account.current["Board"] == nil
                                              or pico.account.current["Board"] == board)) then
      return nil, "Parent thread is locked";
    elseif board_tbl["Lock"] == 1
           and not (pico.account.current and (pico.account.current["Board"] == nil
                                              or pico.account.current["Board"] == board)) then
      return nil, "Board is locked";
    elseif is_thread and board_tbl["TPHLimit"] > 0
           and pico.board.stats.threadrate(board, 1, 1) > board_tbl["TPHLimit"] then
      return nil, "Maximum thread creation rate exceeded";
    elseif board_tbl["PPHLimit"] > 0
           and pico.board.stats.postrate(board, 1, 1) > board_tbl["PPHLimit"] then
      return nil, "Maximum post creation rate exceeded";
    elseif is_thread and #comment < board_tbl["ThreadMinLength"] then
      return nil, "Thread text too short";
    elseif #comment > board_tbl["PostMaxLength"] then
      return nil, "Post text too long";
    elseif select(2, string.gsub(comment, "\r?\n", "")) > board_tbl["PostMaxNewlines"] then
      return nil, "Post contained too many newlines";
    elseif select(2, string.gsub(comment, "\r?\n\r?\n", "")) > board_tbl["PostMaxDblNewlines"] then
      return nil, "Post contained too many double newlines";
    elseif #name > 64 then
      return nil, "Name too long";
    elseif #email > 64 then
      return nil, "Email too long";
    elseif #subject > 64 then
      return nil, "Subject too long";
    elseif not is_thread and parent_tbl["Cycle"] ~= 1
           and parent_tbl["ReplyCount"] >= board_tbl["PostLimit"] then
      return nil, "Thread full";
    elseif (not files or #files == 0) and #comment == 0 then
      return nil, "Post is blank";
    elseif ((is_thread and board_tbl["ThreadCaptcha"] == 1) or (not is_thread and board_tbl["PostCaptcha"] == 1))
           and not checkcaptcha(captcha_id, captcha_text) then
      return nil, "Captcha is required but no valid captcha supplied";
    end
  end

  dbq("BEGIN TRANSACTION");
  dbq("INSERT INTO Posts (Board, Parent, Name, Email, Subject, Comment) " ..
      "VALUES (?, ?, ?, ?, ?, ?)", board, parent, name, email, subject, comment);
  local number = db1("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)["MaxPostNumber"];

  if files ~= nil then
    for i = 1, #files do
      if files[i] ~= "" then
        dbq("INSERT INTO FileRefs VALUES (?, ?, ?, ?)", board, number, files[i], i);
      end
    end
  end

  for ref in comment:gmatch(">>([0-9]+)") do
    ref = tonumber(ref);

    -- 1. Ensure that the reference doesn't already exist.
    -- 2. Ensure that the post being referred to does exist.
    -- 3. Ensure that the post being referred to is in the same thread as the referee.
    -- 4. Ensure that the post being referred to is not the same as the referrer.
    if ref ~= number then
      dbq("INSERT INTO Refs SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM Refs WHERE Board = ? AND Referee = ? AND Referrer = ?) = 0 " ..
          "AND (SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?) = TRUE " ..
          "AND ((SELECT Parent FROM Posts WHERE Board = ? AND Number = ?) = ? OR (? = ?))",
          board, ref, number, board, ref, number, board, ref, board, ref, parent, ref, tonumber(parent));
    end
  end

  dbq("END TRANSACTION");
  return number;
end

function pico.post.delete(board, number, reason)
  if not pico.account.current
     or (pico.account.current["Board"] ~= nil
         and board ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?", board, number) then
    return false, "Post does not exist";
  end

  dbq("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number);
  log(false, board, "Deleted post /%s/%d for reason: %s", board, number, reason);
  return true, "Post deleted successfully";
end

-- remove a file from a post without deleting it
function pico.post.unlink(board, number, file, reason)
  if not pico.account.current
     or (pico.account.current["Board"] ~= nil
         and board ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?",
                 board, number, file) then
    return false, "No such file in that particular post";
  end

  dbq("DELETE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?", board, number, file);
  log(false, board, "Unlinked file %s from /%s/%d for reason: %s",
      file, board, number, reason);
  return true, "File unlinked successfully";
end

-- toggle sticky, lock, autosage, or cycle
function pico.post.toggle(attribute, board, number, reason)
  if not pico.account.current
     or (pico.account.current["Board"] ~= nil
         and board ~= pico.account.current["Board"]) then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?", board, number) then
    return false, "Post does not exist";
  end

  if attribute == "sticky" then
    dbq("UPDATE Posts SET Sticky = NOT Sticky WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "lock" then
    dbq("UPDATE Posts SET Lock = NOT Lock WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "autosage" then
    dbq("UPDATE Posts SET Autosage = NOT Autosage WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "cycle" then
    dbq("UPDATE Posts SET Cycle = NOT Cycle WHERE Board = ? AND Number = ?", board, number);
  else
    return false, "Invalid attribute";
  end

  log(false, board, "Toggled attribute '%s' on /%s/%d for reason: %s",
      attribute, board, number, reason);
  return true, "Attribute toggled successfully";
end

-- 1. Fetch all contents of the thread.
-- 2. For each post of the thread, including the OP:
--    1. Rewrite references in the post's comment using the old->new lookup table.
--    2. Repost the post to the new board.
--    3. Keep a lookup table of the old post number and the new post number.
-- 3. Delete the old thread.
function pico.post.movethread(board, number, newboard, reason)
  if not pico.account.current
     or pico.account.current["Board"] ~= nil then
    return false, "Action not permitted";
  elseif not dbb("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ? AND Parent IS NULL", board, number) then
    return false, "Post does not exist or is not a thread";
  elseif not dbb("SELECT TRUE FROM Boards WHERE Name = ?", newboard) then
    return false, "Destination board does not exist";
  end

  local thread_tbl = pico.post.thread(board, number);
  local number_lut = {};
  local newthread;

  for i = 0, #thread_tbl do
    local post_tbl = thread_tbl[i];
    post_tbl["Comment"] = post_tbl["Comment"]:gsub(">>([0-9]+)", number_lut);
    post_tbl["Parent"] = post_tbl["Parent"] and newthread or nil;

    local files_tbl = pico.file.list(post_tbl["Board"], post_tbl["Number"]);
    for i = 1, #files_tbl do
      files_tbl[i] = files_tbl[i]["Name"];
    end

    local newnumber = pico.post.create(newboard, post_tbl["Parent"],
                                       post_tbl["Name"], post_tbl["Email"],
                                       post_tbl["Subject"], post_tbl["Comment"],
                                       files_tbl, nil, nil, true);
    number_lut[tostring(post_tbl["Number"])] = ">>" .. tostring(newnumber);

    if i == 0 then
      newthread = newnumber;
    end
  end

  dbq("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number);
  log(false, nil, "Moved thread /%s/%d to /%s/%d for reason: %s", board, number, newboard, newthread, reason);
  return true, "Thread moved successfully";
end

--
-- LOG ACCESS FUNCTIONS
--

function pico.log.retrieve(page)
  page = tonumber(page) or 1;
  pagesize = pico.global.get("logpagesize");
  return dbq("SELECT * FROM Logs ORDER BY ROWID DESC LIMIT ? OFFSET ?", pagesize, (page - 1) * pagesize);
end

--
-- CAPTCHA FUNCTIONS
--

-- return a captcha id and a base64 encoded image (jpeg)
function pico.captcha.create()
  local xx, yy, rr, ss, cc, bx, by = {},{},{},{},{},{},{};

  for i = 1, 6 do
    xx[i] = ((48 * i - 168) + math.random(-5, 5));
    yy[i] = math.random(-10, 10);
    rr[i] = math.random(-30, 30);
    ss[i] = math.random(-40, 40);
    cc[i] = string.random(1, "a-z");
    bx[i] = (150 + 1.1 * xx[i]);
    by[i] = (40 + 2 * yy[i]);
  end

  local p = assert(io.popen(string.format(
    "gm convert -size 290x70 xc:white -bordercolor black -border 5 " ..
    "-fill black -stroke black -strokewidth 1 -pointsize 40 " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-draw \"translate %d,%d rotate %d skewX %d gravity center text 0,0 '%s'\" " ..
    "-fill none -strokewidth 2 " ..
    "-draw 'bezier %f,%d %f,%d %f,%d %f,%d' " ..
    "-draw 'polyline %f,%d %f,%d %f,%d' -quality 1 JPEG:-",
    xx[1], yy[1], rr[1], ss[1], cc[1],
    xx[2], yy[2], rr[2], ss[2], cc[2],
    xx[3], yy[3], rr[3], ss[3], cc[3],
    xx[4], yy[4], rr[4], ss[4], cc[4],
    xx[5], yy[5], rr[5], ss[5], cc[5],
    xx[6], yy[6], rr[6], ss[6], cc[6],
    bx[1], by[1], bx[2], by[2], bx[3], by[3], bx[4], by[4],
    bx[4], by[4], bx[5], by[5], bx[6], by[6]
  ), "r"));

  local captcha_data = p:read("*a");
  p:close();

  local captcha_id = string.random(16);
  dbq("INSERT INTO Captchas VALUES (?, ?, STRFTIME('%s', 'now') + 900)", captcha_id, table.concat(cc));

  return captcha_id, string.base64(captcha_data);
end

return pico;
