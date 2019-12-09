-- Picochan Backend.
-- HAPAS ARE SUPERIOR TO WHITES

local sqlite3 = require("picoaux.sqlite3");
local crypto = require("picoaux.crypto");
local sha = require("picoaux.sha");

require("picoaux.stringmisc");

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
db:q("PRAGMA busy_timeout = 10000");
db:q("PRAGMA foreign_keys = ON");
db:q("PRAGMA recursive_triggers = ON");
db:q("PRAGMA secure_delete = ON");

local max_filesize = 16777216; -- 16 MiB. Users should not change.

--
-- MISCELLANEOUS FUNCTIONS
--

local function checkcaptcha(id, text)
  if db:b("SELECT TRUE FROM Captchas WHERE Id = ? AND Text = LOWER(?) AND ExpireDate > STRFTIME('%s', 'now')", id, text) then
    db:q("DELETE FROM Captchas WHERE ExpireDate <= STRFTIME('%s', 'now') OR Id = ?", id);
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
  db:q("INSERT INTO Logs (Account, Board, Description) VALUES (?, ?, ?)",
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

-- permclass is a space-separated list of one or more of the following:
--   admin gvol bo lvol
-- targettype may be one of the following:
--   acct board post
local function permit(permclass, targettype, targarg)
  -- STEP 1. Check account type
  if pico.account.current == nil then
    return false, "Action not permitted (not logged in)";
  elseif not permclass:match(pico.account.current["Type"]) then
    return false, "Action not permitted (account type not authorized)";
  end

  -- STEP 2. Check targets
  -- If no target, stop here
  if not targettype then
    return true;
  end

  -- Special case: Admin can modify any target
  if pico.account.current["Type"] == "admin" then
    return true;
  end

  if targettype == "acct" then
    -- Special case: Anyone can modify their own account (password change)
    if pico.account.current["Name"] == targarg then
      return true;
    end

    local account_tbl = db:r("SELECT Board FROM Accounts WHERE Name = ?", targarg);

    if pico.account.current["Type"] == "gvol" or pico.account.current["Type"] == "lvol" then
      return false, "Action not permitted (account type not authorized)";
    elseif pico.account.current["Type"] == "bo" then
      if account_tbl["Board"] == pico.account.current["Board"] then
        return true;
      else
        return false, "Action not permitted (attempt to modify account outside assigned board)";
      end
    end
  elseif targettype == "board" then
    if pico.account.current["Type"] == "gvol" or pico.account.current["Type"] == "lvol" then
      return false, "Action not permitted (account type not authorized)";
    elseif pico.account.current["Type"] == "bo" then
      if targarg == pico.account.current["Board"] then
        return true;
      else
        return false, "Action not permitted (attempt to modify non-assigned board)";
      end
    end
  elseif targettype == "post" then
    if pico.account.current["Type"] == "gvol" then
      return true;
    elseif (pico.account.current["Type"] == "bo")
        or (pico.account.current["Type"] == "lvol") then
      if targarg == pico.account.current["Board"] then
        return true;
      else
        return false, "Action not permitted (attempt to modify post outside assigned board)";
      end
    end
  end

  return false, "Action not permitted (unclassified denial: THIS IS A BUG, REPORT TO ADMINISTRATOR)";
end

function pico.account.create(name, password, type, board)
  local auth, msg = permit("admin bo", "board", board);
  if not auth then return auth, msg end;

  if not valid_account_name(name) then
    return false, "Account name is invalid";
  elseif not valid_account_type(type) then
    return false, "Account type is invalid";
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements";
  elseif db:b("SELECT TRUE FROM Accounts WHERE Name = ?", name) then
    return false, "Account already exists";
  elseif (type == "bo" or type == "lvol") then
    if not board then
      return false, "Board was not specified, but the account type requires it";
    elseif not db:b("SELECT TRUE FROM Boards WHERE Name = ?", board) then
      return false, "Account's specified board does not exist";
    end
  end

  if type == "admin" or type == "gvol" then
    board = nil;
  end

  db:q("INSERT INTO Accounts (Name, Type, Board, PwHash) VALUES (?, ?, ?, ?)",
      name, type, board, crypto.bcrypt.digest(password, pico.global.get("bcryptrounds")));
  log(false, board, "Created new %s account '%s'", type, name);
  return true, "Account created successfully";
end

function pico.account.delete(name, reason)
  local auth, msg = permit("admin bo", "acct", name);
  if not auth then return auth, msg end;

  local account_tbl = db:r("SELECT * FROM Accounts WHERE Name = ?", name);
  if not account_tbl then
    return false, "Account does not exist";
  end

  db:q("DELETE FROM Accounts WHERE Name = ?", name);
  log(false, account_tbl["Board"], "Deleted a %s account '%s' for reason: %s",
                  account_tbl["Type"], account_tbl["Name"], reason);
  return true, "Account deleted successfully";
end

function pico.account.changepass(name, password)
  local auth, msg = permit("admin gvol bo lvol", "acct", name);
  if not auth then return auth, msg end;

  local account_tbl = db:r("SELECT * FROM Accounts WHERE Name = ?", name);

  if not account_tbl then
    return false, "Account does not exist";
  elseif not valid_account_password(password) then
    return false, "Account password does not meet requirements";
  end

  db:q("UPDATE Accounts SET PwHash = ? WHERE Name = ?",
       crypto.bcrypt.digest(password, pico.global.get("bcryptrounds")), name);
  log(false, account_tbl["Board"], "Changed password of account '%s'", name);
  return true, "Account password changed successfully";
end

-- log in an account. returns an authentication key which you can use to perform
-- mod-only actions.
function pico.account.login(name, password)
  if not db:b("SELECT TRUE FROM Accounts WHERE Name = ?", name)
  or not crypto.bcrypt.verify(password, db:r("SELECT PwHash FROM Accounts WHERE Name = ?", name)["PwHash"]) then
    return nil, "Invalid username or password";
  end

  local key = string.random(16, "a-zA-Z0-9");
  db:q("INSERT INTO Sessions (Key, Account) VALUES (?, ?)", key, name);

  pico.account.register_login(key);
  return key;
end

-- populate the account table using an authentication key (perhaps provided by a
-- session cookie, or by pico.account.login() above)
function pico.account.register_login(key)
  if pico.account.current ~= nil then
    pico.account.logout();
  end

  pico.account.current = db:r("SELECT * FROM Accounts WHERE Name = (SELECT Account FROM Sessions " ..
                              "WHERE Key = ? AND ExpireDate > STRFTIME('%s', 'now'))", key);
  db:q("UPDATE Sessions SET ExpireDate = STRFTIME('%s', 'now') + 86400 WHERE Key = ?", key);
end

function pico.account.logout()
  if not pico.account.current then
    return false, "No account logged in";
  end

  db:q("DELETE FROM Sessions WHERE Key = ?", key);
  return true, "Account logged out successfully";
end

function pico.account.exists(name)
  return db:b("SELECT TRUE FROM Accounts WHERE Name = ?", name);
end

--
-- GLOBAL CONFIGURATION FUNCTIONS
--

-- retrieve value of globalconfig variable or empty string if it doesn't exist
function pico.global.get(name)
  local row = db:r("SELECT Value FROM GlobalConfig WHERE Name = ?", name);
  return row and row["Value"] or "";
end

-- setting a globalconfig variable to nil removes it.
function pico.global.set(name, value)
  local auth, msg = permit("admin");
  if not auth then return auth, msg end;

  db:q("DELETE FROM GlobalConfig WHERE Name = ?", name);

  if value ~= nil then
    db:q("INSERT INTO GlobalConfig VALUES (?, ?)", name, value);
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
  local auth, msg = permit("admin");
  if not auth then return auth, msg end;

  subtitle = subtitle or "";

  if db:b("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return false, "Board already exists";
  elseif not valid_board_name(name) then
    return false, "Invalid board name";
  elseif not valid_board_title(name) then
    return false, "Invalid board title";
  elseif not valid_board_subtitle(subtitle) then
    return false, "Invalid board subtitle";
  end

  db:q("INSERT INTO Boards (Name, Title, Subtitle) VALUES (?, ?, ?)",
      name, title, subtitle);
  log(false, nil, "Created a new board: /%s/ - %s", name, title);
  return true, "Board created successfully";
end

function pico.board.delete(name, reason)
  local auth, msg = permit("admin");
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return false, "Board does not exist";
  end

  db:q("DELETE FROM Boards WHERE Name = ?", name);
  log(false, nil, "Deleted board /%s/ for reason: %s", name, reason);
  return true, "Board deleted successfully";
end

function pico.board.list()
  return db:q("SELECT Name, Title, Subtitle FROM Boards ORDER BY MaxPostNumber DESC");
end

function pico.board.exists(name)
  return db:b("SELECT TRUE FROM Boards WHERE Name = ?", name);
end

function pico.board.tbl(name)
  return db:r("SELECT * FROM Boards WHERE Name = ?", name);
end

function pico.board.configure(board_tbl)
  local auth, msg = permit("admin bo", "board", board_tbl["Name"]);
  if not auth then return auth, msg end;

  if not board_tbl then
    return false, "Board configuration not supplied";
  elseif not db:b("SELECT TRUE FROM Boards WHERE Name = ?", board_tbl["Name"]) then
    return false, "Board does not exist";
  end

  db:q("UPDATE Boards SET Title = ?, Subtitle = ?, Lock = ?, DisplayOverboard = ?, " ..
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
  if not db:b("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return nil, "Board does not exist";
  end

  page = page or 1;
  local pagesize = pico.global.get("indexpagesize");
  local windowsize = pico.global.get("indexwindowsize");

  local index_tbl = {};
  local thread_ops = db:q("SELECT Board, Number, Date, LastBumpDate, Name, Email, Subject, " ..
                         "Comment, Sticky, Lock, Autosage, Cycle, ReplyCount FROM Posts " ..
                         "WHERE Board = ? AND Parent IS NULL ORDER BY Sticky DESC, LastBumpDate DESC LIMIT ? OFFSET ?",
                         name, pagesize, (page - 1) * pagesize);

  for i = 1, #thread_ops do
    index_tbl[i] = {};
    index_tbl[i][0] = thread_ops[i];
    index_tbl[i]["RepliesOmitted"] = thread_ops[i]["ReplyCount"] - windowsize;

    local tmp_tbl = db:q("SELECT Board, Number, Parent, Date, Name, Email, Subject, Comment FROM Posts " ..
                        "WHERE Board = ? AND Parent = ? ORDER BY Number DESC LIMIT ?",
                        thread_ops[i]["Board"], thread_ops[i]["Number"], windowsize);

    while #tmp_tbl > 0 do
      index_tbl[i][#index_tbl[i] + 1] = table.remove(tmp_tbl);
    end

    for j = 0, #index_tbl[i] do
      index_tbl[i][j]["Files"] = pico.file.list(index_tbl[i][j]["Board"], index_tbl[i][j]["Number"]);
    end
  end

  return index_tbl;
end

function pico.board.catalog(name)
  if not db:b("SELECT TRUE FROM Boards WHERE Name = ?", name) then
    return nil, "Board does not exist";
  end

  return db:q("SELECT Posts.Board, Posts.Number, Date, LastBumpDate, Subject, Comment, Sticky, Lock, Autosage, Cycle, ReplyCount, File " ..
             "FROM Posts LEFT JOIN FileRefs ON Posts.Board = FileRefs.Board AND Posts.Number = FileRefs.Number " ..
             "WHERE (Sequence = 1 OR Sequence IS NULL) AND Posts.Board = ? AND Parent IS NULL "..
             "ORDER BY Sticky DESC, LastBumpDate DESC, Posts.Number DESC LIMIT 1000", name);
end

function pico.board.overboard()
  return db:q("SELECT Posts.Board, Posts.Number, Date, LastBumpDate, Subject, Comment, Sticky, Lock, Autosage, Cycle, ReplyCount, File " ..
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
  return math.ceil(db:r("SELECT (COUNT(*) / ?) AS Rate FROM Posts WHERE Board = ? AND Parent IS NULL AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
                        intervals, board, interval * intervals)["Rate"]);
end

function pico.board.stats.postrate(board, interval, intervals)
  return math.ceil(db:r("SELECT (COUNT(*) / ?) AS Rate FROM Posts WHERE Board = ? AND Date > (STRFTIME('%s', 'now') - (? * 3600))",
                        intervals, board, interval * intervals)["Rate"]);
end

function pico.board.stats.totalposts(board)
  return db:r("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)["MaxPostNumber"];
end

--
-- FILE MANAGEMENT FUNCTIONS
--

-- return a file's extension based on its contents
local function identify_file(data)
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
  elseif data:sub(1, 4) == "RIFF"
     and data:sub(9, 12) == "WEBP" then
    return "webp";
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
  elseif not data:find("[^%w%s%p]") then
    return "txt";
  else
    return nil;
  end
end

-- return a file's extension based on its name
function pico.file.extension(hash)
  return hash:match("%.([^.]-)$");
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
    ["epub"] = "document",
    ["txt"]  = "document"
  };

  return lookup[extension] or extension;
end

-- Add a file to the media directory and return its hash reference.
-- Also add its information to the database.
function pico.file.add(path)
  local f = assert(io.open(path, "r"));
  local size = assert(f:seek("end"));

  if size > max_filesize then
    f:close()
    return nil, "File too large";
  end

  assert(f:seek("set"));
  local data = assert(f:read("*a"));
  f:close()

  local extension = identify_file(data);
  if not extension then
    return nil, "Could not identify file type";
  end

  local class = pico.file.class(extension);
  local hash = sha.hash("sha512", data);
  local filename = hash .. "." .. extension;

  if db:b("SELECT TRUE FROM Files WHERE Name = ?", filename) then
    return filename, "File already existed and was not changed";
  end

  local newf = assert(io.open("Media/" .. filename, "w"));
  assert(newf:write(data));
  newf:close();

  local width, height;
  if class == "video" then
    os.execute("exec ffmpeg -i Media/" .. filename .. " -ss 00:00:01.000 -vframes 1 -f image2 - |" ..
               "gm convert -strip - -filter Box -thumbnail 200x200 JPEG:Media/thumb/" .. filename);
    os.execute("exec ffmpeg -i Media/" .. filename .. " -ss 00:00:01.000 -vframes 1 -f image2 - |" ..
               "gm convert -flatten -strip - -filter Box -quality 60 " ..
               "-thumbnail 100x70 JPEG:Media/icon/" .. filename);

    local p = io.popen("ffprobe -hide_banner Media/" .. filename ..
                       " 2>&1 | grep 'Video:' | head -n1 | grep -o '[1-9][0-9]*x[1-9][0-9]*'", "r");
    local dimensions = string.tokenize(p:read("*a"), "x");
    p:close();

    width, height = tonumber(dimensions[1]), tonumber(dimensions[2]);
  elseif class == "image" or extension == "pdf" then
    os.execute("exec gm convert -strip Media/" .. filename .. (extension == "pdf" and "[0]" or "") ..
               " -filter Box -thumbnail 200x200 " .. ((extension == "pdf" or extension == "svg") and "PNG:" or "") ..
               "Media/thumb/" .. filename);
    os.execute("exec gm convert -background '#222' -flatten -strip Media/" .. filename ..
               "[0] -filter Box -quality 60 -thumbnail 100x70 JPEG:Media/icon/" .. filename);

    local p = io.popen("gm identify -format '%w %h' Media/" .. filename .. "[0]", "r");
    local dimensions = string.tokenize(p:read("*a"));
    p:close();

    width, height = tonumber(dimensions[1]), tonumber(dimensions[2]);
  end

  if (not width) or (not height) then
    width, height = nil;
  end

  db:q("INSERT INTO Files VALUES (?, ?, ?, ?)", filename, size, width, height);
  return filename, "File added successfully";
end

-- Delete a file from the media directory and remove its corresponding entries
-- in the database.
function pico.file.delete(hash, reason)
  local auth, msg = permit("admin gvol");
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM Files WHERE Name = ?", hash) then
    return false, "File does not exist";
  end

  db:q("DELETE FROM Files WHERE Name = ?", hash);
  os.remove("Media/" .. hash);
  os.remove("Media/icon/" .. hash);
  os.remove("Media/thumb/" .. hash);

  log(false, nil, "Deleted file %s from all boards for reason: %s", hash, reason);
  return true, "File deleted successfully";
end

function pico.file.list(board, number)
  return db:q("SELECT Files.* From FileRefs JOIN Files ON FileRefs.File=Files.Name " ..
              "WHERE FileRefs.Board = ? AND FileRefs.Number = ? ORDER BY FileRefs.Sequence ASC",
              board, number);
end

--
-- POST ACCESS, CREATION AND DELETION FUNCTIONS
--

function pico.post.recent(page)
  page = tonumber(page) or 1;
  local pagesize = pico.global.get("recentpagesize");
  local recent_tbl = db:q("SELECT * FROM Posts ORDER BY Date DESC LIMIT ? OFFSET ?", pagesize, (page - 1) * pagesize);
  for i = 1, #recent_tbl do
    recent_tbl[i]["Files"] = pico.file.list(recent_tbl[i]["Board"], recent_tbl[i]["Number"]);
  end
  return recent_tbl;
end

function pico.post.tbl(board, number, omit_files)
  local post_tbl = db:r("SELECT * FROM Posts WHERE Board = ? AND Number = ?", board, number);
  if post_tbl and not omit_files then
    post_tbl["Files"] = pico.file.list(board, number);
  end
  return post_tbl;
end

-- Return list of posts which >>reply to the specified post.
function pico.post.refs(board, number)
  local list = db:q("SELECT Referrer FROM Refs WHERE Board = ? AND Referee = ?", board, number);
  for i = 1, #list do
    list[i] = list[i]["Referrer"];
  end
  return list;
end

-- Return entire thread (parent + all replies + all file info) as a table
function pico.post.thread(board, number)
  if not db:b("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ? AND Parent IS NULL",
             board, number) then
    return nil, "Post is not a thread or does not exist";
  end

  local thread_tbl = db:q("SELECT Board, Number, Parent, Date, Name, Email, Subject, Comment FROM Posts " ..
                          "WHERE Board = ? AND Parent = ? ORDER BY Number ASC", board, number);
  thread_tbl[0] = db:r("SELECT Board, Number, Date, LastBumpDate, Name, Email, Subject, " ..
                       "Comment, Sticky, Lock, Autosage, Cycle, ReplyCount FROM Posts " ..
                       "WHERE Board = ? AND Number = ?", board, number);
  local stmt = db:prepare("SELECT Files.* From FileRefs JOIN Files ON FileRefs.File=Files.Name " ..
                          "WHERE FileRefs.Board = ? AND FileRefs.Number = ? ORDER BY FileRefs.Sequence ASC");
  db:q("BEGIN TRANSACTION");

  for i = 0, #thread_tbl do
    local post_tbl = thread_tbl[i];
    post_tbl["Files"] = {};
    stmt:bind_values(post_tbl["Board"], post_tbl["Number"]);
    while stmt:step() == sqlite3.ROW do
      post_tbl["Files"][#post_tbl["Files"] + 1] = stmt:get_named_values();
    end
    stmt:reset();
  end

  db:q("END TRANSACTION");
  stmt:finalize();
  return thread_tbl;
end

-- Create a post and return its number
-- 'files' is an array with a collection of file hashes to attach to the post
function pico.post.create(board, parent, name, email, subject, comment, files, captcha_id, captcha_text, bypasschecks)
  if bypasschecks == true then
    local auth, msg = permit("admin gvol");
    if not auth then return auth, msg end;
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
    elseif not is_thread and parent_tbl["Lock"] == 1 and not permit("admin gvol bo lvol", "post", board) then
      return nil, "Parent thread is locked";
    elseif not is_thread and parent_tbl["Cycle"] ~= 1
           and parent_tbl["ReplyCount"] >= board_tbl["PostLimit"] then
      return nil, "Thread full";
    elseif is_thread and board_tbl["TPHLimit"] > 0
           and pico.board.stats.threadrate(board, 1, 1) > board_tbl["TPHLimit"] then
      return nil, "Maximum thread creation rate exceeded";
    elseif is_thread and #comment < board_tbl["ThreadMinLength"] then
      return nil, "Thread text too short";
    elseif board_tbl["Lock"] == 1 and not permit("admin gvol bo lvol", "board", board) then
      return nil, "Board is locked";
    elseif board_tbl["PPHLimit"] > 0
           and pico.board.stats.postrate(board, 1, 1) > board_tbl["PPHLimit"] then
      return nil, "Maximum post creation rate exceeded";
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
    elseif (not files or #files == 0) and #comment == 0 then
      return nil, "Post is blank";
    elseif ((is_thread and board_tbl["ThreadCaptcha"] == 1) or (not is_thread and board_tbl["PostCaptcha"] == 1))
           and not checkcaptcha(captcha_id, captcha_text) then
      return nil, "Captcha is required but no valid captcha supplied";
    end
  end

  db:q("BEGIN TRANSACTION");
  db:q("INSERT INTO Posts (Board, Parent, Name, Email, Subject, Comment) " ..
      "VALUES (?, ?, ?, ?, ?, ?)", board, parent, name, email, subject, comment);
  local number = db:r("SELECT MaxPostNumber FROM Boards WHERE Name = ?", board)["MaxPostNumber"];

  if files ~= nil then
    for i = 1, #files do
      if files[i] ~= "" then
        db:q("INSERT INTO FileRefs VALUES (?, ?, ?, ?)", board, number, files[i], i);
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
      db:q("INSERT INTO Refs SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM Refs WHERE Board = ? AND Referee = ? AND Referrer = ?) = 0 " ..
          "AND (SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?) = TRUE " ..
          "AND ((SELECT Parent FROM Posts WHERE Board = ? AND Number = ?) = ? OR (? = ?))",
          board, ref, number, board, ref, number, board, ref, board, ref, parent, ref, tonumber(parent));
    end
  end

  db:q("END TRANSACTION");
  return number;
end

function pico.post.delete(board, number, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board);
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?", board, number) then
    return false, "Post does not exist";
  end

  db:q("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number);
  log(false, board, "Deleted post /%s/%d for reason: %s", board, number, reason);
  return true, "Post deleted successfully";
end

-- example: pico.post.multidelete("b", "31-57 459-1000", "33 35 48 466", "spam")
function pico.post.multidelete(board, include, exclude, reason)
  local auth, msg = permit("admin bo", "board", board);
  if not auth then return auth, msg end;
  assert(include, "Invalid include parameter");

  if not db:b("SELECT TRUE FROM Boards WHERE Name = ?", board) then
    return false, "Board does not exist";
  end

  local sql = {"DELETE FROM Posts WHERE Board = ? AND (TRUE=FALSE"};
  local sqlp = {board};
  local inclist = (include or ""):tokenize();
  local exclist = (exclude or ""):tokenize();

  local function genspec(spec, sql, sqlp)
    if spec:match("-") then
      local start, finish = unpack(spec:tokenize("-"));
      start, finish = tonumber(start), tonumber(finish);
      if not start or not finish then
        return false, "Invalid range specification";
      end

      sql[#sql + 1] = "OR Number BETWEEN ? AND ?";
      sqlp[#sqlp + 1] = start;
      sqlp[#sqlp + 1] = finish;
    else
      local number = tonumber(spec);
      if not number then
        return false, "Invalid single specification";
      end

      sql[#sql + 1] = "OR Number = ?";
      sqlp[#sqlp + 1] = number;
    end
  end

  for i = 1, #inclist do genspec(inclist[i], sql, sqlp) end;
  sql[#sql + 1] = ") AND NOT (TRUE=FALSE";
  for i = 1, #exclist do genspec(exclist[i], sql, sqlp) end;
  sql[#sql + 1] = ")";

  db:q(table.concat(sql, " "), unpack(sqlp));
  log(false, board, "Deleted posts {%s} excluding {%s} for reason: %s", include, exclude, reason);
  return true, "Posts deleted successfully";
end

function pico.post.pattdelete(pattern, reason)
  local auth, msg = permit("admin");
  if not auth then return auth, msg end;
  if not pattern or #pattern < 6 then return false, "Invalid or too short include pattern" end;

  db:q("DELETE FROM Posts WHERE Comment LIKE ?", "%" .. pattern .. "%");
  log(false, board, "Deleted posts matching pattern '%%%s%%' for reason: %s", pattern, reason);
  return true, "Posts deleted successfully";
end

-- remove a file from a post without deleting it
function pico.post.unlink(board, number, file, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board);
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?",
                 board, number, file) then
    return false, "No such file in that particular post";
  end

  db:q("DELETE FROM FileRefs WHERE Board = ? AND Number = ? AND File = ?", board, number, file);
  log(false, board, "Unlinked file %s from /%s/%d for reason: %s",
      file, board, number, reason);
  return true, "File unlinked successfully";
end

-- toggle sticky, lock, autosage, or cycle
function pico.post.toggle(attribute, board, number, reason)
  local auth, msg = permit("admin gvol bo lvol", "post", board);
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ?", board, number) then
    return false, "Post does not exist";
  end

  if attribute == "sticky" then
    db:q("UPDATE Posts SET Sticky = NOT Sticky WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "lock" then
    db:q("UPDATE Posts SET Lock = NOT Lock WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "autosage" then
    db:q("UPDATE Posts SET Autosage = NOT Autosage WHERE Board = ? AND Number = ?", board, number);
  elseif attribute == "cycle" then
    db:q("UPDATE Posts SET Cycle = NOT Cycle WHERE Board = ? AND Number = ?", board, number);
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
  local auth, msg = permit("admin gvol", "post", board);
  if not auth then return auth, msg end;

  if not db:b("SELECT TRUE FROM Posts WHERE Board = ? AND Number = ? AND Parent IS NULL", board, number) then
    return false, "Post does not exist or is not a thread";
  elseif not db:b("SELECT TRUE FROM Boards WHERE Name = ?", newboard) then
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
    for j = 1, #post_tbl["Files"] do
      post_tbl["Files"][j] = post_tbl["Files"][j]["Name"];
    end

    local newnumber = pico.post.create(newboard, post_tbl["Parent"],
                                       post_tbl["Name"], post_tbl["Email"],
                                       post_tbl["Subject"], post_tbl["Comment"],
                                       post_tbl["Files"], nil, nil, true);
    number_lut[tostring(post_tbl["Number"])] = ">>" .. tostring(newnumber);

    if i == 0 then
      newthread = newnumber;
    end
  end

  db:q("DELETE FROM Posts WHERE Board = ? AND Number = ?", board, number);
  log(false, nil, "Moved thread /%s/%d to /%s/%d for reason: %s", board, number, newboard, newthread, reason);
  return true, "Thread moved successfully";
end

--
-- LOG ACCESS FUNCTIONS
--

function pico.log.retrieve(page)
  page = tonumber(page) or 1;
  pagesize = pico.global.get("logpagesize");
  return db:q("SELECT * FROM Logs ORDER BY ROWID DESC LIMIT ? OFFSET ?", pagesize, (page - 1) * pagesize);
end

--
-- CAPTCHA FUNCTIONS
--

-- return a captcha id and a base64 encoded image (jpeg)
function pico.captcha.create()
  local xx, yy, rr, ss, cc, bx, by = {},{},{},{},{},{},{};

  for i = 1, 6 do
    xx[i] = ((48 * i - 168) + crypto.arc4random(-5, 5));
    yy[i] = crypto.arc4random(-15, 15);
    rr[i] = crypto.arc4random(-30, 30);
    ss[i] = crypto.arc4random(-30, 30);
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
    "-fill none -strokewidth 3 " ..
    "-draw 'bezier %f,%d %f,%d %f,%d %f,%d' " ..
    "-draw 'polyline %f,%d %f,%d %f,%d' -quality 0 JPEG:-",
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
  db:q("INSERT INTO Captchas VALUES (?, ?, STRFTIME('%s', 'now') + 1200)", captcha_id, table.concat(cc));

  return captcha_id, string.base64(captcha_data);
end

return pico;
