local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox      = require("ui/widget/confirmbox")
local DataStorage     = require("datastorage")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local LuaSettings     = require("luasettings")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local Party      = require("party")
local ScreenBase = require("screen_base")

local Lists    = lrequire("lists")
local NumEntry = lrequire("numentry")
local Numpad   = lrequire("numpad")
local Rng      = lrequire("rng")

local DeviceScreen = Device.screen
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local function pxFace(px, bold)
    return Font:getFace(bold and "smallinfofontbold" or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

local function vspan(h) return VerticalSpan:new{ width = math.floor(h) } end
local function hspan(w) return HorizontalSpan:new{ width = math.floor(w) } end

-- One line at up to `px` pixels, shrunk until it fits `max_w`.
local function fitLine(text, px, max_w, bold)
    local face = pxFace(px, bold)
    while px > 12 do
        if RenderText:sizeUtf8Text(0, max_w * 10, face, text, true, bold).x <= max_w then break end
        px = math.floor(px * 0.9)
        face = pxFace(px, bold)
    end
    return TextWidget:new{ text = text, face = face, max_width = max_w, bold = bold }
end

-- A paragraph at up to `px` pixels, shrunk until it fits max_h.
local function fitBox(text, px, width, max_h, bold, align)
    local box
    while true do
        box = TextBoxWidget:new{ text = text, face = pxFace(px, bold), bold = bold, width = width,
                                 alignment = align or "center" }
        if not max_h or box:getSize().h <= max_h or px <= 12 then break end
        box:free()
        px = math.floor(px * 0.9)
    end
    return box
end

local TABS = { "coin", "number", "pick", "order", "teams", "draw" }
local TAB_LABEL = {
    coin   = _("Coin"),
    number = _("Number"),
    pick   = _("Name"),
    order  = _("Order"),
    teams  = _("Teams"),
    draw   = _("Raffle"),
}
local HISTORY = 12

local RULES_EN = [[
Random draw — the reader decides, fairly, for the whole table.

• Coin: heads or tails, with the last flips and how many of each.
• Number: a whole number between the two bounds, both included. Tap a bound to change it, or use a preset (a die, 1–10, 1–100…).
• Name: one name picked from the current list.
• Order: the whole list shuffled — who plays first, then second… (turn order).
• Teams: the list split into 2 to 6 teams whose sizes differ by one at most.
• Raffle: names drawn one by one without putting them back, until the list is empty. Start over puts every name back. A name written twice in the list has two tickets.

Lists (☰ menu): create as many as you like (family, class, club…), one name per line. The players of Score sheets can be imported as a list.

Every draw uses the device's random generator, seeded each time the screen opens from the system's entropy and the clock: no draw follows another one, every outcome is equally likely.
]]

local RULES_FR = [[
Tirage au sort — la liseuse décide, équitablement, pour toute la table.

• Pièce : pile ou face, avec les derniers lancers et le compte de chaque côté.
• Nombre : un nombre entier entre les deux bornes, incluses. Touchez une borne pour la changer, ou prenez un préréglage (un dé, 1–10, 1–100…).
• Nom : un nom tiré dans la liste choisie.
• Ordre : toute la liste mélangée — qui joue en premier, puis en deuxième… (ordre de jeu).
• Équipes : la liste répartie en 2 à 6 équipes dont les tailles diffèrent d'une personne au plus.
• Tombola : les noms sont tirés un par un sans remise, jusqu'à ce que la liste soit vide. Recommencer remet tous les noms. Un nom écrit deux fois dans la liste a deux tickets.

Listes (menu ☰) : créez-en autant que vous voulez (famille, classe, club…), un nom par ligne. Les joueurs des Feuilles de score peuvent être importés comme liste.

Chaque tirage utilise le générateur aléatoire de l'appareil, initialisé à chaque ouverture de l'écran à partir de l'entropie du système et de l'horloge : aucun tirage n'en suit un autre, chaque résultat a autant de chances.
]]

-- ---------------------------------------------------------------------------
-- RandomScreen
-- ---------------------------------------------------------------------------

local RandomScreen = ScreenBase:extend{ vertical_align = "top" }

function RandomScreen:init()
    Rng.seed()
    local p = self.plugin
    self.lists = Lists.restore(p:getSetting("lists", nil))
    if #self.lists == 0 then
        self.lists = { { name = _("Players"), items = Party.loadPlayers(p, 4) } }
    end
    self.list_i = math.max(1, math.min(#self.lists, tonumber(p:getSetting("list", 1)) or 1))
    local st = p:loadState()
    st = type(st) == "table" and st or {}
    self.st = {
        tab      = TAB_LABEL[st.tab] and st.tab or "coin",
        coins    = type(st.coins) == "table" and st.coins or {},
        numbers  = type(st.numbers) == "table" and st.numbers or {},
        lo       = tonumber(st.lo) or 1,
        hi       = tonumber(st.hi) or 6,
        picks    = type(st.picks) == "table" and st.picks or {},
        order    = type(st.order) == "table" and st.order or nil,
        teams    = type(st.teams) == "table" and st.teams or nil,
        nteams   = tonumber(st.nteams) or 2,
        draw     = type(st.draw) == "table" and st.draw or nil,
    }
    self.editing = nil       -- "lo" / "hi" while a bound is typed
    ScreenBase.init(self)
end

function RandomScreen:serializeState()
    return self.st
end

function RandomScreen:_save()
    self.plugin:saveState(self.st)
end

function RandomScreen:_saveLists()
    self.plugin:saveSetting("lists", self.lists)
    self.plugin:saveSetting("list", self.list_i)
end

function RandomScreen:_list()
    return self.lists[self.list_i]
end

function RandomScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

local function push(hist, v)
    hist[#hist + 1] = v
    while #hist > HISTORY do table.remove(hist, 1) end
end

-- ---------------------------------------------------------------------------
-- Draws
-- ---------------------------------------------------------------------------

function RandomScreen:_needNames(min)
    local l = self:_list()
    if not l or #l.items < (min or 1) then
        if (min or 1) <= 1 then
            self:updateStatus(_("The list is empty: add names in ☰ → Lists."))
        else
            self:updateStatus(T(_("The list needs at least %1 names: ☰ → Lists."), min))
        end
        return nil
    end
    return l
end

function RandomScreen:onDraw()
    local st = self.st
    local tab = st.tab
    if tab == "coin" then
        push(st.coins, Rng.coin())
    elseif tab == "number" then
        push(st.numbers, Rng.int(st.lo, st.hi))
    elseif tab == "pick" then
        local l = self:_needNames(1)
        if not l then return end
        push(st.picks, Rng.pick(l.items))
    elseif tab == "order" then
        local l = self:_needNames(2)
        if not l then return end
        st.order = { list = l.name, items = Rng.shuffle(l.items) }
    elseif tab == "teams" then
        local l = self:_needNames(2)
        if not l then return end
        st.teams = { list = l.name, teams = Rng.teams(l.items, st.nteams) }
    elseif tab == "draw" then
        local d = self:_raffle()
        if not d then return end
        if #d.remaining == 0 then
            self:updateStatus(_("Everyone has been drawn. Start over to put the names back."))
            return
        end
        d.drawn[#d.drawn + 1] = Rng.drawFrom(d.remaining)
    end
    self:_save()
    self:_redraw()
end

-- The raffle in progress for the current list (a fresh one when the list
-- changed or there is none).
function RandomScreen:_raffle(reset)
    local l = self:_needNames(1)
    if not l then return nil end
    local d = self.st.draw
    if reset or not d or d.list ~= l.name or type(d.remaining) ~= "table" or type(d.drawn) ~= "table" then
        d = { list = l.name, remaining = {}, drawn = {} }
        for i, s in ipairs(l.items) do d.remaining[i] = s end
        self.st.draw = d
    end
    return d
end

function RandomScreen:onRaffleReset()
    local d = self.st.draw
    local function go()
        self:_raffle(true)
        self:_save()
        self:_redraw()
    end
    if d and #d.drawn > 0 then
        UIManager:show(ConfirmBox:new{
            text = _("Put every name back and start the raffle over?"),
            ok_text = _("Start over"),
            ok_callback = go,
        })
    else
        go()
    end
end

function RandomScreen:setTab(tab)
    self.st.tab = tab
    self.editing = nil
    self:_save()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Range entry (number tab)
-- ---------------------------------------------------------------------------

function RandomScreen:editBound(which)
    self.editing = which
    self.entry = ""
    self:_redraw()
end

function RandomScreen:onKey(key)
    if not self.editing then return end
    self.entry = NumEntry.press(self.entry, key, { signed = true, max_digits = 6 })
    self:_redraw()
end

function RandomScreen:onBoundDone(ok)
    if ok then
        local v = NumEntry.value(self.entry)
        if v then self.st[self.editing] = math.floor(v) end
        if self.st.lo > self.st.hi then self.st.lo, self.st.hi = self.st.hi, self.st.lo end
        self.st.numbers = {}
        self:_save()
    end
    self.editing = nil
    self:_redraw()
end

function RandomScreen:setRange(lo, hi)
    self.st.lo, self.st.hi = lo, hi
    self.st.numbers = {}
    self:_save()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Lists
-- ---------------------------------------------------------------------------

function RandomScreen:_editItems(i, on_done)
    local l = self.lists[i]
    local dialog
    dialog = InputDialog:new{
        title = T(_("Names in %1 (one per line)"), l.name),
        input = Lists.format(l.items),
        allow_newline = true,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = false, callback = function()
                l.items = Lists.parse(dialog:getInputText())
                UIManager:close(dialog)
                self:_saveLists()
                if on_done then on_done() end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function RandomScreen:_askName(title, current, on_name)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = current or "",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local s = Lists.clean(dialog:getInputText())
                UIManager:close(dialog)
                if s ~= "" then on_name(s) end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function RandomScreen:newList()
    self:_askName(_("Name of the new list"), "", function(name)
        name = Lists.uniqueName(self.lists, name)
        self.lists[#self.lists + 1] = { name = name, items = {} }
        self.list_i = #self.lists
        self:_saveLists()
        self:_editItems(self.list_i, function() self:_redraw() end)
    end)
end

-- The players remembered by Score sheets, read from its settings file
-- (nothing is shared otherwise: either plugin works without the other).
function RandomScreen:_scoresheetNames()
    local path = DataStorage:getSettingsDir() .. "/scoresheet.lua"
    local f = io.open(path, "r")
    if not f then return nil end
    f:close()
    local ok, s = pcall(LuaSettings.open, LuaSettings, path)
    if not ok or not s then return nil end
    local names = s:readSetting("party_players")
    if type(names) ~= "table" then return nil end
    local out = {}
    for _i, n in ipairs(names) do
        if type(n) == "string" and n ~= "" then out[#out + 1] = n end
    end
    return #out > 0 and out or nil
end

function RandomScreen:importScoresheet()
    local names = self:_scoresheetNames()
    if not names then
        self:showMessage(_("No players saved in Score sheets yet."))
        return
    end
    local name = Lists.uniqueName(self.lists, _("Score sheet players"))
    self.lists[#self.lists + 1] = { name = name, items = names }
    self.list_i = #self.lists
    self:_saveLists()
    self:_redraw()
    self:showMessage(T(_("List \"%1\" added: %2 names."), name, #names))
end

function RandomScreen:openListActions(i)
    local l = self.lists[i]
    local items = {
        { id = "use",    text = _("Use this list") },
        { id = "edit",   text = _("Edit the names") },
        { id = "rename", text = _("Rename the list") },
        { id = "delete", text = _("Delete the list") },
    }
    MenuHelper.openPickerMenu{
        title = T(_("%1 (%2 names)"), l.name, #l.items), items = items, parent = self,
        on_select = function(id)
            if id == "use" then
                self.list_i = i
                self:_saveLists()
                self:_redraw()
            elseif id == "edit" then
                self:_editItems(i, function() self:_redraw() end)
            elseif id == "rename" then
                self:_askName(_("Rename the list"), l.name, function(name)
                    if name ~= l.name then l.name = Lists.uniqueName(self.lists, name) end
                    self:_saveLists()
                    self:_redraw()
                end)
            elseif id == "delete" then
                UIManager:show(ConfirmBox:new{
                    text = T(_("Delete the list \"%1\"?"), l.name),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        table.remove(self.lists, i)
                        if #self.lists == 0 then
                            self.lists = { { name = _("Players"), items = Party.loadPlayers(self.plugin, 4) } }
                        end
                        self.list_i = math.max(1, math.min(self.list_i, #self.lists))
                        self:_saveLists()
                        self:_redraw()
                    end,
                })
            end
        end,
    }
end

function RandomScreen:openListsMenu()
    local items = {}
    for i, l in ipairs(self.lists) do
        items[#items + 1] = { id = i, text = T(_("%1 (%2 names)"), l.name, #l.items) }
    end
    items[#items + 1] = { id = "new", text = "+ " .. _("New list") }
    items[#items + 1] = { id = "import", text = "+ " .. _("Import the Score sheets players") }
    MenuHelper.openPickerMenu{
        title = _("Lists"), items = items, current_id = self.list_i, parent = self,
        on_select = function(id)
            if id == "new" then self:newList()
            elseif id == "import" then self:importScoresheet()
            else self:openListActions(id) end
        end,
    }
end

-- Quick switch: tap the list's name above a result.
function RandomScreen:openListPicker()
    local items = {}
    for i, l in ipairs(self.lists) do
        items[#items + 1] = { id = i, text = T(_("%1 (%2 names)"), l.name, #l.items) }
    end
    items[#items + 1] = { id = "manage", text = _("Manage the lists…") }
    MenuHelper.openPickerMenu{
        title = _("Use the list"), items = items, current_id = self.list_i, parent = self,
        on_select = function(id)
            if id == "manage" then return self:openListsMenu() end
            self.list_i = id
            self:_saveLists()
            self:_redraw()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function RandomScreen:_titleBar()
    return self:buildTitleBar(_("Random draw"), function()
        local items = {
            { text = _("Lists"), callback = function() self:openListsMenu() end },
        }
        if self.st.tab == "draw" then
            items[#items + 1] = { text = _("Start the raffle over"), callback = function() self:onRaffleReset() end }
        end
        items[#items + 1] = { text = _("Clear the history"), callback = function()
            self.st.coins, self.st.numbers, self.st.picks = {}, {}, {}
            self.st.order, self.st.teams = nil, nil
            self:_save()
            self:_redraw()
        end }
        items[#items + 1] = self:makeRulesButtonConfig(RULES_EN, RULES_FR)
        return items
    end)
end

-- The tab strip: one button per draw, the current one inverted.
function RandomScreen:_tabs(w, per_row)
    local gap = Size.span.horizontal_small
    per_row = per_row or #TABS
    local bw = math.floor((w - gap * (per_row - 1)) / per_row)
    local vg = VerticalGroup:new{ align = "center" }
    local hg
    for k, tab in ipairs(TABS) do
        if (k - 1) % per_row == 0 then
            if hg then vg[#vg + 1] = hg; vg[#vg + 1] = vspan(gap) end
            hg = HorizontalGroup:new{ align = "center" }
        else
            hg[#hg + 1] = hspan(gap)
        end
        local t = tab
        hg[#hg + 1] = Button:new{
            text = TAB_LABEL[tab], width = bw, height = DeviceScreen:scaleBySize(44),
            text_font_size = 18, preselect = self.st.tab == tab,
            bordersize = Size.border.button, radius = Size.radius.button, margin = 0,
            padding = Size.padding.small,
            callback = function() self:setTab(t) end,
        }
    end
    vg[#vg + 1] = hg
    return vg
end

function RandomScreen:_actionRows()
    local tab = self.st.tab
    if self.editing then
        return { { text = _("Cancel"), callback = function() self:onBoundDone(false) end },
                 { text = _("OK"), callback = function() self:onBoundDone(true) end } }
    end
    local label = ({ coin = _("Flip the coin"), number = _("Draw a number"), pick = _("Pick"), order = _("Shuffle the order"),
                     teams = _("Split"), draw = _("Draw a name") })[tab]
    local rows = { { text = label, callback = function() self:onDraw() end } }
    if tab == "draw" then
        table.insert(rows, 1, { text = _("Start over"), callback = function() self:onRaffleReset() end })
    end
    return rows
end

function RandomScreen:buildLayout()
    local title_bar = self:_titleBar()
    local land = self:isLandscape()
    local g = self:getGutter()
    local cw = self:getControlsWidth()
    self.status_text:setMaxWidth(cw)

    local controls = VerticalGroup:new{ align = "center" }
    if land then
        controls[#controls + 1] = self:_tabs(cw, 3)
        controls[#controls + 1] = vspan(Size.span.vertical_large * 2)
    end
    if self.editing then
        controls[#controls + 1] = Numpad.build{
            width = cw, key_height = DeviceScreen:scaleBySize(52), sign = true,
            onKey = function(k) self:onKey(k) end,
        }
        controls[#controls + 1] = vspan(Size.span.vertical_large)
    end
    controls[#controls + 1] = self.status_text
    controls[#controls + 1] = vspan(Size.span.vertical_large)
    local bar_rows = self:_actionRows()
    -- The draw button is the one tapped over and over: make it tall.
    controls[#controls + 1] = self:_bigBar(bar_rows, cw)

    local tabs = (not land) and self:_tabs(self.dimen.w - 2 * g) or nil
    local tb_h = title_bar:getSize().h
    local bw, bh
    if land then
        bw = self.dimen.w - cw - 3 * g
        bh = self.dimen.h - tb_h - 2 * g
    else
        bw = self.dimen.w - 2 * g
        bh = self.dimen.h - tb_h - tabs:getSize().h - controls:getSize().h - 4 * g
    end
    local content = self:_content(bw, bh)
    local content_box = CenterContainer:new{ dimen = Geom:new{ w = bw, h = bh }, content }

    if land then
        local ch = controls:getSize().h
        self.layout = VerticalGroup:new{
            align = "left",
            title_bar,
            HorizontalGroup:new{
                align = "top",
                hspan(g),
                VerticalGroup:new{ vspan(g), content_box },
                hspan(g),
                VerticalGroup:new{ align = "center", vspan(math.max(g, math.floor((self.dimen.h - tb_h - ch) / 2))), controls },
            },
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            title_bar,
            vspan(g),
            tabs,
            vspan(g),
            content_box,
            vspan(g),
            controls,
            vspan(g),
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function RandomScreen:_bigBar(rows, w)
    local gap = Size.span.horizontal_default
    local hg = HorizontalGroup:new{ align = "center" }
    local bw = math.floor((w - gap * (#rows - 1)) / #rows)
    for k, r in ipairs(rows) do
        if k > 1 then hg[#hg + 1] = hspan(gap) end
        local main = k == #rows
        hg[#hg + 1] = Button:new{
            text = r.text, width = bw, height = DeviceScreen:scaleBySize(60),
            text_font_size = main and 24 or 20, bordersize = main and Size.border.thick * 2 or Size.border.button,
            radius = Size.radius.button, margin = 0, callback = r.callback,
        }
    end
    return hg
end

-- The list in use, as a button: tapping it switches lists.
function RandomScreen:_listButton(w)
    local l = self:_list()
    return Button:new{
        text = T(_("List: %1 (%2) ▾"), l.name, #l.items), width = w,
        text_font_size = 18, bordersize = Size.border.thin, radius = Size.radius.button,
        callback = function() self:openListPicker() end,
    }
end

-- A big result in a thick frame.
function RandomScreen:_resultCard(text, w, h, px)
    local inner_w = w - 2 * (Size.border.thick * 2 + Size.padding.large)
    local line = fitLine(text, px, inner_w, true)
    return FrameContainer:new{
        bordersize = Size.border.thick * 2, radius = Size.radius.window,
        padding = Size.padding.large, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = math.max(h, line:getSize().h) }, line },
    }
end

function RandomScreen:_content(w, h)
    local st = self.st
    local short = math.min(w, self.dimen.h, self.dimen.w)
    local vs = Size.span.vertical_large
    local g = VerticalGroup:new{ align = "center" }
    local function add(x) g[#g + 1] = x end
    local small = short * 0.045
    local tab = st.tab

    if tab == "coin" then
        local last = st.coins[#st.coins]
        local word = last == "heads" and _("HEADS") or (last == "tails" and _("TAILS") or "?")
        add(self:_resultCard(word, w, h * 0.45, short * 0.17))
        add(vspan(vs * 2))
        if #st.coins > 0 then
            -- H/T in English, F/P in French: the first letter of the word.
            local h1 = _("HEADS"):match("^[%z\1-\127\194-\244][\128-\191]*")
            local t1 = _("TAILS"):match("^[%z\1-\127\194-\244][\128-\191]*")
            local marks, heads = {}, 0
            for i = #st.coins, 1, -1 do
                local c = st.coins[i]
                if c == "heads" then heads = heads + 1 end
                marks[#marks + 1] = c == "heads" and h1 or t1
            end
            add(fitLine(T(_("Heads %1 · Tails %2"), heads, #st.coins - heads), small * 1.2, w))
            add(vspan(vs))
            add(fitLine(T(_("Last flips: %1"), table.concat(marks, " ")), small, w))
        else
            add(fitLine(_("Tap Flip the coin."), small * 1.2, w))
        end
    elseif tab == "number" then
        local gap = Size.span.horizontal_default
        local half = math.floor((w - gap) / 2)
        local function bound(which, label)
            local editing = self.editing == which
            local v = editing and (NumEntry.display(self.entry) ~= "" and NumEntry.display(self.entry) or "…")
                      or NumEntry.plain(st[which])
            return Button:new{
                text = T(label, v), width = half, height = DeviceScreen:scaleBySize(54),
                text_font_size = 22, preselect = editing,
                bordersize = Size.border.thick, radius = Size.radius.button,
                callback = function() self:editBound(which) end,
            }
        end
        add(HorizontalGroup:new{ bound("lo", _("Min %1")), hspan(gap), bound("hi", _("Max %1")) })
        add(vspan(vs * 2))
        if not self.editing then
            local presets = { { 1, 6 }, { 1, 10 }, { 1, 20 }, { 1, 100 }, { 0, 9 } }
            local pg = HorizontalGroup:new{ align = "center" }
            local pw = math.floor((w - gap * (#presets - 1)) / #presets)
            for k, pr in ipairs(presets) do
                if k > 1 then pg[#pg + 1] = hspan(gap) end
                local lo, hi = pr[1], pr[2]
                pg[#pg + 1] = Button:new{
                    text = lo .. "–" .. hi, width = pw, text_font_size = 17,
                    preselect = st.lo == lo and st.hi == hi, bordersize = Size.border.button,
                    radius = Size.radius.button, padding = Size.padding.small,
                    callback = function() self:setRange(lo, hi) end,
                }
            end
            add(pg)
            add(vspan(vs * 2))
            local last = st.numbers[#st.numbers]
            add(self:_resultCard(last and NumEntry.plain(last) or "?", w, h * 0.35, short * 0.2))
            add(vspan(vs * 2))
            if #st.numbers > 1 then
                local prev = {}
                for i = #st.numbers - 1, 1, -1 do prev[#prev + 1] = NumEntry.plain(st.numbers[i]) end
                add(fitLine(T(_("Before: %1"), table.concat(prev, " · ")), small, w))
            end
        else
            add(fitLine(_("Type the bound on the keypad."), small * 1.2, w))
        end
    elseif tab == "pick" then
        add(self:_listButton(w))
        add(vspan(vs * 2))
        local last = st.picks[#st.picks]
        add(self:_resultCard(last or "?", w, h * 0.4, short * 0.14))
        add(vspan(vs * 2))
        if #st.picks > 1 then
            local prev = {}
            for i = #st.picks - 1, 1, -1 do prev[#prev + 1] = st.picks[i] end
            add(fitBox(T(_("Before: %1"), table.concat(prev, " · ")), small, w, h * 0.2))
        end
    elseif tab == "order" then
        add(self:_listButton(w))
        add(vspan(vs * 2))
        local o = st.order
        if o and o.list == self:_list().name then
            add(fitLine(T(_("First: %1"), o.items[1]), short * 0.09, w, true))
            add(vspan(vs * 2))
            add(self:_numberedList(o.items, w, h * 0.65, short * 0.06))
        else
            add(fitLine(_("Tap Shuffle the order for a random turn order."), small * 1.2, w))
        end
    elseif tab == "teams" then
        add(self:_listButton(w))
        add(vspan(vs))
        local gap = Size.span.horizontal_small
        local counts = { 2, 3, 4, 5, 6 }
        local cg = HorizontalGroup:new{ align = "center" }
        local cbw = math.floor((w - gap * #counts) / (#counts + 1.6))
        cg[#cg + 1] = TextWidget:new{ text = _("Teams:") .. " ", face = pxFace(small, true), bold = true }
        for k, n in ipairs(counts) do
            if k > 1 then cg[#cg + 1] = hspan(gap) end
            cg[#cg + 1] = Button:new{
                text = tostring(n), width = cbw, text_font_size = 20, preselect = st.nteams == n,
                bordersize = Size.border.button, radius = Size.radius.button,
                callback = function()
                    st.nteams = n
                    self:_save()
                    self:_redraw()
                end,
            }
        end
        add(cg)
        add(vspan(vs * 2))
        local tm = st.teams
        if tm and tm.list == self:_list().name and #tm.teams == st.nteams then
            add(self:_teamBlocks(tm.teams, w, h * 0.7, short))
        else
            add(fitLine(_("Tap Split to make the teams."), small * 1.2, w))
        end
    elseif tab == "draw" then
        add(self:_listButton(w))
        add(vspan(vs * 2))
        local d = self:_raffle()
        if d then
            local total = #d.remaining + #d.drawn
            local last = d.drawn[#d.drawn]
            add(fitLine(T(_("Left: %1 of %2"), #d.remaining, total), small * 1.2, w))
            add(vspan(vs))
            add(self:_resultCard(last or "?", w, h * 0.3, short * 0.13))
            add(vspan(vs * 2))
            if #d.drawn > 0 then
                local order = {}
                for i, s in ipairs(d.drawn) do order[#order + 1] = i .. ". " .. s end
                add(fitBox(table.concat(order, " · "), small, w, h * 0.3))
            end
            if #d.remaining == 0 and total > 0 then
                add(vspan(vs))
                add(fitLine(_("The list is empty."), small * 1.2, w, true))
            end
        end
    end
    return g
end

-- "1. Alice", "2. Bob"…, in one or two columns.
function RandomScreen:_numberedList(items, w, max_h, px)
    local cols = #items > 6 and 2 or 1
    local per_col = math.ceil(#items / cols)
    local col_w = math.floor(w / cols)
    local function build(p)
        local hg = HorizontalGroup:new{ align = "top" }
        for c = 1, cols do
            local vg = VerticalGroup:new{ align = "left" }
            for k = (c - 1) * per_col + 1, math.min(#items, c * per_col) do
                vg[#vg + 1] = TextWidget:new{ text = k .. ". " .. items[k], face = pxFace(p, k == 1),
                                              bold = k == 1, max_width = col_w - Size.padding.large }
            end
            hg[#hg + 1] = CenterContainer:new{ dimen = Geom:new{ w = col_w, h = vg:getSize().h }, vg }
        end
        return hg
    end
    local hg = build(px)
    while hg:getSize().h > max_h and px > 14 do
        px = math.floor(px * 0.9)
        hg = build(px)
    end
    return hg
end

-- Teams side by side (two per row), each in a frame with its names.
function RandomScreen:_teamBlocks(teams, w, max_h, short)
    local per_row = #teams <= 2 and 2 or (#teams <= 4 and 2 or 3)
    local gap = Size.span.horizontal_default
    local bw = math.floor((w - gap * (per_row - 1)) / per_row)
    local function build(px)
        local vg = VerticalGroup:new{ align = "center" }
        local row
        local heights = {}
        local blocks = {}
        for t, team in ipairs(teams) do
            local inner = VerticalGroup:new{ align = "center" }
            inner[#inner + 1] = TextWidget:new{ text = T(_("Team %1"), t), face = pxFace(px * 1.1, true), bold = true }
            inner[#inner + 1] = vspan(px * 0.3)
            for _i, s in ipairs(team) do
                inner[#inner + 1] = TextWidget:new{ text = s, face = pxFace(px), max_width = bw - 4 * Size.padding.default }
            end
            blocks[t] = inner
            local r = math.ceil(t / per_row)
            heights[r] = math.max(heights[r] or 0, inner:getSize().h)
        end
        for t, inner in ipairs(blocks) do
            if (t - 1) % per_row == 0 then
                if row then vg[#vg + 1] = row; vg[#vg + 1] = vspan(gap) end
                row = HorizontalGroup:new{ align = "top" }
            else
                row[#row + 1] = hspan(gap)
            end
            local r = math.ceil(t / per_row)
            row[#row + 1] = FrameContainer:new{
                bordersize = Size.border.thick, radius = Size.radius.window,
                padding = Size.padding.default, margin = 0,
                CenterContainer:new{ dimen = Geom:new{ w = bw - 2 * (Size.border.thick + Size.padding.default),
                                                       h = heights[r] }, inner },
            }
        end
        if row then vg[#vg + 1] = row end
        return vg
    end
    local px = short * 0.055
    local vg = build(px)
    while vg:getSize().h > max_h and px > 14 do
        px = math.floor(px * 0.9)
        vg = build(px)
    end
    return vg
end

function RandomScreen:updateStatus(msg)
    if msg then return ScreenBase.updateStatus(self, msg) end
    local st = self.st
    local text = ""
    if self.editing then
        text = self.editing == "lo" and _("Lowest number") or _("Highest number")
    elseif st.tab == "number" then
        text = T(_("A whole number from %1 to %2"), NumEntry.plain(st.lo), NumEntry.plain(st.hi))
    elseif st.tab == "teams" then
        local l = self:_list()
        local n = #l.items
        local lo = math.floor(n / st.nteams)
        local hi = math.ceil(n / st.nteams)
        text = lo == hi and T(_("%1 teams of %2"), st.nteams, lo)
               or T(_("%1 teams of %2 or %3"), st.nteams, lo, hi)
    end
    ScreenBase.updateStatus(self, text)
end

return RandomScreen
