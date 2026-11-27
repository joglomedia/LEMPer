-- Rspamd policy for the dedicated submission milter.
local rspamd_util = require "rspamd_util"

-- Permit folding, comments and quoted display names, but require the whole
-- field to describe one mailbox. The native address parser is intentionally
-- tolerant of fragments such as a group terminator or a trailing comma.
local function surrounding_text_valid(text, display)
  local depth, quoted, escaped = 0, false, false
  for index = 1, #text do
    local char = text:sub(index, index)
    if char:match("[%z\001-\008\011-\031\127]") then
      return false
    end
    if escaped then
      escaped = false
    elseif depth > 0 then
      if char == "\\" then
        escaped = true
      elseif char == "(" then
        depth = depth + 1
      elseif char == ")" then
        depth = depth - 1
      end
    elseif quoted then
      if char == "\\" then
        escaped = true
      elseif char == '"' then
        quoted = false
      end
    elseif char == "(" then
      depth = 1
    elseif display and char == '"' then
      quoted = true
    elseif not char:match("[ \t]") and
        (not display or char:match("[()<>,;:@%[%]\\]")) then
      return false
    end
  end
  return depth == 0 and not quoted and not escaped
end

local function visible_author(task)
  -- A malformed field can be absent from the native header index even when
  -- another mail reader treats it as an author field.
  if task:has_flag("broken_headers") then
    return nil
  end
  local headers = task:get_header_full("From")
  if not headers or #headers ~= 1 or headers[1].name:lower() ~= "from" then
    return nil
  end
  local field = headers[1].value:gsub("\r?\n[ \t]+", " ")
  local addresses = rspamd_util.parse_mail_address(field, task:get_mempool())
  if not addresses or #addresses ~= 1 then
    return nil
  end
  local author = addresses[1]
  -- LEMPer provisions only dot-atom local parts and DNS domains. Match the
  -- exact mailbox spelling recognized by the parser before looking it up.
  if not author.flags.valid or author.flags.quoted or author.flags.ip then
    return nil
  end
  local address = author.addr
  local syntax = author.flags.braced and "<" .. address .. ">" or address
  local first, last = field:find(syntax, 1, true)
  if not first or not surrounding_text_valid(field:sub(1, first - 1), author.flags.braced) or
      not surrounding_text_valid(field:sub(last + 1), false) then
    return nil
  end
  return address:lower()
end

local function authorized(task)
  local login = task:get_user()
  if not login then
    return false
  end
  local author = visible_author(task)
  if not author then
    return false
  end
  local map = io.open("@ROOT@/current/sender_login", "r")
  if not map then
    return nil
  end
  login = login:lower()
  -- Open the current published generation for each decision so alias edits
  -- and account disablement do not rely on a filter cache refresh.
  local matches = false
  for entry in map:lines() do
    local address, owner = entry:match("^([^\t]+)\t([^\t]+)$")
    if address == author then
      matches = owner == login
      break
    end
  end
  map:close()
  return matches
end

rspamd_config:register_symbol({
  name = "LEMPER_SUBMISSION_AUTHOR",
  type = "prefilter",
  priority = 10,
  callback = function(task)
    local ok, allowed = pcall(authorized, task)
    if not ok or allowed == nil then
      task:set_pre_result("soft reject", "Submission author policy unavailable")
    elseif not allowed then
      task:set_pre_result("reject", "From must be the authenticated mailbox or one of its assigned aliases")
    else
      task:set_pre_result("no action")
    end
  end,
})
