-- /catnip perf: measures how much time Catnip's own code takes, per module and per event, in and
-- out of combat, so a change can be compared before and after.
--
-- Each runtime file starts with `local CreateFrame, C_Timer = ns.Profiled("<Module>")`. Its plain
-- frames (type "Frame", no template) then time every script they run (OnEvent per event name,
-- OnUpdate, ...), and its C_Timer callbacks are timed too (Cooldowns.lua's updates run in them).
-- While not measuring, a wrapper only checks a flag. Times are inclusive: a handler that calls into
-- another module (a callback like ns.OnStealthChanged) counts that time as its own.
-- Not covered: frames with a template or of other types (Cooldown, StatusBar, AuraContainer: their
-- few scripts are light), and Blizzard's work on our behalf (drawing, AuraContainer, swipes).
local addonName, ns = ...

local Profiler = {}
ns.Profiler = Profiler

local REAL_CREATE_FRAME = CreateFrame
local REAL_TIMER = C_Timer
local CAN_TIME = debugprofilestop ~= nil
local TOP = 15 -- rows printed in chat (all are saved)
local KEEP = 10 -- reports kept in CatnipDB.perfReports

local running = false
local rows = {} -- key -> { calls, ms, max, combatCalls, combatMs }
local label, startedAt, combatSeconds, combatSince
local inCombat = InCombatLockdown() -- a /reload in combat

local function Record(key, ms)
    local row = rows[key]
    if not row then
        row = { calls = 0, ms = 0, max = 0, combatCalls = 0, combatMs = 0 }
        rows[key] = row
    end
    row.calls = row.calls + 1
    row.ms = row.ms + ms
    if ms > row.max then
        row.max = ms
    end
    if inCombat then
        row.combatCalls = row.combatCalls + 1
        row.combatMs = row.combatMs + ms
    end
end

local function Wrap(key, fn)
    return function(...)
        if not running then
            return fn(...)
        end
        local start = debugprofilestop()
        fn(...)
        Record(key, debugprofilestop() - start)
    end
end

-- OnEvent is keyed by the event, so "Cooldowns UNIT_AURA" and "Cooldowns SPELL_UPDATE_COOLDOWN"
-- show apart.
local function WrapEvent(module, fn)
    local prefix = module .. " "
    return function(self, event, ...)
        if not running then
            return fn(self, event, ...)
        end
        local start = debugprofilestop()
        fn(self, event, ...)
        Record(prefix .. tostring(event), debugprofilestop() - start)
    end
end

-- Returns a CreateFrame and a C_Timer for one module: the same as the game's, plus timing.
function ns.Profiled(module)
    if not CAN_TIME then
        return REAL_CREATE_FRAME, REAL_TIMER
    end
    local function ProfiledCreateFrame(frameType, name, parent, template, ...)
        local frame = REAL_CREATE_FRAME(frameType, name, parent, template, ...)
        if frameType ~= "Frame" or template ~= nil then
            return frame -- Blizzard's templates and widgets keep their own SetScript
        end
        local setScript = frame.SetScript
        frame.SetScript = function(self, script, fn)
            if type(fn) == "function" then
                if script == "OnEvent" then
                    fn = WrapEvent(module, fn)
                else
                    fn = Wrap(module .. " " .. script, fn)
                end
            end
            return setScript(self, script, fn)
        end
        return frame
    end
    local timerKey = module .. " C_Timer"
    local timer = setmetatable({
        After = function(seconds, fn)
            return REAL_TIMER.After(seconds, Wrap(timerKey, fn))
        end,
        NewTimer = function(seconds, fn)
            return REAL_TIMER.NewTimer(seconds, Wrap(timerKey, fn))
        end,
        NewTicker = function(seconds, fn, iterations)
            return REAL_TIMER.NewTicker(seconds, Wrap(timerKey, fn), iterations)
        end,
    }, { __index = REAL_TIMER })
    return ProfiledCreateFrame, timer
end

-- Combat time, so in-combat cost can be shown per second of combat.
local events = REAL_CREATE_FRAME("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    local now = event == "PLAYER_REGEN_DISABLED"
    if now == inCombat then
        return
    end
    inCombat = now
    if not running then
        return
    end
    if inCombat then
        combatSince = GetTime()
    elseif combatSince then
        combatSeconds = combatSeconds + GetTime() - combatSince
        combatSince = nil
    end
end)

local function Durations()
    local total = GetTime() - startedAt
    local combat = combatSeconds + (combatSince and GetTime() - combatSince or 0)
    return total, combat
end

-- Blizzard's own addon profiler, if this client has it (unverified on Forever): a cross-check that
-- covers what our wrappers can't see. Nil if it's missing or refuses.
local function BlizzardLine()
    local api, metrics = C_AddOnProfiler, Enum.AddOnProfilerMetric
    if not (api and api.GetAddOnMetric and metrics) then
        return nil
    end
    local function Get(name, overall)
        local metric = metrics[name]
        if metric == nil then
            return "?"
        end
        local ok, value
        if overall then
            ok, value = pcall(api.GetOverallMetric, metric)
        else
            ok, value = pcall(api.GetAddOnMetric, addonName, metric)
        end
        if not ok or type(value) ~= "number" or ns.IsSecret(value) then
            return "?"
        end
        return string.format("%.3f", value)
    end
    return string.format("Blizzard's profiler: Catnip recent %s, session %s, peak %s ms; all addons recent %s ms",
        Get("RecentAverageTime"), Get("SessionAverageTime"), Get("PeakTime"), Get("RecentAverageTime", true))
end

-- ms of our code per second of play, as text ("-" when there was no such time).
local function PerSecond(ms, seconds)
    if seconds < 0.5 then
        return "-"
    end
    return string.format("%.2f", ms / seconds)
end

local function BuildReport()
    local total, combat = Durations()
    local out = total - combat
    local sorted = {}
    local sumMs, sumCombatMs = 0, 0
    for key, row in pairs(rows) do
        sorted[#sorted + 1] = { key = key, row = row }
        sumMs = sumMs + row.ms
        sumCombatMs = sumCombatMs + row.combatMs
    end
    table.sort(sorted, function(a, b)
        return a.row.ms > b.row.ms
    end)
    local lines = {}
    lines[1] = string.format("%s: %.0fs measured, %.0fs in combat. Times are ms of Catnip code per second of play.",
        label, total, combat)
    lines[2] = string.format("TOTAL: combat %s ms/s, out of combat %s ms/s (%.1f ms over %d entries)",
        PerSecond(sumCombatMs, combat), PerSecond(sumMs - sumCombatMs, out), sumMs, #sorted)
    for _, entry in ipairs(sorted) do
        local row = entry.row
        lines[#lines + 1] = string.format("%s: combat %s, out %s ms/s | %d calls, avg %.3f, max %.2f ms",
            entry.key, PerSecond(row.combatMs, combat), PerSecond(row.ms - row.combatMs, out),
            row.calls, row.ms / row.calls, row.max)
    end
    local blizzard = BlizzardLine()
    if blizzard then
        table.insert(lines, 3, blizzard)
    end
    return lines
end

local function PrintReport(lines)
    local header = BlizzardLine() and 3 or 2
    for i, line in ipairs(lines) do
        if i > header + TOP then
            ns.Print(string.format("... %d more in CatnipDB.perfReports (after a /reload)", #lines - header - TOP))
            break
        end
        ns.Print(i <= header and line or ("|cffcccccc" .. line .. "|r"))
    end
end

local function Start(name)
    wipe(rows)
    label = (name and name ~= "") and name or date("%H:%M")
    startedAt, combatSeconds = GetTime(), 0
    combatSince = inCombat and GetTime() or nil
    running = true
    ns.Print("perf: measuring '" .. label .. "'. /catnip perf to see it so far, /catnip perf stop to finish and save.")
end

local function Stop()
    local lines = BuildReport()
    running = false
    ns.db.perfReports = ns.db.perfReports or {}
    table.insert(ns.db.perfReports, { label = label, date = date("%Y-%m-%d %H:%M"), lines = lines })
    while #ns.db.perfReports > KEEP do
        table.remove(ns.db.perfReports, 1)
    end
    PrintReport(lines)
    ns.Print("perf: saved as '" .. label .. "' (/reload writes it to the SavedVariables file).")
end

-- /catnip perf start [label] | stop | (nothing: the report so far, or how to use it)
ns.commands.perf = function(arg)
    if not CAN_TIME then
        ns.Print("perf: debugprofilestop isn't available in this client, so nothing can be timed.")
        return
    end
    local action, name = strsplit(" ", arg or "", 2)
    if action == "start" then
        Start(name)
    elseif action == "stop" then
        if running then
            Stop()
        else
            ns.Print("perf: not measuring. /catnip perf start [label]")
        end
    elseif running then
        PrintReport(BuildReport())
    else
        ns.Print("perf: /catnip perf start [label], play a while (in and out of combat), then /catnip perf stop.")
        local blizzard = BlizzardLine()
        ns.Print(blizzard or "Blizzard's addon profiler (C_AddOnProfiler) isn't in this client.")
    end
end
