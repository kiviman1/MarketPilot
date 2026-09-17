local _, Probe = ...

function Probe.Now()
    return type(time) == "function" and time() or "UNKNOWN"
end

-- Never traverse nested API tables or invoke their __pairs/__tostring hooks.
local function primitive(value)
    local kind = type(value)
    return kind == "string" or kind == "number" or kind == "boolean"
end

function Probe.Text(value)
    if value == nil then return "UNKNOWN" end
    if not primitive(value) then return "<" .. type(value) .. ">" end
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" then return string.format("%.17g", value) end
    return tostring(value)
end

function Probe.Describe(value)
    if type(value) ~= "table" then return Probe.Text(value) end
    local fields = {}
    for key, field in next, value do
        if primitive(key) and primitive(field) then
            fields[#fields + 1] = Probe.Text(key) .. "=" .. Probe.Text(field)
        end
    end
    table.sort(fields)
    -- Only the first five rows are read; retain all their primitive fields.
    return "{" .. table.concat(fields, ", ") .. "}"
end

function Probe.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, field in pairs(value) do copy[key] = Probe.Copy(field) end
    return copy
end

function Probe.Log(message)
    local line = tostring(message)
    -- Escape chat markup without modifying the saved evidence.
    print("|cff66ccffMarketPilotProbe:|r " .. line:gsub("|", "||"))
    if not Probe.db then return end
    local logs = Probe.db.logs
    logs[#logs + 1] = { t = Probe.Now(), message = line }
    while #logs > 200 do table.remove(logs, 1) end
end

function Probe.Build()
    local snapshot = { capturedAt = Probe.Now() }
    if type(GetBuildInfo) == "function" then
        local ok, version, build, buildDate, interface = pcall(GetBuildInfo)
        if ok then
            snapshot.version, snapshot.build = version, build
            snapshot.buildDate, snapshot.interface = buildDate, interface
        else
            Probe.Log("GetBuildInfo failed: " .. Probe.Text(version))
        end
    else
        Probe.Log("GetBuildInfo unavailable; build/interface=UNKNOWN")
    end
    return snapshot
end

function Probe.InitDB()
    local saved = MarketPilotProbeDB
    if saved == nil then saved = { schema = 2, logs = {} } end
    if type(saved) ~= "table" or (saved.schema ~= 1 and saved.schema ~= 2) then
        -- Preserve unknown schemas on disk; explicit /mpprobe clear can reset them.
        Probe.db = { schema = 2, logs = {} }
        Probe.Log("unsupported SavedVariables schema; using memory only. Saved data preserved; /mpprobe clear resets it")
        return
    end
    if saved.schema == 1 then
        -- Additive migration: legacy lastResult was not validated and stays intact.
        saved.schema = 2
    end
    if type(saved.logs) ~= "table" then saved.logs = {} end
    Probe.db = saved
    MarketPilotProbeDB = saved
end

function Probe.Exists(name)
    return type(C_AuctionHouse) == "table" and type(C_AuctionHouse[name]) == "function"
end

function Probe.Call(name, ...)
    if not Probe.Exists(name) then
        Probe.Log(name .. " unavailable; result=UNKNOWN")
        return false
    end
    local ok, result = pcall(C_AuctionHouse[name], ...)
    if not ok then Probe.Log(name .. " failed (original error): " .. Probe.Text(result)) end
    return ok, result
end

function Probe.Ready(context)
    local ok, value = Probe.Call("IsThrottledMessageSystemReady")
    local state = "UNKNOWN"
    if ok and type(value) == "boolean" then state = value end
    Probe.session.throttle = { state = state, capturedAt = Probe.Now(), context = context }
    Probe.Log("throttle " .. context .. " ready=" .. Probe.Text(state) .. " raw=" .. Probe.Text(value))
    return state
end

function Probe.IsCount(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end
