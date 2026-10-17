BGSessionTracker = { name = "BGSessionTracker", version = "1.0.0" }
local A = BGSessionTracker
local C = {}
A.Core = C

function C.IsNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function C.IsCount(value)
    return C.IsNumber(value) and value >= 0 and value == math.floor(value)
end

function C.Clamp(value, low, high, fallback)
    if not C.IsNumber(value) then return fallback end
    return math.max(low, math.min(high, value))
end

function C.NewSession(now)
    return { startedAt = now, wins = 0, losses = 0, draws = 0, ap = 0, apByReason = {} }
end

function C.ValidSession(s)
    return type(s) == "table" and C.IsCount(s.startedAt)
        and C.IsCount(s.wins) and C.IsCount(s.losses) and C.IsCount(s.draws)
        and C.IsCount(s.ap) and type(s.apByReason) == "table"
end

function C.CanResume(s, now)
    return C.ValidSession(s) and C.IsNumber(s.reloadAt)
        and now >= s.reloadAt and now - s.reloadAt <= 120
end

function C.WinRate(s)
    local decided = s.wins + s.losses
    return decided > 0 and string.format("%.1f%%", s.wins / decided * 100) or "0.0%"
end

function C.Completed(s)
    return s.wins + s.losses + s.draws
end

function C.FormatAP(value)
    if not C.IsCount(value) then return "--" end
    -- Round before selecting the suffix to avoid values such as 1000.0K.
    if value >= 999950 then return string.format("%.2fM", value / 1000000) end
    if value >= 1000 then return string.format("%.1fK", value / 1000) end
    return tostring(value)
end

-- A final API result is authoritative; scores and round wins are never inferred.
function C.RecordResult(s, match, result)
    if not match or not match.eligible or match.counted then return false end
    if result == "win" then s.wins = s.wins + 1
    elseif result == "loss" then s.losses = s.losses + 1
    elseif result == "draw" then s.draws = s.draws + 1
    else return false end
    match.counted = true
    return true
end

-- Require the event's positive delta to agree with the observed wallet change.
-- Repeated events have the same total; spending and transfers still rebase it.
function C.ApplyAP(s, total, difference, reason, excluded)
    if not C.IsCount(total) then return false, "invalid" end
    local previous = s.lastAP
    s.lastAP = total
    if total == previous then return false end
    if excluded then return false end
    if not C.IsNumber(difference) then return false, "gap" end
    if difference <= 0 then return false end
    if not C.IsCount(difference) or reason == nil or not C.IsCount(previous)
        or total - previous ~= difference then
        return false, "gap"
    end
    s.ap = s.ap + difference
    local key = tostring(reason)
    s.apByReason[key] = (C.IsCount(s.apByReason[key]) and s.apByReason[key] or 0) + difference
    return true
end
