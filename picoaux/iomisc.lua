-- Miscellaneous io functions.

function io.fileexists(path)
  local f = io.open(filename, "r");

  if f ~= nil then
    f:close();
    return true;
  else
    return false;
  end
end
