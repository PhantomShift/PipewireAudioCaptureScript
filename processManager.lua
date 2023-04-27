local function getOSExecuteResult(command)
    local fs = io.popen(command)
    assert(fs, ("getOSExecuteResult given malformed command '%s'"):format(command))
    local result = fs:read("*all")
    fs:close()
    return result
end

local function stripQuotes(str)
    return str:gsub("%b\"\"", function(n) return n:sub(2, -2) end)
end
local function cleanMagicCharacters(str)
    return str:gsub("[%$%%%^%*%(%)%.%[%]%[%+%-%?]", {
        ["$"] = "%$",
        ["%"] = "%%",
        ["^"] = "%^",
        ["*"] = "%*",
        ["("] = "%(",
        [")"] = "%)",
        ["."] = "%.",
        ["["] = "%[",
        ["]"] = "%]",
        ["+"] = "%+",
        ["-"] = "%-",
        ["?"] = "%?"
    })
end
local function cleanString(str)
    return cleanMagicCharacters(stripQuotes(str))
end

-- Small module for managing spawned processes, not meant to be used elsewhere
-- Note that this assumes the use of unique process names + arguments
-- i.e. if a process `/usr/lib/firefox` is spawned, no other processes of this name should exist
local processManager = {}
processManager.__index = processManager
function processManager.new()
    return setmetatable({}, processManager)
end

function processManager:kill(pid)
    if not pid or not self[pid] then return end
    os.execute("kill " .. pid)
    self[pid] = nil
end
function processManager:spawn(cmd)
    os.execute(("%s &"):format(cmd))
    local pid = getOSExecuteResult(("pgrep %s -a"):format(cmd:match("[^%s]+"))):match("(%d+)%s+" .. cleanString(cmd))
    print(getOSExecuteResult(("pgrep %s -a")))
    print("(%d+)%s+" .. cleanString(cmd))
    self[pid] = cmd
    return pid
end

return processManager.new()
