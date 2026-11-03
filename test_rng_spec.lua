-- The draws (ranges, shuffles, team sizes, raffle without replacement), a
-- rough check that they are not biased, the saved lists and the keypad
-- entry.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Rng      = require("rng")
local Lists    = require("lists")
local NumEntry = require("numentry")

local function names(n)
    local t = {}
    for i = 1, n do t[i] = "P" .. i end
    return t
end

describe("Rng", function()
    setup(function() Rng.seed() end)

    it("stays within the range, both ends included, in any order", function()
        local seen = {}
        for _i = 1, 2000 do
            local v = Rng.int(6, 1)
            assert.is_true(v >= 1 and v <= 6)
            seen[v] = true
        end
        for v = 1, 6 do assert.is_true(seen[v]) end
        assert.are.equal(7, Rng.int(7, 7))
        for _i = 1, 200 do
            local v = Rng.int(-5, 5)
            assert.is_true(v >= -5 and v <= 5)
        end
    end)

    it("is not biased (chi-square on a die)", function()
        local counts, n = { 0, 0, 0, 0, 0, 0 }, 60000
        for _i = 1, n do
            local v = Rng.int(1, 6)
            counts[v] = counts[v] + 1
        end
        local e, chi = n / 6, 0
        for _i, c in ipairs(counts) do chi = chi + (c - e) ^ 2 / e end
        -- 5 degrees of freedom: 20.5 is the 0.1 % critical value
        assert.is_true(chi < 20.5, "chi-square " .. chi)
    end)

    it("flips both sides of the coin about as often", function()
        local heads = 0
        for _i = 1, 10000 do if Rng.coin() == "heads" then heads = heads + 1 end end
        assert.is_true(heads > 4700 and heads < 5300, "heads " .. heads)
    end)

    it("shuffles into a permutation, every name first about as often", function()
        local list = names(4)
        local first = {}
        for _i = 1, 8000 do
            local s = Rng.shuffle(list)
            assert.are.equal(4, #s)
            local seen = {}
            for _j, v in ipairs(s) do seen[v] = true end
            for _j, v in ipairs(list) do assert.is_true(seen[v]) end
            first[s[1]] = (first[s[1]] or 0) + 1
        end
        for _j, v in ipairs(list) do
            assert.is_true(first[v] > 1700 and first[v] < 2300, v .. " first " .. first[v])
        end
        assert.are.same({ "P1", "P2", "P3", "P4" }, list)   -- the original is untouched
    end)

    it("splits into teams whose sizes differ by one at most", function()
        for n = 1, 13 do
            for t = 2, 6 do
                local teams = Rng.teams(names(n), t)
                assert.are.equal(t, #teams)
                local lo, hi, total = math.huge, 0, 0
                for _k, team in ipairs(teams) do
                    lo = math.min(lo, #team); hi = math.max(hi, #team); total = total + #team
                end
                assert.are.equal(n, total)
                assert.is_true(hi - lo <= 1, ("%d names in %d teams"):format(n, t))
            end
        end
        local teams = Rng.teams(names(10), 3)
        assert.are.same({ 4, 3, 3 }, { #teams[1], #teams[2], #teams[3] })
    end)

    it("draws without replacement until the list is empty", function()
        local remaining = names(5)
        local drawn = {}
        for _i = 1, 5 do
            local v = Rng.drawFrom(remaining)
            assert.is_nil(drawn[v])
            drawn[v] = true
        end
        assert.are.equal(0, #remaining)
        assert.is_nil(Rng.drawFrom(remaining))
        assert.is_nil(Rng.pick({}))
    end)
end)

describe("Lists", function()
    it("parses one name per line, commas too, and trims", function()
        assert.are.same({ "Alice", "Bob", "Chloé", "Dan" }, Lists.parse("  Alice \nBob\n\n Chloé, Dan ;"))
        assert.are.same({}, Lists.parse(""))
        assert.are.equal(Lists.MAX_LEN, #Lists.clean(string.rep("x", 50)))
        assert.are.equal("Alice\nBob", Lists.format({ "Alice", "Bob" }))
    end)
    it("restores saved lists and finds a free name", function()
        local l = Lists.restore({ { name = "A", items = { "x", 3, "" } }, "junk", { name = 1 } })
        assert.are.same({ { name = "A", items = { "x" } } }, l)
        assert.are.equal("A 2", Lists.uniqueName(l, "A"))
        assert.are.equal("B", Lists.uniqueName(l, "B"))
    end)
end)

describe("NumEntry", function()
    it("types, erases and signs", function()
        local s = ""
        for _i, k in ipairs({ "0", "1", "2" }) do s = NumEntry.press(s, k) end
        assert.are.equal("12", s)
        s = NumEntry.press(s, "±", { signed = true })
        assert.are.equal(-12, NumEntry.value(s))
        assert.are.equal("12", NumEntry.press(s, "±", { signed = true }))
        assert.are.equal("-1", NumEntry.press(s, "⌫"))
        assert.are.equal("", NumEntry.press(s, "C"))
        assert.are.equal("-12", NumEntry.press(s, "±"))   -- unsigned entry ignores ±
        assert.is_nil(NumEntry.value("-"))
    end)
    it("takes a half point once and caps the digits", function()
        local s = NumEntry.press("40", "½", { half = true })
        assert.are.equal(40.5, NumEntry.value(s))
        assert.are.equal(s, NumEntry.press(s, "½", { half = true }))
        assert.are.equal(s, NumEntry.press(s, "3", { half = true }))
        assert.are.equal("40", NumEntry.press(s, "⌫"))
        assert.are.equal("40½", NumEntry.display(s))
        assert.are.equal("123", NumEntry.press("123", "4", { max_digits = 3 }))
        assert.are.equal("+318", NumEntry.signed(318))
        assert.are.equal("−106", NumEntry.signed(-106))
    end)
end)
