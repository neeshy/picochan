local ffi = require("ffi");
local null = {};

ffi.cdef[[
  typedef struct cJSON {
    struct cJSON *next, *prev;
    struct cJSON *child;
    int type;
    char *valuestring;
    int valueint;
    double valuedouble;
    char *string;
  } cJSON;

  cJSON *cJSON_Parse(const char *value);
  char  *cJSON_Print(cJSON *item);
  char  *cJSON_PrintUnformatted(cJSON *item);
  void   cJSON_Delete(cJSON *c);
  int    cJSON_GetArraySize(cJSON *array);
  cJSON *cJSON_CreateNull(void);
  cJSON *cJSON_CreateTrue(void);
  cJSON *cJSON_CreateFalse(void);
  cJSON *cJSON_CreateBool(int b);
  cJSON *cJSON_CreateNumber(double num);
  cJSON *cJSON_CreateString(const char *string);
  cJSON *cJSON_CreateArray(void);
  cJSON *cJSON_CreateObject(void);
  void   cJSON_AddItemToArray(cJSON *array, cJSON *item);
  void   cJSON_AddItemToObject(cJSON *object,const char *string,cJSON *item);
  void   cJSON_Minify(char *json);
  void   free(void *ptr);
]]

if not pcall(require, "table.new") then
  function table.new()
    return {};
  end
end

local cjson = ffi.load("cjson");
local json = table.new(0, 6);
local char_t = ffi.typeof("char[?]");
local mt_arr = { __index = { __jsontype = "array"  }};
local mt_obj = { __index = { __jsontype = "object" }};

local function is_array(t)
    local m, c = 0, 0;

    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 0 or floor(k) ~= k then return false end;
        m = math.max(m, k);
        c = c + 1;
    end

    return c == m;
end

function json.decval(j)
    local t = j.type;
    if t == 1 then return false end;
    if t == 2 then return true end;
    if t == 4 then return null end;
    if t == 8 then return j.valuedouble end;
    if t == 16 then return ffi.string(j.valuestring) end;
    if t == 32 then return setmetatable(json.parse(j.child, table.new(cjson.cJSON_GetArraySize(j), 0)) or {}, mt_arr) end;
    if t == 64 then return setmetatable(json.parse(j.child, table.new(0, cjson.cJSON_GetArraySize(j))) or {}, mt_obj) end;
    return nil;
end

function json.parse(j, r)
    if j == nil then return nil end;
    local c = j;

    repeat
        r[c.string ~= nil and ffi.string(c.string) or #r + 1] = json.decval(c);
        c = c.next;
    until c == nil

    return r;
end

function json.decode(value)
    if type(value) ~= "string" then return value end;
    local j = ffi.gc(cjson.cJSON_Parse(value), cjson.cJSON_Delete);
    if j == nil then return nil end;
    local t = j.type;
    if t == 5 then return setmetatable(json.parse(j.child, table.new(cjson.cJSON_GetArraySize(j), 0)) or {}, mt_arr) end;
    if t == 6 then return setmetatable(json.parse(j.child, table.new(0, cjson.cJSON_GetArraySize(j))) or {}, mt_obj) end;
    return json.decval(j);
end

function json.encval(value)
  local t = type(value);

  if t == "string" then
    return cjson.cJSON_CreateString(value);
  elseif t == "number" then
    if value ~= value then
      return error("nan is not allowed in JSON");
    elseif value == math.huge or value == -math.huge then
      return error("inf is not allowed in JSON");
    else
      return cjson.cJSON_CreateNumber(value);
    end
  elseif t == "boolean" then
    return value and cjson.cJSON_CreateTrue() or cjson.cJSON_CreateFalse();
  elseif t == "table" then
    if next(value) == nil then
      return (getmetatable(value) ~= mt_obj and is_array(value))
             and cjson.cJSON_CreateArray() or cjson.cJSON_CreateObject();
    end

    if getmetatable(value) ~= mt_obj and is_array(value) then
      local j = cjson.cJSON_CreateArray();
      for _, v in ipairs(value) do
        cjson.cJSON_AddItemToArray(j, json.encval(v));
      end
      return j;
    end

    local j = cjson.cJSON_CreateObject();

    for k, v in pairs(value) do
      cjson.cJSON_AddItemToObject(j, type(k) ~= "string" and tostring(k) or k, json.encval(v));
    end

    return j;
  else
    return cjson.cJSON_CreateNull();
  end
end

function json.encode(value, formatted)
  local j = ffi.gc(json.encval(value), cjson.cJSON_Delete);
  if j == nil then return nil end;
  return (formatted ~= false) and ffi.string(ffi.gc(cjson.cJSON_PrintUnformatted(j), ffi.C.free))
                               or ffi.string(ffi.gc(cjson.cJSON_Print(j), ffi.C.free));
end

function json.minify(value)
  local t = type(value) ~= "string" and json.encode(value) or value;
  local m = ffi.new(char_t, #t, t);
  cjson.cJSON_Minify(m);
  return ffi.string(m);
end

return {
  decode = json.decode,
  encode = json.encode,
  minify = json.minify,
  array  = mt_arr,
  object = mt_obj,
  null   = null
};
