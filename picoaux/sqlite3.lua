-- SQLite3 FFI bindings for LuaJIT.

local ffi = require("ffi");
      ffi.sqlite3 = ffi.load("sqlite3");
local sqlite = {};

ffi.cdef[[
  typedef struct sqlite3 sqlite3;
  typedef struct sqlite3_stmt sqlite3_stmt;

  static const int SQLITE_OPEN_READONLY = 0x00000001;
  static const int SQLITE_OPEN_READWRITE = 0x00000002;
  static const int SQLITE_OPEN_CREATE = 0x00000004;

  static const int SQLITE_OK = 0;
  static const int SQLITE_ROW = 100;
  static const int SQLITE_DONE = 101;

  static const int SQLITE_INTEGER = 1;
  static const int SQLITE_FLOAT = 2;
  static const int SQLITE_TEXT = 3;
  static const int SQLITE_BLOB = 4;
  static const int SQLITE_NULL = 5;

  int sqlite3_errcode(sqlite3 *db);
  const char *sqlite3_errmsg(sqlite3 *db);
  int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *zvfs);
  int sqlite3_busy_timeout(sqlite3 *db, int ms);
  int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbyte, sqlite3_stmt **stmt, const char **sqltail);
  int sqlite3_step(sqlite3_stmt *stmt);
  int sqlite3_reset(sqlite3_stmt *stmt);
  int sqlite3_finalize(sqlite3_stmt *stmt);
  int sqlite3_close_v2(sqlite3 *db);

  int sqlite3_bind_parameter_count(sqlite3_stmt *stmt);
  int sqlite3_bind_int(sqlite3_stmt *stmt, int column, int value);
  int sqlite3_bind_double(sqlite3_stmt *stmt, int column, double value);
  int sqlite3_bind_text(sqlite3_stmt *stmt, int column, const char *value, int length, void(*)(void *));
  int sqlite3_bind_null(sqlite3_stmt *stmt, int column);

  int sqlite3_data_count(sqlite3_stmt *stmt);
  const char *sqlite3_column_name(sqlite3_stmt *stmt, int column);
  int sqlite3_column_type(sqlite3_stmt *stmt, int column);
  int sqlite3_column_bytes(sqlite3_stmt *stmt, int column);
  double sqlite3_column_double(sqlite3_stmt *stmt, int column);
  const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int column);
]];

sqlite.READONLY = ffi.sqlite3.SQLITE_OPEN_READONLY;
sqlite.READWRITE = ffi.sqlite3.SQLITE_OPEN_READWRITE;
sqlite.CREATE = ffi.sqlite3.SQLITE_OPEN_CREATE;
sqlite.OK = ffi.sqlite3.SQLITE_OK;
sqlite.ROW = ffi.sqlite3.SQLITE_ROW;
sqlite.DONE = ffi.sqlite3.SQLITE_DONE;

local new_db = ffi.typeof("sqlite3 *[1]");
local new_stmt = ffi.typeof("sqlite3_stmt *[1]");

local metatable_db = {};
local metatable_stmt = {};
metatable_db.__index = metatable_db;
metatable_stmt.__index = metatable_stmt;

local modes = {
  r = sqlite.READONLY,
  w = sqlite.READWRITE,
  c = sqlite.READWRITE + sqlite.CREATE
};

--
-- GLOBAL FUNCTIONS
--

function sqlite.open(path, mode)
  assert(type(path) == "string", "incorrect datatype for parameter 'path'");
  assert(modes[mode or "c"], "invalid value for parameter 'mode'");

  local db = new_db();
  local err = ffi.sqlite3.sqlite3_open_v2(path, db, modes[mode or "c"], nil);
  db = db[0];

  if err ~= sqlite.OK then
    return nil, ffi.string(ffi.sqlite3.sqlite3_errmsg(db)), ffi.sqlite3.sqlite3_errcode(db);
  end

  return setmetatable({db = db}, metatable_db);
end

--
-- DATABASE METHODS
--

function metatable_db:busy_timeout(ms)
  return ffi.sqlite3.sqlite3_busy_timeout(self.db, ms);
end

function metatable_db:errmsg()
  return ffi.string(ffi.sqlite3.sqlite3_errmsg(self.db));
end

function metatable_db:errcode()
  return ffi.sqlite3.sqlite3_errcode(self.db);
end

function metatable_db:prepare(sql)
  assert(type(sql) == "string", "incorrect datatype for parameter 'sql'");

  local stmt = new_stmt();
  local err = ffi.sqlite3.sqlite3_prepare_v2(self.db, sql, -1, stmt, nil);

  if err ~= sqlite.OK then
    return nil, self:errmsg(), self:errcode();
  else
    stmt = stmt[0];
  end

  return setmetatable({db = self.db, stmt = stmt}, metatable_stmt);
end

-- The following six functions are quick convenience functions which accept
-- variable arguments. These functions call error() upon failure.

-- Return a table of rows.
-- e.g. t[1]["Name"], t[1]["Address"], t[2]["Name"]
function metatable_db:q(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  local rows = {};
  while stmt:step() == sqlite.ROW do
    rows[#rows + 1] = stmt:get_named_values();
  end

  stmt:finalize();
  return rows;
end

-- Return a table of the first column of each row
function metatable_db:q1(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  local values = {};
  while stmt:step() == sqlite.ROW do
    values[#values + 1] = stmt:get_value(1);
  end

  stmt:finalize();
  return values;
end

-- Return the first row, or nil if there are none.
-- e.g. t["Name"], t["Address"]
function metatable_db:r(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  ret = stmt:step();
  local row;
  if ret == sqlite.ROW then
    row = stmt:get_named_values();
  elseif ret ~= sqlite.DONE then
    error(self:errmsg(), 2);
  end

  stmt:finalize();
  return row;
end

-- Return the first column of the first row, or nil if there are none.
function metatable_db:r1(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  ret = stmt:step();
  local value;
  if ret == sqlite.ROW then
    value = stmt:get_value(1);
  elseif ret ~= sqlite.DONE then
    error(self:errmsg(), 2);
  end

  stmt:finalize();
  return value;
end

-- Return a boolean: true if result rows were produced by the SQL statement
-- and false if not.
-- e.g. db:b("SELECT TRUE FROM Customers WHERE Name = ?", "James") would
--      return true if there is a customer named James, or false otherwise.
function metatable_db:b(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  ret = stmt:step();
  stmt:finalize();

  if ret == sqlite.ROW then
    return true;
  elseif ret == sqlite.DONE then
    return false;
  else
    error(self:errmsg(), 2);
  end
end

-- Return nothing
function metatable_db:e(sql, ...)
  local stmt, errmsg = self:prepare(sql);
  if not stmt then
    error(errmsg, 2);
  end

  local ret = stmt:bind_values(...);
  if ret ~= sqlite.OK then
    error(self:errmsg(), 2);
  end

  ret = stmt:step();
  if ret ~= sqlite.ROW and ret ~= sqlite.DONE then
    error(self:errmsg(), 2);
  end
  stmt:finalize();
end

--
-- STATEMENT METHODS
--

local coltypes_bind = {
  ["string"] = ffi.sqlite3.sqlite3_bind_text,
  ["number"] = ffi.sqlite3.sqlite3_bind_double,
  ["boolean"] = ffi.sqlite3.sqlite3_bind_int,
  ["nil"] = ffi.sqlite3.sqlite3_bind_null
};

function metatable_stmt:bind(column, value)
  assert(type(column) == "number", "incorrect datatype for parameter 'column'");
  local type = type(value);
  assert(coltypes_bind[type], "incorrect datatype for parameter 'value'");

  if type == "string" then
    return coltypes_bind[type](self.stmt, column, value, #value, ffi.cast("void *", 0));
  elseif value == nil then
    return coltypes_bind[type](self.stmt, column);
  else
    return coltypes_bind[type](self.stmt, column, value);
  end
end

function metatable_stmt:bind_values(...)
  for i = 1, select("#", ...) do
    if self:bind(i, select(i, ...)) ~= sqlite.OK then
      return err;
    end
  end

  return sqlite.OK;
end

function metatable_stmt:step()
  return ffi.sqlite3.sqlite3_step(self.stmt);
end

function metatable_stmt:columns()
  return ffi.sqlite3.sqlite3_data_count(self.stmt);
end

function metatable_stmt:get_name(column)
  return ffi.string(ffi.sqlite3.sqlite3_column_name(self.stmt, column - 1));
end

function metatable_stmt:get_value(column)
  local type = ffi.sqlite3.sqlite3_column_type(self.stmt, column - 1);

  if type == ffi.sqlite3.SQLITE_INTEGER or
     type == ffi.sqlite3.SQLITE_FLOAT then
    return ffi.sqlite3.sqlite3_column_double(self.stmt, column - 1);
  elseif type == ffi.sqlite3.SQLITE_TEXT or
         type == ffi.sqlite3.SQLITE_BLOB then
    return ffi.string(ffi.sqlite3.sqlite3_column_text(self.stmt, column - 1));
  elseif type == ffi.sqlite3.SQLITE_NULL then
    return nil;
  end
end

function metatable_stmt:get_named_values()
  local ret = {};

  for i = 1, self:columns() do
    ret[self:get_name(i)] = self:get_value(i);
  end

  return ret;
end

function metatable_stmt:reset()
  return ffi.sqlite3.sqlite3_reset(self.stmt);
end

function metatable_stmt:finalize()
  return ffi.sqlite3.sqlite3_finalize(self.stmt);
end

return sqlite;
