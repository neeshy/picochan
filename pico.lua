#!/usr/local/bin/haserl -u16384
<% -- Picochan CGI/HTML Frontend
-- HAPAS ARE SUPERIOR TO WHITES

local cgi = require("picoaux.cgi");
local pico = require("picoengine");
local json = require("picoaux.json");
local request = require("picoaux.request");
local date = require("picoaux.date");

local html = {};
      html.table = {};
      html.list = {};
      html.container = {};
      html.form = {};

--
-- INITIALIZATION
--

if jit.os == "BSD" then
  -- The following pledge and unveil configuration was tested on an OpenBSD 6.6 system.
  local openbsd = require("picoaux.openbsd");
  openbsd.unveil("./picochan.db", "rw");
  openbsd.unveil("./picochan.db-journal", "rwc");
  openbsd.unveil("./Media/", "rwxc");
  openbsd.unveil("/dev/urandom", "r");
  openbsd.unveil("/tmp/", "rwc");
  openbsd.unveil("/usr/local/", "x");
  openbsd.unveil("/bin/sh", "x");
  openbsd.pledge("stdio rpath wpath cpath fattr flock proc exec prot_exec inet dns");
end

local sitename = pico.global.get("sitename");
pico.account.register_login(COOKIE["session_key"]);

cgi.initialize();

local function printf(...)
  cgi.outputbuf[#cgi.outputbuf + 1] = string.format(...);
end

local function thumbsize(w, h, mw, mh)
  return math.min(w, mw, math.floor(w / h * mh + 0.5)), math.min(h, mh, math.floor(h / w * mw + 0.5));
end

--
-- HTML FUNCTIONS
--

function html.begin(...)
  local title = string.format(...);
  title = title and (title .. " - ") or "";

  printf("<!DOCTYPE html>\n");
  printf("<html>");
  printf(  "<head>");
  printf(    "<title>%s%s</title>", title, sitename);
  printf(    "<link rel='stylesheet' type='text/css' href='/Static/picochan.css' />");
  printf(    "<link rel='shortcut icon' type='image/png' href='/Static/favicon.png' />");
  printf(    "<meta charset='utf-8' />");
  printf(    "<meta name='viewport' content='width=device-width, initial-scale=1.0' />");
  printf(  "</head>");
  printf(  "<body>");
  printf(    "<nav id='topbar'><ul>");
  printf(      "<li class='system'><a href='/' accesskey='`'>main</a></li>");
  printf(      "<li class='system'><a href='/Mod' accesskey='1'>mod</a></li>");
  printf(      "<li class='system'><a href='/Log' accesskey='2'>log</a></li>");
  printf(      "<li class='system'><a href='/Boards' accesskey='3'>boards</a></li>");
  printf(      "<li class='system'><a href='/Recent' accesskey='4'>recent</a></li>");
  printf(      "<li class='system'><a href='/Overboard' accesskey='5'>overboard</a></li>");

  local boards = pico.board.list();
  for i = 1, #boards do
    printf("<li class='board'><a href='/%s/' title='%s'>/%s/</a></li>",
           boards[i]["Name"], boards[i]["Title"], boards[i]["Name"]);
  end

  if pico.account.current then
    printf("<span id='logged-in-notification'>Logged in as <b>%s</b> <a href='/Mod/logout'>[Logout]</a></span>", pico.account.current["Name"]);
  end

  printf(    "</ul>");
  printf(    "<a class='invisible' href='' accesskey='r'></a>");
  printf(    "<a class='invisible' href='#postform' accesskey='p'></a>");
  printf(    "</nav>");
end

function html.finish()
  printf("<!-- %d ms generation time -->", os.clock() * 1000);
  printf("</html>");
end

function html.error(title, ...)
  cgi.outputbuf = {};
  html.begin("error");
  html.redheader(title);
  html.container.begin();
  printf(...);
  html.container.finish();
  html.finish();
  cgi.finalize();
end

function html.redheader(...)
  printf("<h1 class='redheader'>%s</h1>", string.format(...));
end

function html.announce()
  printf("<div id='announce'>%s</div>", pico.global.get("announce"));
end

function html.container.begin(width)
  printf("<div class='container %s'>", width or "narrow");
end

function html.container.finish()
  printf("</div>");
end

function html.container.barheader(...)
  printf("<h2 class='barheader'>%s</h2>", string.format(...));
end

function html.list.begin(class)
  printf("<".."%sl>", (class == "ordered") and "o" or "u");
end

function html.list.finish(class)
  printf("</%sl>", (class == "ordered") and "o" or "u");
end

function html.list.entry(...)
  printf("<li>%s</li>", string.format(...));
end

function html.table.begin(...)
  printf("<table><tr>");
  for i = 1, select("#", ...) do
    printf("<th>%s</th>", select(i, ...));
  end
  printf("</tr>");
end

function html.table.entry(...)
  printf("<tr>");
  for i = 1, select("#", ...) do
    printf("<td>%s</td>", select(i, ...));
  end
  printf("</tr>");
end

function html.table.finish()
  printf("</table>");
end

function html.date(timestamp, reldisplay)
  local difftime = os.time() - timestamp;
  local unit, multiple;
  local decimal = false;
  local reltime;

  if difftime >= (60 * 60 * 24 * 365) then
    unit = "year";
    multiple = difftime / (60 * 60 * 24 * 365);
    decimal = true;
  elseif difftime >= (60 * 60 * 24 * 30) then
    unit = "month";
    multiple = difftime / (60 * 60 * 24 * 30);
    decimal = true;
  elseif difftime >= (60 * 60 * 24 * 7) then
    unit = "week";
    multiple = difftime / (60 * 60 * 24 * 7);
  elseif difftime >= (60 * 60 * 24) then
    unit = "day";
    multiple = difftime / (60 * 60 * 24);
  elseif difftime >= (60 * 60) then
    unit = "hour";
    multiple = difftime / (60 * 60);
  elseif difftime >= (60) then
    unit = "minute";
    multiple = difftime / (60);
  else
    unit = "second";
    multiple = difftime;
  end

  if decimal then
    reltime = string.format("%.1f %s%s ago", multiple, unit, multiple == 1 and "" or "s");
  else
    multiple = math.floor(multiple);
    reltime = string.format("%d %s%s ago", multiple, unit, multiple == 1 and "" or "s");
  end

  return string.format("<time datetime='%s' title='%s'>%s</time>", os.date("!%F %T", timestamp),
                       reldisplay and os.date("!%F %T %Z %z", timestamp) or reltime,
                       reldisplay and reltime or os.date("!%F %T", timestamp));
end

function html.striphtml(s)
  s = tostring(s);
  local ret = s
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub("'", "&#39;")
    :gsub("\"", "&quot;");
  return ret;
end

function html.unstriphtml(s)
  s = tostring(s);
  local ret = s
    :gsub("\"", "&quot;")
    :gsub("&#39;", "'")
    :gsub("&gt;", ">")
    :gsub("&lt;", "<")
    :gsub("&amp;", "&");
  return ret;
end

function html.picofmt(post_tbl, disable_refs)
  if post_tbl["Email"] and post_tbl["Email"]:match("nofo") then
    return html.striphtml(post_tbl["Comment"]);
  end

  local function handle_refs(number)
    local ref_post_tbl = pico.post.tbl(post_tbl["Board"], number, true);

    if not ref_post_tbl then
      return string.format("<s><a class='reference'>&gt;&gt;%d</a></s>", number);
    else
      return string.format("<a class='reference' href='/%s/%d#%d'>&gt;&gt;%d</a>",
                           ref_post_tbl["Board"], ref_post_tbl["Parent"] or number, number, number);
    end
  end

  local function handle_xbrefs(board, number)
    if not tonumber(number) then
      return string.format("<a class='reference' href='/%s/'>&gt;&gt;&gt;/%s/</a>%s", board, board, number);
    end

    local ref_post_tbl = pico.post.tbl(board, number, true);

    if not ref_post_tbl then
      return string.format("<s><a class='reference'>&gt;&gt;&gt;/%s/%s</a></s>", board, number or "");
    else
      return string.format("<a class='reference' href='/%s/%d#%d'>&gt;&gt;&gt;/%s/%d</a>",
                           board, ref_post_tbl["Parent"] or number, number, board, number);
    end
  end

  local function handle_url(previous, url)
    local balance_tbl = {
      ["("] = ")",
      ["<"] = ">",
      ["{"] = "}",
      ["["] = "]"
    };
    url = html.unstriphtml(url);
    prev = html.unstriphtml(previous):sub(-1);
    local balance = balance_tbl[prev];
    local append = "";
    if balance then
      local i = 1;
      local count = 1;
      for c in url:gmatch(".") do
        if c == prev then
          count = count + 1;
        elseif c == balance then
          if count == 1 then
            append = url:sub(i);
            url = url:sub(1, i - 1);
            break;
          end
          count = count - 1;
        end
        i = i + 1;
      end
    end
    url = html.striphtml(url);
    append = html.striphtml(append);
    return string.format("%s<a href='%s'>%s</a>%s", previous, url, url, append);
  end

  local s = "\n" .. html.striphtml(post_tbl["Comment"]) .. "\n";

  if not disable_refs then
    s = s:gsub("&gt;&gt;&gt;/([%d%l]-)/(%d+)", handle_xbrefs);
    s = s:gsub("&gt;&gt;&gt;/([%d%l]-)/(%s)", handle_xbrefs);
    s = s:gsub("&gt;&gt;(%d+)", handle_refs);
  end

  s = s:gsub("(.?.?.?.)(https?://[a-zA-Z0-9%.%%%-%+%(%)_/=%?&;:,#~@]-[a-zA-Z0-9%.%%%-%+%(%)/%?&;:,#@])[^a-zA-Z0-9%.%%%-%+%(%)_/=%?&;:,#~@]", handle_url);
  s = s:gsub("&#39;&#39;&#39;([^\r\n]-)&#39;&#39;&#39;", "<b>%1</b>");
  s = s:gsub("&#39;&#39;([^\r\n]-)&#39;&#39;", "<i>%1</i>");
  s = s:gsub("~~([^\r\n]-)~~", "<s>%1</s>");
  s = s:gsub("__([^\r\n]-)__", "<u>%1</u>");
  s = s:gsub("==([^%s])==", "<span class='redtext'>%1</span>");
  s = s:gsub("==([^%s][^\r\n]-[^%s])==", "<span class='redtext'>%1</span>");
  s = s:gsub("%*%*([^\r\n]-)%*%*", "<span class='spoiler'>%1</span>");
  s = s:gsub("%(%(%([^\r\n]-%)%)%)", "<span class='kiketext'>%1</span>");
  s = s:gsub("([\r\n])(&gt;.-)([\r\n])", "%1<span class='greentext'>%2</span>%3");
  s = s:gsub("([\r\n])(&lt;.-)([\r\n])", "%1<span class='pinktext'>%2</span>%3");

  s = s:gsub("^[\r\n]+", "");
  s = s:gsub("[\r\n]+$", "");
  return s;
end

function html.modlinks(post_tbl)
  local board = post_tbl["Board"];
  local number = post_tbl["Number"];

  if (not pico.account.current)
     or (pico.account.current["Board"]
         and pico.account.current["Board"] ~= board) then
    return;
  end

  printf("<span class='mod-links'>");
  printf("<a href='/Mod/post/delete/%s/%d'>[D]</a>", board, number);

  if not post_tbl["Parent"] then
    printf("<a href='/Mod/post/move/%s/%d'>[M]</a>", board, number);
    printf("<a href='/Mod/post/sticky/%s/%d'>[S]</a>", board, number);
    printf("<a href='/Mod/post/lock/%s/%d'>[L]</a>", board, number);
    printf("<a href='/Mod/post/autosage/%s/%d'>[A]</a>", board, number);
    printf("<a href='/Mod/post/cycle/%s/%d'>[C]</a>", board, number);
  end

  printf("</span>");
end

function html.threadflags(post_tbl)
  if (post_tbl["Sticky"] == 1 or post_tbl["Lock"] == 1
      or post_tbl["Autosage"] == 1 or post_tbl["Cycle"] == 1) then
    printf("<span class='thread-flags'>");
    printf(" %s %s %s %s ",
      post_tbl["Sticky"]   == 1 and "<a title='Sticky'>&#x1f4cc;</a>"  or "",
      post_tbl["Lock"]     == 1 and "<a title='Lock'>&#x1f512;</a>"    or "",
      post_tbl["Autosage"] == 1 and "<a title='Autosage'>&#x2193;</a>" or "",
      post_tbl["Cycle"]    == 1 and "<a title='Cycle'>&#x27f3;</a>"    or "");
    printf("</span>");
  end
end

function html.renderpostfiles(post_tbl)
  local function formatfilesize(size)
    if size > (1024 * 1024) then
      return string.format("%.2f MiB", (size / 1024 / 1024));
    elseif size > 1024 then
      return string.format("%.2f KiB", (size / 1024));
    else
      return string.format("%d B", size);
    end
  end

  local file_tbl = post_tbl["Files"];
  local truncate = #file_tbl == 1 and 64 or 24;

  if file_tbl then
    for i = 1, #file_tbl do
      local file = file_tbl[i];
      local filename = file["Name"];
      local downloadname = file["DownloadName"];
      downloadname = (downloadname and downloadname ~= "") and downloadname:gsub("%.([^.]-)$", "") or filename;
      local spoiler = file["Spoiler"] == 1;
      local extension = pico.file.extension(filename);
      local class = pico.file.class(extension);

      printf("<div class='post-file%s'>", #file_tbl == 1 and "-single" or "");
      printf("<div class='post-file-info'>");
      printf("<a href='/Media/%s' title='Open file in new tab' target='_blank'>%s.%s</a><br />%s%s",
             filename, html.striphtml(#downloadname > truncate and downloadname:sub(1, truncate) .. ".." or downloadname), extension,
             formatfilesize(file["Size"]), file["Width"] and (" " .. file["Width"] .. "x" .. file["Height"]) or "");
      printf(" <a href='/Media/%s' title='Download file' download='%s.%s'>(dl)</a>", filename, html.striphtml(downloadname), extension);

      if pico.account.current and ((not pico.account.current["Board"])
                                   or (pico.account.current["Board"] == post_tbl["Board"])) then
        printf(" <span class='mod-links'>");
        printf("<a href='/Mod/post/unlink/%s/%d/%s' title='Unlink File'>[U]</a>",
               post_tbl["Board"], post_tbl["Number"], filename);
        printf("<a href='/Mod/post/spoiler/%s/%d/%s' title='Spoiler File'>[S]</a>",
               post_tbl["Board"], post_tbl["Number"], filename);
        printf("<a href='/Mod/post/unspoiler/%s/%d/%s' title='Unspoiler File'>[O]</a>",
               post_tbl["Board"], post_tbl["Number"], filename);

        if not pico.account.current["Board"] then
          printf("<a href='/Mod/file/delete/%s' title='Delete File'>[F]</a>",
                 filename);
        end

        printf("</span>");
      end

      printf("</div>");

      if extension == "svg" then
        printf("<a href='/Media/%s'><img class='post-file-thumbnail' src='/Media/thumb/%s' alt='[SVG]' /></a>", filename, filename);
      elseif class == "image" then
        printf("<style>input[type='checkbox']#%s-%d-%d:checked + img.post-file-thumbnail + div.post-file-fullsize::after " ..
               "{background-image: url('/Media/%s'); width: calc(90vh * (%d/%d)); height: calc(90vw * (%d/%d));}</style>",
               post_tbl["Board"], post_tbl["Number"], i,
               filename, file["Width"] or 0, file["Height"] or 0, file["Height"] or 0, file["Width"] or 0);

        printf("<label>");
        printf("<input id='%s-%d-%d' type='checkbox' hidden />", post_tbl["Board"], post_tbl["Number"], i);
        if spoiler then
          printf("<img class='post-file-thumbnail' src='/Static/spoiler.png' width=100 height=70 alt='[SPL]' />");
        else
          printf("<img class='post-file-thumbnail' src='/Media/thumb/%s' width='%d' height='%d' />",
                 filename, thumbsize(file["Width"] or 0, file["Height"] or 0, 200, 200));
        end
        printf("<div class='post-file-fullsize'></div>");
        printf("</label>");
      elseif spoiler then
        printf("<a href='/Media/%s'><image class='post-file-thumbnail' src='/Static/spoiler.png' width=100 height=70 alt='[SPL]' /></a>", filename);
      elseif extension == "pdf" then
        printf("<a href='/Media/%s'><img class='post-file-thumbnail' src='/Media/thumb/%s' width='%d' height='%d' alt='[PDF]' /></a>",
               filename, filename, thumbsize(file["Width"] or 200, file["Height"] or 200, 200, 200));
      elseif extension == "epub" then
        printf("<a href='/Media/%s'><img class='post-file-thumbnail' src='/Static/epub.png' width=100 height=70 alt='[EPUB]' /></a>", filename);
      elseif extension == "txt" then
        printf("<a href='/Media/%s' target='_blank'><img class='post-file-thumbnail' src='/Static/txt.png' width=100 height=70 alt='[TXT]' /></a>", filename);
      elseif class == "video" then
        printf("<video class='post-video' controls loop preload='none' src='/Media/%s' poster='/Media/thumb/%s'></video>", filename, filename);
      elseif class == "audio" then
        printf("<audio class='post-audio' controls loop preload='none' src='/Media/%s'></audio>", filename);
      end

      printf("</div>");
    end
  end
end

function html.renderpost(post_tbl, overboard, separate)
  printf("<div%s class='post-container'>",
         overboard and "" or string.format(" id='%d'", post_tbl["Number"]));
  printf("<div class='post%s'>", (separate or post_tbl["Parent"]) and "" or " thread");
  printf("<div class='post-header'>");

  if separate then
    printf("<span class='post-thread-link'>");
    if post_tbl["Parent"] then
      printf("<a href='/%s/%d'>/%s/%d</a>",
             post_tbl["Board"], post_tbl["Parent"], post_tbl["Board"], post_tbl["Parent"]);
    else
      printf("<a href='/%s/'>/%s/</a>", post_tbl["Board"], post_tbl["Board"]);
    end
    printf("</span>-&gt; ");
  end

  if post_tbl["Subject"] ~= "" then
    printf("<span class='post-subject'>%s</span>", html.striphtml(post_tbl["Subject"]));
  end

  printf("<span class='post-name'>");

  if post_tbl["Email"] ~= "" then
    printf("<a class='post-email' href='mailto:%s'>%s</a>",
           html.striphtml(post_tbl["Email"]), html.striphtml(post_tbl["Name"]));
  else
    printf("%s", html.striphtml(post_tbl["Name"]));
  end

  printf("</span>");
  printf("<span class='post-date'>%s</span>", html.date(post_tbl["Date"]));
  printf("<span class='post-number'><a href='/%s/%d#%d'>No.</a><a href='/%s/%d#postform'>%d</a></span>",
         post_tbl["Board"], post_tbl["Parent"] or post_tbl["Number"], post_tbl["Number"],
         post_tbl["Board"], post_tbl["Parent"] or post_tbl["Number"], post_tbl["Number"]);

  html.threadflags(post_tbl);
  html.modlinks(post_tbl);

  local reflist = pico.post.refs(post_tbl["Board"], post_tbl["Number"]);
  for i = 1, #reflist do
    printf("<a class='referrer' href='/%s/%d#%d'>&gt;&gt;%d</a> ",
           post_tbl["Board"], post_tbl["Parent"] or post_tbl["Number"], reflist[i], reflist[i]);
  end

  printf("</div>");
  html.renderpostfiles(post_tbl);
  printf("<div class='post-comment'>%s</div>", html.picofmt(post_tbl));
  printf("</div></div>");
end

function html.rendercatalog(catalog_tbl)
  printf("<div class='catalog-container'>");

  for i = 1, #catalog_tbl do
    local post_tbl = catalog_tbl[i];
    local board = post_tbl["Board"];
    local number = post_tbl["Number"];

    printf("<div class='catalog-thread'>");
    printf("<a class='catalog-thread-link' href='/%s/%d'>", board, number);

    if post_tbl["File"] then
      if post_tbl["Spoiler"] == 1 then
        printf("<img alt='***' src='/Static/spoiler.png' width=100 height=70 />");
      else
        local extension = pico.file.extension(post_tbl["File"]);
        local class = pico.file.class(extension);

        if class == "image" or class == "video" or extension == "pdf" then
          if post_tbl["FileWidth"] and post_tbl["FileHeight"] then
            printf("<img alt='***' src='/Media/icon/%s' width=%d height=%d />",
                   post_tbl["File"], thumbsize(post_tbl["FileWidth"], post_tbl["FileHeight"], 100, 70));
          else
            printf("<img alt='***' src='/Media/icon/%s' />", post_tbl["File"]);
          end
        elseif class == "audio" then
          printf("<img alt='***' src='/Static/audio.png' width=100 height=70 />");
        elseif extension == "epub" then
          printf("<img alt='***' src='/Static/epub.png' width=100 height=70 />");
        elseif extension == "txt" then
          printf("<img alt='***' src='/Static/txt.png' width=100 height=70 />");
        end
      end
    else
      printf("***");
    end

    printf("</a>");
    printf("<div class='catalog-thread-info'>");
    printf("<a href='/%s/'>/%s/</a> R:%d ", board, board, post_tbl["ReplyCount"]);
    html.threadflags(post_tbl);
    printf("</div>");

    printf("<div class='catalog-thread-lastbumpdate'>Bump: %s</div>", html.date(post_tbl["LastBumpDate"], true));
    printf("<div class='catalog-thread-subject'>%s</div>", html.striphtml(post_tbl["Subject"]));
    printf("<div class='catalog-thread-comment'>%s</div>", html.picofmt(post_tbl, true));

    printf("</div>");
  end

  printf("</div>");
end

function html.renderindex(index_tbl, board, page, prev, next)
  overboard = board == "Overboard";
  for i = 1, #index_tbl do
    printf("<div class='index-thread'>");
    html.renderpost(index_tbl[i][0], overboard);

    printf("<span class='index-thread-summary'>");
    if index_tbl[i]["RepliesOmitted"] > 0 then
      printf("%d replies omitted. ", index_tbl[i]["RepliesOmitted"]);
    end

    printf("Click <a href='/%s/%d'>here</a> to view full thread.", index_tbl[i][0]["Board"], index_tbl[i][0]["Number"]);
    printf("</span>");

    for j = 1, #index_tbl[i] do
      html.renderpost(index_tbl[i][j], overboard);
    end

    printf("</div><hr />");
  end

  printf("<div class='page-switcher'>");
  printf("<span class='page-switcher-curr'>Page: %d</span> ", page);
  if prev then
    printf("<a class='page-switcher-prev' href='/%s/index/%d'>[Prev]</a>", board, page - 1);
  end
  if next then
    printf("<a class='page-switcher-next' href='/%s/index/%d'>[Next]</a>", board, page + 1);
  end
  printf("</div>");
end

function html.brc(title, redheader)
  html.begin(title);
  html.redheader(redheader);
  html.container.begin();
end

function html.cfinish()
  html.container.finish();
  html.finish();
end

function html.form.postform(board_tbl, parent)
  printf("<fieldset><form id='postform' action='/Post' method='POST' enctype='multipart/form-data'>");
  printf(  "<input name='board' value='%s' type='hidden' />", board_tbl["Name"]);

  if parent ~= nil then
    printf("<input name='parent' value='%d' type='hidden' />", parent);
  end

  printf(  "<a class='close-button' href='##' accesskey='w'>[X]</a>");
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' maxlength=64 /><br />");
  printf(  "<label for='email'>Email</label><input id='email' name='email' type='text' maxlength=64 /><br />");
  printf(  "<label for='subject'>Subject</label><input id='subject' name='subject' type='text' maxlength=64 />");
  printf(  "<input type='submit' value='Post' accesskey='s' /><br />");
  printf(  "<label for='comment'>Comment</label><textarea id='comment' name='comment' form='postform' rows=5 cols=35 maxlength=%d></textarea><br />", board_tbl["PostMaxLength"]);

  for i = 1, board_tbl["PostMaxFiles"] do
    printf("<label for='file%d'>File %d</label><input id='file%d' name='file%d' type='file' />" ..
           "<label for='file%d_spoiler'>Spoiler</label><input id='file%d_spoiler' name='file%d_spoiler' type='checkbox' value=1 />%s",
           i, i, i, i, i, i, i, i ~= board_tbl["PostMaxFiles"] and "<br />" or "");
  end

  if parent == nil and board_tbl["ThreadCaptcha"] == 1
     or parent ~= nil and board_tbl["PostCaptcha"] == 1 then
    local captchaid, captchab64 = pico.captcha.create();

    printf("<input name='captchaid' value='%s' type='hidden' />", captchaid);
    printf("<br /><label for='captcha'>Captcha</label><input id='captcha' name='captcha' type='text' pattern='[a-zA-Z]{6}' maxlength=6 required /><br />");
    printf("<img id='captcha-image' src='data:image/jpeg;base64,%s' />", captchab64);
  end

  printf("</form></fieldset>");
end

function html.form.mod_login()
  printf("<fieldset><form method='POST'>");
  printf(  "<label for='username'>Username</label><input id='username' name='username' type='text' required autofocus /><br />");
  printf(  "<label for='password'>Password</label><input id='password' name='password' type='password' required /><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.board_create()
  printf("<fieldset><form method='POST'>");
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />");
  printf(  "<label for='title'>Title</label><input id='title' name='title' type='text' required /><br />");
  printf(  "<label for='subtitle'>Subtitle</label><input id='subtitle' name='subtitle' type='text' /><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Create' />");
  printf("</form></fieldset>");
end

function html.form.board_delete()
  printf("<fieldset><form method='POST'>");
  printf(  "<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />");
  printf(  "<label for='reason'>Reason</label><input id='reason' name='reason' type='text' /><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />");
  printf("</form></fieldset>");
end

function html.form.board_config_select()
  printf("<fieldset><form method='POST'>");
  printf(  "<label for='Name'>Name</label><input id='Name' name='Name' type='text' required autofocus /><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.board_config(board)
  local board_tbl = pico.board.tbl(board);

  printf("<fieldset><form method='POST'>");
  printf(  "<input type='hidden' name='Name' value='%s' />", board_tbl["Name"]);
  printf(  "<label for='Title'>Title</label><input id='Title' name='Title' type='text' value='%s' maxlength=32 required /><br />", html.striphtml(board_tbl["Title"]));
  printf(  "<label for='Subtitle'>Subtitle</label><input id='Subtitle' name='Subtitle' type='text' value='%s' maxlength=64 /><br />", html.striphtml(board_tbl["Subtitle"]));
  printf(  "<label for='Lock'>Lock</label><input id='Lock' name='Lock' type='checkbox' value=1 %s/><br />", board_tbl["Lock"] == 1 and "checked " or "");
  printf(  "<label for='DisplayOverboard'>DisplayOverboard</label><input id='DisplayOverboard' name='DisplayOverboard' type='checkbox' value=1 %s/><br />", board_tbl["DisplayOverboard"] == 1 and "checked " or "");
  printf(  "<label for='PostMaxFiles'>PostMaxFiles</label><input id='PostMaxFiles' name='PostMaxFiles' type='number' value='%d' min=0 max=5 required /><br />", board_tbl["PostMaxFiles"]);
  printf(  "<label for='ThreadMinLength'>ThreadMinLength</label><input id='ThreadMinLength' name='ThreadMinLength' type='number' value='%d' required /><br />", board_tbl["ThreadMinLength"]);
  printf(  "<label for='PostMaxLength'>PostMaxLength</label><input id='PostMaxLength' name='PostMaxLength' type='number' value='%d' required /><br />", board_tbl["PostMaxLength"]);
  printf(  "<label for='PostMaxNewlines'>PostMaxNewlines</label><input id='PostMaxNewlines' name='PostMaxNewlines' type='number' value='%d' required /><br />", board_tbl["PostMaxNewlines"]);
  printf(  "<label for='PostMaxDblNewlines'>PostMaxDblNewlines</label><input id='PostMaxDblNewlines' name='PostMaxDblNewlines' type='number' value='%d' required /><br />", board_tbl["PostMaxDblNewlines"]);
  printf(  "<label for='TPHLimit'>TPHLimit</label><input id='TPHLimit' name='TPHLimit' type='number' value='%d' required /><br />", board_tbl["TPHLimit"]);
  printf(  "<label for='PPHLimit'>PPHLimit</label><input id='PPHLimit' name='PPHLimit' type='number' value='%d' required /><br />", board_tbl["PPHLimit"]);
  printf(  "<label for='ThreadCaptcha'>ThreadCaptcha</label><input id='ThreadCaptcha' name='ThreadCaptcha' type='checkbox' value=1 %s/><br />", board_tbl["ThreadCaptcha"] == 1 and "checked " or "");
  printf(  "<label for='PostCaptcha'>PostCaptcha</label><input id='PostCaptcha' name='PostCaptcha' type='checkbox' value=1 %s/><br />", board_tbl["PostCaptcha"] == 1 and "checked " or "");
  printf(  "<label for='CaptchaTriggerTPH'>CaptchaTriggerTPH</label><input id='CaptchaTriggerTPH' name='CaptchaTriggerTPH' type='number' value='%d' required /><br />", board_tbl["CaptchaTriggerTPH"]);
  printf(  "<label for='CaptchaTriggerPPH'>CaptchaTriggerPPH</label><input id='CaptchaTriggerPPH' name='CaptchaTriggerPPH' type='number' value='%d' required /><br />", board_tbl["CaptchaTriggerPPH"]);
  printf(  "<label for='BumpLimit'>BumpLimit</label><input id='BumpLimit' name='BumpLimit' type='number' value='%d' min=0 max=1000 required /><br />", board_tbl["BumpLimit"]);
  printf(  "<label for='PostLimit'>PostLimit</label><input id='PostLimit' name='PostLimit' type='number' value='%d' min=0 max=1000 required /><br />", board_tbl["PostLimit"]);
  printf(  "<label for='ThreadLimit'>ThreadLimit</label><input id='ThreadLimit' name='ThreadLimit' type='number' value='%d' min=0 max=1000 required /><br />", board_tbl["ThreadLimit"]);
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Configure' />");
  printf("</form></fieldset>");
end

function html.form.account_create()
  printf("<fieldset><form id='account-create' method='POST'>");
  printf("<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />");
  printf("<label for='password'>Password</label><input id='password' name='password' type='password' pattern='.{6,128}' maxlength=128 required /><br />");
  printf("<label for='type'>Type</label><select form='account-create' id='type' name='type'>");
  printf(  "<option value='admin'>Administrator</option>");
  printf(  "<option value='bo'>Board Owner</option>");
  printf(  "<option value='gvol'>Global Volunteer</option>");
  printf(  "<option value='lvol' selected>Local Volunteer</option>");
  printf("</select><br />");
  printf("<label for='board'>Board</label><input id='board' name='board' type='text' /><br />");
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Create' />");
  printf("</form></fieldset>");
end

function html.form.account_delete()
  printf("<fieldset><form method='POST'>");
  printf("<label for='name'>Name</label><input id='name' name='name' type='text' required autofocus /><br />");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />");
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />");
  printf("</form></fieldset>");
end

function html.form.account_config()
  printf("<fieldset><form method='POST'>");
  printf("<label for='name'>Account</label><input id='name' name='name' type='text' value='%s' required /><br />", pico.account.current["Name"]);
  printf("<label for='password'>Password</label><input id='password' name='password' type='password' required /><br />");
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Change Password' />");
  printf("</form></fieldset>");
end

function html.form.endpoint_add()
  printf("<fieldset><form id='endpoint-add' method='POST'>");
  printf("<label for='endpoint'>Endpoint</label><input id='endpoint' name='endpoint' type='text' required autofocus /><br />");
  printf("<label for='type'>Type</label><select form='endpoint-add' id='type' name='type'>");
  printf(  "<option value='following' selected>Following</option>");
  printf(  "<option value='known'>Known Only</option>");
  printf(  "<option value='blacklist'>Blacklisted</option>");
  printf("</select><br />");
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Add' />");
  printf("</form></fieldset>");
end

function html.form.endpoint_remove()
  printf("<fieldset><form method='POST'>");
  printf("<label for='endpoint'>Endpoint</label><input id='endpoint' name='endpoint' type='text' required autofocus /><br />");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />");
  printf("<label for='submit'>Submit</label><input id='submit' type='submit' value='Delete' />");
  printf("</form></fieldset>");
end

function html.form.endpoint_config_select()
  printf("<fieldset><form method='POST'>");
  printf(  "<label for='Endpoint'>Endpoint</label><input id='Endpoint' name='Endpoint' type='text' required autofocus /><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.endpoint_config(endpoint)
  local endpoint_tbl = pico.webring.endpoint.tbl(endpoint);

  printf("<fieldset><form method='POST'>");
  printf(  "<input type='hidden' name='Endpoint' value='%s' />", html.striphtml(endpoint_tbl["Endpoint"]));
  printf(  "<label for='Type'>Type</label><select id='Type' name='Type'>");
  printf(    "<option value='following'%s>Following</option>", endpoint_tbl["Type"] == "following" and " selected" or "");
  printf(    "<option value='known'%s>Known Only</option>", endpoint_tbl["Type"] == "known" and " selected" or "");
  printf(    "<option value='blacklist'%s>Blacklisted</option>", endpoint_tbl["Type"] == "blacklist" and " selected" or "");
  printf(  "</select><br />");
  printf(  "<label for='submit'>Submit</label><input id='submit' type='submit' value='Configure' />");
  printf("</form></fieldset>");
end

function html.form.globalconfig(varname)
  printf("<fieldset><form id='globalconfig' method='POST'>");
  printf("<input type='hidden' name='name' value='%s' />", varname);
  printf("<label for='value'>%s</label>", varname);

  if varname == "frontpage" or varname == "announce" then
    printf("<textarea id='value' name='value' form='globalconfig' cols=40 rows=12 autofocus>%s</textarea>",
           html.striphtml(pico.global.get(varname)) or "");
  else
    printf("<input id='value' name='value' value='%s' type='text' autofocus />",
           html.striphtml(pico.global.get(varname)) or "");
  end
  printf("<br /><label for='submit'>Submit</label><input id='submit' type='submit' value='Set' />");
  printf("</form></fieldset>");
end

function html.form.mod_action_reason()
  printf("<fieldset><form method='POST'>");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required autofocus />");
  printf("<input type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.mod_move_thread()
  printf("<fieldset><form method='POST'>");
  printf("<label for='destination'>Destination</label><input id='destination' name='destination' type='text' required autofocus /><br />");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />");
  printf("<input type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.mod_multidelete()
  printf("<fieldset><form method='POST'>");
  printf("<label for='board'>Board</label><input id='board' name='board' type='text' required autofocus /><br />");
  printf("<label for='ispec'>Include</label><input id='ispec' name='ispec' type='text' required /><br />");
  printf("<label for='espec'>Exclude</label><input id='espec' name='espec' type='text' /><br />");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />");
  printf("<input type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

function html.form.mod_pattdelete()
  printf("<fieldset><form method='POST'>");
  printf("<label for='pattern'>Pattern</label><input id='pattern' name='pattern' type='text' required autofocus /><br />");
  printf("<label for='reason'>Reason</label><input id='reason' name='reason' type='text' required /><br />");
  printf("<input type='submit' value='Continue' />");
  printf("</form></fieldset>");
end

--
-- PAGE DEFINITIONS
--

cgi.headers["Content-Type"] = "text/html; charset=utf-8";
cgi.headers["Cache-Control"] = "no-cache";
cgi.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; media-src 'self'; prefetch-src 'self';";
cgi.headers["Referrer-Policy"] = "no-referrer";
cgi.headers["X-DNS-Prefetch-Control"] = "off";
cgi.headers["X-Frame-Options"] = "deny";

local handlers = {}

local function account_check()
  if not pico.account.current then
    cgi.headers["Status"] = "303 See Other";
    cgi.headers["Location"] = "/Mod/login";
    cgi.finalize();
  end
end

handlers["/"] = function()
  html.begin("welcome");
  html.redheader("Welcome to %s", sitename);
  html.container.begin();
  printf("%s", pico.global.get("frontpage") or "");
  html.container.finish();
  html.finish();
end;

handlers["/Mod"] = function()
  account_check();
  html.brc("dashboard", "Moderation Dashboard");
  printf("You are logged in as <b>%s</b>. Your account type is <b>%s</b>.",
         pico.account.current["Name"], pico.account.current["Type"]);
  html.container.barheader("Global");
  html.list.begin("unordered");
  html.list.entry("<a href='/Mod/global/announce'>Change global announcement</a>");
  html.list.entry("<a href='/Mod/global/sitename'>Change site name</a>");
  html.list.entry("<a href='/Mod/global/url'>Change site URL</a>");
  html.list.entry("<a href='/Mod/global/frontpage'>Change front-page content</a>");
  html.list.entry("<a href='/Mod/global/defaultpostname'>Change default post name</a>");
  html.list.entry("<a href='/Mod/global/indexpagesize'>Change index page size</a>");
  html.list.entry("<a href='/Mod/global/indexwindowsize'>Change index window size</a>");
  html.list.entry("<a href='/Mod/global/recentpagesize'>Change recent posts page size</a>");
  html.list.entry("<a href='/Mod/global/logpagesize'>Change mod log page size</a>");
  html.list.finish();
  html.container.barheader("Miscellaneous Tools");
  html.list.begin("unordered");
  html.list.entry("<a href='/Mod/tools/multidelete'>Multi-delete by range</a>");
  html.list.entry("<a href='/Mod/tools/pattdelete'>Pattern delete</a>");
  html.list.finish();
  html.container.barheader("Accounts");
  html.list.begin("unordered");
  html.list.entry("<a href='/Mod/account/create'>Create an account</a>");
  html.list.entry("<a href='/Mod/account/delete'>Delete an account</a>");
  html.list.entry("<a href='/Mod/account/config'>Configure an account</a>");
  html.list.finish();
  html.container.barheader("Boards");
  html.list.begin("unordered");
  html.list.entry("<a href='/Mod/board/create'>Create a board</a>");
  html.list.entry("<a href='/Mod/board/delete'>Delete a board</a>");
  html.list.entry("<a href='/Mod/board/config'>Configure a board</a>");
  html.list.finish();
  html.container.barheader("Webring");
  html.list.begin("unordered");
  html.list.entry("<a href='/Mod/webring/add'>Add a webring endpoint</a>");
  html.list.entry("<a href='/Mod/webring/remove'>Remove a webring endpoint</a>");
  html.list.entry("<a href='/Mod/webring/config'>Configure a webring endpoint</a>");
  html.list.finish();
  html.cfinish();
end;

handlers["/Mod/login"] = function()
  html.brc("login", "Moderator Login");

  if POST["username"] and POST["password"] then
    local session_key, errmsg = pico.account.login(POST["username"], POST["password"]);

    if not session_key then
      printf("Cannot log in: %s", errmsg);
    else
      cgi.headers["Set-Cookie"] = "session_key=" .. session_key .. "; HttpOnly; Path=/; SameSite=Strict";
      cgi.headers["Status"] = "303 See Other";
      cgi.headers["Location"] = "/Mod";
      cgi.finalize();
    end
  end

  html.form.mod_login();
  html.cfinish();
end;

handlers["/Mod/logout"] = function()
  account_check();
  pico.account.logout();
  cgi.headers["Set-Cookie"] = "session_key=; HttpOnly; Path=/; Expires=Thursday, 1 Jan 1970 00:00:00 GMT; SameSite=Strict";
  cgi.headers["Status"] = "303 See Other";
  cgi.headers["Location"] = "/Overboard";
  cgi.finalize();
end;

handlers["/Mod/global/([%l%d]+)"] = function(varname)
  account_check();
  html.brc("change global configuration", "Change global configuration");

  if POST["name"] then
    local result, msg;
    if POST["value"] == "" then
      result, msg = pico.global.set(POST["name"], nil);
    else
      result, msg = pico.global.set(POST["name"], POST["value"]);
    end

    printf("%s: %s", result and "Variable set" or "Cannot set variable", msg);
  end

  html.form.globalconfig(varname);
  html.cfinish();
end;

handlers["/Mod/account/create"] = function()
  account_check();
  html.brc("create account", "Create account");

  if POST["name"] ~= nil and POST["name"] ~= "" then
    printf("%s", select(2, pico.account.create(POST["name"], POST["password"], POST["type"], POST["board"])));
  end

  html.form.account_create();
  html.cfinish();
end;

handlers["/Mod/account/delete"] = function()
  account_check();
  html.brc("delete account", "Delete account");

  if POST["name"] and POST["reason"] then
    local status, msg = pico.account.delete(POST["name"], POST["reason"]);
    printf("%s%s", (not status) and "Cannot delete account: " or "", msg);
  end

  html.form.account_delete();
  html.cfinish();
end;

handlers["/Mod/account/config"] = function()
  account_check();
  html.brc("configure account", "Configure account");

  if POST["name"] and POST["password"] then
    printf("%s", select(2, pico.account.changepass(POST["name"], POST["password"])));
  end

  html.form.account_config();
  html.cfinish();
end;

handlers["/Mod/board/create"] = function()
  account_check();
  html.brc("create board", "Create board");

  if POST["name"] and POST["title"] and POST["subtitle"] then
    local status, msg = pico.board.create(POST["name"], POST["title"], POST["subtitle"]);
    printf("%s%s", (not status) and "Cannot create board: " or "", msg);
  end

  html.form.board_create();
  html.cfinish();
end;

handlers["/Mod/board/delete"] = function()
  account_check();
  html.brc("delete board", "Delete board");

  if POST["name"] and POST["reason"] then
    local status, msg = pico.board.delete(POST["name"], POST["reason"]);
    printf("%s%s", (not status) and "Cannot delete board: " or "", msg);
  end

  html.form.board_delete();
  html.cfinish();
end;

handlers["/Mod/board/config"] = function()
  account_check();
  html.brc("configure board", "Configure board");

  if POST["Name"] == nil or POST["Name"] == "" then
    html.form.board_config_select();
  elseif not pico.board.exists(POST["Name"]) then
    printf("Cannot configure board: Board does not exist");
    html.form.board_config_select();
  else
    if POST["Title"] then
      local status, msg = pico.board.configure(POST);
      printf("%s%s", (not status) and "Cannot configure board: " or "", msg);
    end

    html.form.board_config(POST["Name"]);
  end

  html.cfinish();
end;

handlers["/Mod/webring/add"] = function()
  account_check();
  html.brc("add webring endpoint", "Add webring endpoint");

  if POST["endpoint"] and POST["type"] then
    local status, msg = pico.webring.endpoint.add(POST["endpoint"], POST["type"]);
    printf("%s%s", (not status) and "Cannot add webring endpoint: " or "", msg);
  end

  html.form.endpoint_add();
end;

handlers["/Mod/webring/remove"] = function()
  account_check();
  html.brc("remove webring endpoint", "Remove webring endpoint");

  if POST["endpoint"] and POST["reason"] then
    local status, msg = pico.webring.endpoint.remove(POST["endpoint"], POST["reason"]);
    printf("%s%s", (not status) and "Cannot remove webring endpoint: " or "", msg);
  end

  html.form.endpoint_remove();
end;

handlers["/Mod/webring/config"] = function()
  account_check();
  html.brc("configure webring endpoint", "Configure webring endpoint");

  if POST["Endpoint"] == nil or POST["Endpoint"] == "" then
    html.form.endpoint_config_select();
  elseif not pico.webring.endpoint.exists(POST["Endpoint"]) then
    printf("Cannot configure webring endpoint: Endpoint does not exist");
    html.form.endpoint_config_select();
  else
    if POST["Type"] then
      local status, msg = pico.webring.endpoint.configure(POST);
      printf("%s%s", (not status) and "Cannot configure webring endpoint: " or "", msg);
    end

    html.form.endpoint_config(POST["Endpoint"]);
  end

  html.cfinish();
end;

handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"] = function(operation, board, post, file)
  account_check();
  html.begin("%s post", operation);
  html.redheader("Modify or Delete a Post");
  html.container.begin();

  local board_tbl = pico.board.tbl(board);
  local post_tbl, msg = pico.post.tbl(board, post);
  if not post_tbl then
    html.error("Action failed", "Cannot find post: %s", msg);
  end

  if POST["reason"] and POST["reason"] ~= "" then
    local result, msg;

    if operation == "delete" then
      result, msg = pico.post.delete(board, post, POST["reason"]);
    elseif operation == "unlink" then
      result, msg = pico.post.unlink(board, post, file, POST["reason"]);
    elseif operation == "spoiler" then
      result, msg = pico.post.spoiler(board, post, file, true, POST["reason"]);
    elseif operation == "unspoiler" then
      result, msg = pico.post.spoiler(board, post, file, false, POST["reason"]);
    elseif operation == "move" then
      result, msg = pico.post.movethread(board, post, POST["destination"], POST["reason"]);
    else
      result, msg = pico.post.toggle(operation, board, post, POST["reason"]);
    end

    if not result then
      html.error("Action failed", "Backend returned error: %s", msg);
    else
      cgi.headers["Status"] = "303 See Other";

      if operation == "move" then
        cgi.headers["Location"] = "/" .. POST["destination"];
      else
        cgi.headers["Location"] =
          post_tbl["Parent"] and ("/" .. board_tbl["Name"] .. "/" .. post_tbl["Parent"])
                              or ("/" .. board_tbl["Name"] .. "/" .. post_tbl["Number"]);
      end

      cgi.finalize();
    end
  end

  printf("You are about to <b>%s</b>%s the following post:", operation,
         (operation == "unlink" or operation == "spoiler" or operation == "unspoiler") and
         " " .. file .. " from" or "");
  html.renderpost(post_tbl, true, true);

  if operation == "move" then
    html.form.mod_move_thread();
  else
    html.form.mod_action_reason();
  end

  html.cfinish();
end;

handlers["/Mod/post/(unlink)/([%l%d]+)/(%d+)/([%l%d.]+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(spoiler)/([%l%d]+)/(%d+)/([%l%d.]+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(unspoiler)/([%l%d]+)/(%d+)/([%l%d.]+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(move)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(sticky)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(lock)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(autosage)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];
handlers["/Mod/post/(cycle)/([%l%d]+)/(%d+)"] = handlers["/Mod/post/(delete)/([%l%d]+)/(%d+)"];

handlers["/Mod/tools/multidelete"] = function()
  account_check();
  html.brc("multidelete", "Multidelete");

  if POST["board"] then
    local result, msg = pico.post.multidelete(POST["board"], POST["ispec"], POST["espec"], POST["reason"]);
    printf("%s", msg);
  end

  html.form.mod_multidelete();
  html.cfinish();
end;

handlers["/Mod/tools/pattdelete"] = function()
  account_check();
  html.brc("pattern delete", "Pattern delete");

  if POST["pattern"] then
    local result, msg = pico.post.pattdelete(POST["pattern"], POST["reason"]);
    printf("%s", msg);
  end

  html.form.mod_pattdelete();
  html.cfinish();
end;

handlers["/Mod/file/delete/([%l%d.]+)"] = function(file)
  account_check();
  html.brc("delete file", "Delete file");

  if POST["reason"] and POST["reason"] ~= "" then
    local result, msg = pico.file.delete(file, POST["reason"]);

    if not result then
      html.error("Action failed", "Backend returned error: %s", msg);
    else
      cgi.headers["Status"] = "303 See Other";
      cgi.headers["Location"] = "/Overboard";
      cgi.finalize();
    end
  end

  printf("You are about to <b>delete</b> the file %s from <i>all boards</i>.", file);
  html.form.mod_action_reason();
  html.cfinish();
end;

handlers["/Log"] = function(page)
  html.begin("logs");
  html.redheader("Moderation Logs");
  html.container.begin("wide");

  page = tonumber(page) or 1;
  if page <= 0 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too low: %s", page);
  end

  local log_tbl = pico.log.retrieve(page);
  if #log_tbl == 0 and page ~= 1 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too high: %s", page);
  end

  prev = page > 1
  next = #log_tbl == pico.global.get("logpagesize") and #pico.log.retrieve(page + 1) ~= 0;

  printf("<div class='page-switcher'>");
  if prev then
    printf("<a class='page-switcher-prev' href='/Log/%d'>[Prev]</a>", page - 1);
  else
    printf("[Prev]");
  end
  if next then
    printf("<a class='page-switcher-next' href='/Log/%d'>[Next]</a>", page + 1);
  end
  printf("</div>");
  html.table.begin("Account", "Board", "Date", "Description");

  for i = 1, #log_tbl do
    local entry = log_tbl[i];
    html.table.entry(entry["Account"] == "SYSTEM" and "<i>SYSTEM</i>" or entry["Account"],
                     entry["Board"] == "GLOBAL" and "<i>GLOBAL</i>" or string.format("<a href='/%s/'>/%s/</a>", entry["Board"], entry["Board"]),
                     html.date(entry["Date"]),
                     html.striphtml(entry["Description"]));
  end

  html.table.finish();
  printf("<div class='page-switcher'>");
  if prev then
    printf("<a class='page-switcher-prev' href='/Log/%d'>[Prev]</a>", page - 1);
  else
    printf("[Prev]");
  end
  if next then
    printf("<a class='page-switcher-next' href='/Log/%d'>[Next]</a>", page + 1);
  end
  printf("</div>");
  html.cfinish();
end;

handlers["/Log/(%d+)"] = handlers["/Log"];

handlers["/Boards"] = function()
  local known = pico.webring.tbl()["known"];
  local webring_boards = {};

  for i = 1, #known do
    local response = request.send(known[i], {["timeout"] = 1});
    if response then
      local status = response["code"];
      if status == 200 or status == 301 then
        local status, boards = pcall(function()
          local webring = assert(json.decode(response["body"]));
          local site_name = assert(webring["name"]);
          local site_boards = assert(webring["boards"]);
          local boards = {};
          for j = 1, #site_boards do
            local board = {};
            board["site_name"] = site_name;
            board["name"] = html.striphtml(site_boards[j]["uri"]) or "";
            board["title"] = html.striphtml(site_boards[j]["title"]) or "";
            board["subtitle"] = html.striphtml(site_boards[j]["subtitle"]) or "";
            board["path"] = html.striphtml(site_boards[j]["path"]) or "";
            board["pph"] = html.striphtml(site_boards[j]["postsPerHour"]) or "";
            board["total"] = html.striphtml(site_boards[j]["totalPosts"]) or "";
            board["last"] = date.iso8601(site_boards[j]["lastPostTimestamp"]);
            board["last"] = board["last"] and html.date(board["last"], true) or "";

            boards[#boards + 1] = board;
          end
          return boards;
        end);
        if status then
          for j = 1, #boards do
            webring_boards[#webring_boards + 1] = boards[j];
          end
        end
      end
    end
  end

  html.begin("boards");
  html.redheader("Board List");
  html.container.begin("wide");
  if #webring_boards ~= 0 then
    html.container.barheader("Local Boards");
  end
  html.table.begin("Board", "Title", "Subtitle", "TPW (7d)", "TPD (1d)", "PPD (7d)", "PPD (1d)", "PPH (1h)", "Total Posts", "Last Activity");

  local g_tpw7d = 0;
  local g_tpd1d = 0;
  local g_ppd7d = 0;
  local g_ppd1d = 0;
  local g_pph1h = 0;
  local g_total = 0;
  local g_last = nil;
  local board_list_tbl = pico.board.list();
  for i = 1, #board_list_tbl do
    local board = board_list_tbl[i]["Name"];
    local title = board_list_tbl[i]["Title"];
    local subtitle = board_list_tbl[i]["Subtitle"];
    local tpw7d = pico.board.stats.threadrate(board, 24 * 7, 1);
    local tpd1d = pico.board.stats.threadrate(board, 24, 1);
    local ppd7d = pico.board.stats.postrate(board, 24, 7);
    local ppd1d = pico.board.stats.postrate(board, 24, 1);
    local pph1h = pico.board.stats.postrate(board, 1, 1);
    local total = pico.board.stats.totalposts(board);
    local last = pico.board.stats.lastbumpdate(board);

    g_tpw7d = g_tpw7d + tpw7d;
    g_tpd1d = g_tpd1d + tpd1d;
    g_ppd7d = g_ppd7d + ppd7d;
    g_ppd1d = g_ppd1d + ppd1d;
    g_pph1h = g_pph1h + pph1h;
    g_total = g_total + total;
    if not g_last then
      g_last = last;
    elseif last then
      g_last = math.max(g_last, last);
    end

    html.table.entry(string.format("<a href='/%s/' title='%s'>/%s/</a>", board, title, board),
                     title, subtitle, tpw7d, tpd1d, ppd7d, ppd1d, pph1h, total, last and html.date(last, true) or "");
  end

  html.table.entry("<i>GLOBAL</i>", "", "", g_tpw7d, g_tpd1d, g_ppd7d, g_ppd1d, g_pph1h, g_total, g_last and html.date(g_last, true) or "");
  html.table.finish();

  if #webring_boards ~= 0 then
    html.container.barheader("Webring Boards");
    html.table.begin("Board", "Title", "Subtitle", "PPH", "Total Posts", "Last Activity");
    for i = 1, #webring_boards do
      local board = webring_boards[i];
      html.table.entry(string.format("<a href='%s' title='%s'>%s/%s/</a>",
                       board["path"], board["title"], board["site_name"], board["name"]),
                       board["title"], board["subtitle"], board["pph"], board["total"], board["last"]);
    end
  end

  html.table.finish();
  html.cfinish();
end;

handlers["/Post"] = function()
  local files = {};

  -- step 1. add all the files of the post (if any) to pico's file registration
  for i = 1, 5 do
    local name = POST["file" .. i .. "_name"];
    if name and name ~= "" then
      local spoiler = POST["file" .. i .. "_spoiler"] and 1 or 0;

      local hash, msg = pico.file.add(HASERL["file" .. i .. "_path"]);
      if not hash then
        cgi.headers["Status"] = "400 Bad Request";
        html.error("File Upload Error", "Cannot add file #%d: %s", i, msg);
      end

      files[#files + 1] = {Name = name, Hash = hash, Spoiler = spoiler};
    end
  end

  -- step 2. create the post itself
  local number, msg = pico.post.create(
    POST["board"], tonumber(POST["parent"]),
    POST["name"], POST["email"], POST["subject"],
    POST["comment"], files,
    POST["captchaid"], POST["captcha"]
  );

  if not number then
    cgi.headers["Status"] = "400 Bad Request";
    html.error("Posting Error", "Cannot make post: %s", msg);
  end

  cgi.headers["Status"] = "303 See Other";

  if not POST["parent"] then
    cgi.headers["Location"] = "/" .. POST["board"] .. "/" .. number;
  else
    cgi.headers["Location"] = "/" .. POST["board"] .. "/" .. POST["parent"] .. "#" .. number;
  end
end;

local function overboard_header()
  html.begin("overboard");
  html.redheader("%s Overboard", sitename);
  html.announce();
  printf("<a href='/Overboard/catalog'>[Catalog]</a> <a href='/Overboard/index'>[Index]</a> <a href=''>[Update]</a><hr />");
end

handlers["/Overboard"] = function()
  overboard_header();
  html.rendercatalog(pico.board.overboard());
  html.finish();
end;

handlers["/Overboard/catalog"] = handlers["/Overboard"];

handlers["/Overboard/index"] = function(page)
  overboard_header();
  page = tonumber(page) or 1;

  if page <= 0 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too low: %s", page);
  end

  local index_tbl = pico.board.index(nil, page);
  if #index_tbl == 0 and page ~= 1 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too high: %s", page);
  end

  html.renderindex(index_tbl, "Overboard", page, page > 1,
    #index_tbl == pico.global.get("indexpagesize") and #pico.board.index(nil, page + 1) ~= 0);
  html.finish();
end;

handlers["/Overboard/index/(%d+)"] = handlers["/Overboard/index"];

handlers["/Recent"] = function(page)
  html.begin("recent posts");
  html.redheader("Recent Posts");
  html.announce();
  printf("<a href=''>[Update]</a><hr class='recent-page-separator' />");

  page = tonumber(page) or 1;
  if page <= 0 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too low: %s", page);
  end

  local recent_tbl = pico.post.recent(page);
  if #recent_tbl == 0 and page ~= 1 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too high: %s", page);
  end

  for i = 1, #recent_tbl do
    html.renderpost(recent_tbl[i], true, true);
    printf("<hr class='invisible-separator'>");
  end

  printf("<hr />");
  printf("<div class='page-switcher'>");
  printf("<span class='page-switcher-curr'>Page: %d</span> ", page);
  if page > 1 then
    printf("<a class='page-switcher-prev' href='/Recent/%d'>[Prev]</a>", page - 1);
  end
  if #recent_tbl == pico.global.get("recentpagesize") and #pico.post.recent(page + 1) ~= 0 then
    printf("<a class='page-switcher-next' href='/Recent/%d'>[Next]</a>", page + 1);
  end
  printf("</div>");
  html.finish();
end;

handlers["/Recent/(%d+)"] = handlers["/Recent"];

local function board_header(board_tbl)
  if not board_tbl then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Board Not Found", "The board you specified does not exist.");
  end

  html.begin("/%s/", board_tbl["Name"]);
  printf("<h1 id='boardtitle'>/%s/ - %s</h1>", board_tbl["Name"], html.striphtml(board_tbl["Title"]));
  printf("<h2 id='boardsubtitle'>%s</h2>", html.striphtml(board_tbl["Subtitle"]));
  html.announce();
  printf("<a id='new-post' href='#postform'>[Start a New Thread]</a>");
  html.form.postform(board_tbl, nil);
  printf("<a href='/%s/catalog'>[Catalog]</a> <a href='/%s/index'>[Index]</a> <a href=''>[Update]</a><hr />",
         board_tbl["Name"], board_tbl["Name"]);
end

handlers["/([%l%d]+)/?"] = function(board)
  local board_tbl = pico.board.tbl(board);
  board_header(board_tbl);
  html.rendercatalog(pico.board.catalog(board_tbl["Name"]));
  html.finish();
end;

handlers["/([%l%d]+)/catalog"] = handlers["/([%l%d]+)/?"];

handlers["/([%l%d]+)/index"] = function(board, page)
  local board_tbl = pico.board.tbl(board);
  board_header(board_tbl);
  page = tonumber(page) or 1;

  if page <= 0 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too low: %s", page);
  end

  local index_tbl = pico.board.index(board_tbl["Name"], page);
  if #index_tbl == 0 and page ~= 1 then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Page not found", "Page number too high: %s", page);
  end

  html.renderindex(index_tbl, board_tbl["Name"], page, page > 1,
    #index_tbl == pico.global.get("indexpagesize") and #pico.board.index(board_tbl["Name"], page + 1) ~= 0);
  html.finish();
end;

handlers["/([%l%d]+)/index/(%d+)"] = handlers["/([%l%d]+)/index"];

handlers["/([%l%d]+)/(%d+)"] = function(board, post)
  local board_tbl = pico.board.tbl(board);

  if not board_tbl then
    cgi.headers["Status"] = "404 Not Found";
    html.error("Board Not Found", "The board you specified does not exist.");
  end

  local thread_tbl, msg = pico.post.thread(board_tbl["Name"], post);

  if not thread_tbl then
    local post_tbl = pico.post.tbl(board_tbl["Name"], post);
    if not post_tbl then
      cgi.headers["Status"] = "404 Not Found";
      html.error("Thread Not Found", "Cannot display thread: %s", msg);
    else
      cgi.headers["Status"] = "301 Moved Permanently";
      cgi.headers["Location"] = string.format("/%s/%d#%d", board_tbl["Name"], post_tbl["Parent"], post_tbl["Number"]);
      cgi.finalize();
    end
  end

  html.begin("/%s/ - %s", board_tbl["Name"], (thread_tbl[0]["Subject"] and #thread_tbl[0]["Subject"] > 0)
                                             and html.striphtml(thread_tbl[0]["Subject"])
                                             or html.striphtml(thread_tbl[0]["Comment"]:sub(1, 64)));
  printf("<h1 id='boardtitle'>/%s/ - %s</h1>", board_tbl["Name"], html.striphtml(board_tbl["Title"]));
  printf("<h2 id='boardsubtitle'>%s</h2>", html.striphtml(board_tbl["Subtitle"]));
  html.announce();
  printf("<a id='new-post' href='#postform'>[Make a Post]</a>");
  html.form.postform(board_tbl, post);
  printf("<hr />");

  for i = 0, #thread_tbl do
    html.renderpost(thread_tbl[i]);
  end

  printf("<hr />");
  printf("<div id='thread-view-links'>");
  printf("<a href='/%s/catalog'>[Catalog]</a>", board_tbl["Name"]);
  printf("<a href='/%s/index'>[Index]</a>", board_tbl["Name"]);
  printf("<a href='/Overboard'>[Overboard]</a>");
  printf("<a href=''>[Update]</a>");

  printf("<span id='thread-reply'>");
  printf("<a href='#postform'>[Reply]</a>");
  printf("%d replies", thread_tbl[0]["ReplyCount"]);
  printf("</span>");

  printf("</div>");
  html.finish();
end;

handlers["/webring.json"] = function()
  cgi.headers["Content-Type"] = "application/json";
  printf("%s", json.encode(pico.webring.tbl()));
end;

for patt, func in pairs(handlers) do
  patt = "^" .. patt .. "$";

  if ENV["PATH_INFO"]:match(patt) then
    ENV["PATH_INFO"]:gsub(patt, func);
    cgi.finalize();
  end
end

cgi.headers["Status"] = "404 Not Found";
html.error("Page Not Found", "The specified page does not exist.");
%>
