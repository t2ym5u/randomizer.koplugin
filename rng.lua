-- rng.lua — the draws, on math.random seeded from the system's entropy.
-- Pure Lua, no KOReader dependency.
--
-- Rng.seed() mixes /dev/urandom (when there is one, as on Kobo and Kindle),
-- os.time() and os.clock(), then throws the first values away. It runs each
-- time the screen opens: another game may have seeded math.random with a
-- fixed value (a daily challenge does), and draws must not follow it.

local Rng = {}

function Rng.seed()
    local s = os.time()
    local f = io.open("/dev/urandom", "rb")
    if f then
        local b = f:read(4)
        f:close()
        if b and #b == 4 then
            local a1, a2, a3, a4 = b:byte(1, 4)
            s = s + ((a1 * 256 + a2) * 256 + a3) * 256 + a4
        end
    end
    s = s + math.floor((os.clock() * 1000000) % 1000000)
    math.randomseed(s % 2147483647)
    for _i = 1, 10 do math.random() end
end

-- Uniform integer in [lo, hi] (lo and hi may come in any order).
function Rng.int(lo, hi)
    if lo > hi then lo, hi = hi, lo end
    return lo + math.floor(math.random() * (hi - lo + 1))
end

-- "heads" or "tails".
function Rng.coin()
    return Rng.int(1, 2) == 1 and "heads" or "tails"
end

-- A shuffled copy (Fisher–Yates).
function Rng.shuffle(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    for i = #out, 2, -1 do
        local j = Rng.int(1, i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

function Rng.pick(list)
    if #list == 0 then return nil end
    return list[Rng.int(1, #list)]
end

-- n teams of sizes that differ by one at most: the shuffled list dealt
-- round the teams like cards. With fewer names than teams, the last teams
-- stay empty.
function Rng.teams(list, n)
    n = math.max(1, n)
    local teams = {}
    for t = 1, n do teams[t] = {} end
    for i, v in ipairs(Rng.shuffle(list)) do
        local t = (i - 1) % n + 1
        teams[t][#teams[t] + 1] = v
    end
    return teams
end

-- Draw without replacement: removes one random entry from `remaining` and
-- returns it (nil once it is empty).
function Rng.drawFrom(remaining)
    if #remaining == 0 then return nil end
    return table.remove(remaining, Rng.int(1, #remaining))
end

return Rng
