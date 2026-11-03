-- lists.lua — saved lists of names: { { name = "Family", items = { ... } }, ... }
-- Pure Lua, no KOReader dependency.

local Lists = {}

Lists.MAX_ITEMS = 100
Lists.MAX_LEN   = 30

-- Trim, drop control characters, cut at MAX_LEN characters (UTF-8 safe).
function Lists.clean(s)
    s = tostring(s or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local count, cut = 0, #s
    for pos in s:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > Lists.MAX_LEN then cut = pos - 1; break end
    end
    return s:sub(1, cut)
end

-- Names typed one per line (commas and semicolons also separate them).
-- Blank entries are dropped; repeats are kept (a raffle may hold a name
-- several times, once per ticket).
function Lists.parse(text)
    local out = {}
    for part in (tostring(text or "") .. "\n"):gmatch("([^\n,;]*)[\n,;]") do
        local s = Lists.clean(part)
        if s ~= "" and #out < Lists.MAX_ITEMS then out[#out + 1] = s end
    end
    return out
end

function Lists.format(items)
    return table.concat(items or {}, "\n")
end

-- Validates saved lists; drops anything unusable.
function Lists.restore(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for _i, l in ipairs(t) do
        if type(l) == "table" and type(l.name) == "string" and type(l.items) == "table" then
            local items = {}
            for _j, s in ipairs(l.items) do
                if type(s) == "string" and s ~= "" then items[#items + 1] = s end
            end
            out[#out + 1] = { name = l.name, items = items }
        end
    end
    return out
end

-- A name not used by another list: "List", "List 2", ...
function Lists.uniqueName(lists, base)
    local used = {}
    for _i, l in ipairs(lists) do used[l.name] = true end
    if not used[base] then return base end
    local k = 2
    while used[base .. " " .. k] do k = k + 1 end
    return base .. " " .. k
end

return Lists
