-- Händlerprofit: findet Rezepte, deren Ergebnis beim Händler mehr einbringt,
-- als die Materialien kosten. Materialpreise kommen aus Auctionator
-- (Auktionshaus-Scan und dort gemerkte Händlerpreise).
local ADDON, ns = ...
local CALLER = "Haendlerprofit"
local RECIPES = ns.RECIPES

ns.PROFESSIONS = {
  [129] = "Erste Hilfe", [164] = "Schmiedekunst", [165] = "Lederverarbeitung",
  [171] = "Alchemie", [185] = "Kochkunst", [186] = "Bergbau",
  [197] = "Schneiderei", [202] = "Ingenieurskunst", [333] = "Verzauberkunst",
}

-- Welche Rezepte stellen einen Gegenstand her (für Zwischenprodukte).
-- Rezepte mit Abklingzeit (Transmutationen, Mondstoff) zählen hier nicht:
-- sie lassen sich nicht beliebig oft ausführen.
local producers = {}
for spellID, r in pairs(RECIPES) do
  if not ns.COOLDOWNS[spellID] then
    local list = producers[r[1]]
    if not list then list = {}; producers[r[1]] = list end
    list[#list + 1] = spellID
  end
end

local MAX_DEPTH = 3
local db, charDB

-- ---------------------------------------------------------------- Preise

local function AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end
ns.AuctionatorAPI = AuctionatorAPI

local function SafeCall(f, ...)
  if not f then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
  return nil
end

-- Kaufpreis pro Stück: der günstigere aus Händler und Auktionshaus.
-- Rückgabe: Preis, Alter in Tagen, Quelle ("H" Händler, "AH")
local function BuyPrice(itemID)
  local api = AuctionatorAPI()
  if not api then return nil end
  local vendor = SafeCall(api.GetVendorPriceByItemID, CALLER, itemID)
  local auction = SafeCall(api.GetAuctionPriceByItemID, CALLER, itemID)
  if vendor and vendor <= 0 then vendor = nil end
  if auction and auction <= 0 then auction = nil end
  if vendor and (not auction or vendor <= auction) then
    return vendor, 0, "H"
  elseif auction then
    return auction, SafeCall(api.GetAuctionAgeByItemID, CALLER, itemID) or 0, "AH"
  end
  return nil
end

local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local pendingItems = false

-- Name, Link, Qualität, Symbol, Händler-Verkaufspreis; nil solange nicht geladen
-- Einmal geladene Daten werden behalten: der Client wirft Gegenstände wieder aus
-- seinem Zwischenspeicher, sonst würden Zeilen kommen und gehen. Nachgeladen wird
-- jeder Gegenstand nur einmal angefragt, damit keine Dauerschleife entsteht.
local itemCache, itemRequested = {}, {}
local function ItemData(itemID)
  local c = itemCache[itemID]
  if c then return c[1], c[2], c[3], c[4], c[5] end
  local name, link, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfoFn(itemID)
  if not name then
    pendingItems = true
    if not itemRequested[itemID] then
      itemRequested[itemID] = true
      if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
      end
    end
    return nil
  end
  itemCache[itemID] = { name, link, quality, icon, sellPrice or 0 }
  return name, link, quality, icon, sellPrice or 0
end
ns.ItemData = ItemData

-- Zeitpunkt des letzten Auctionator-Scans (Sekunden), nil wenn unbekannt
function ns.LastScanTime()
  local state = (Auctionator and Auctionator.SavedState) or AUCTIONATOR_SAVEDVARS
  if type(state) ~= "table" then return nil end
  local latest
  for _, key in ipairs({ "TimeOfLastBrowseScan", "TimeOfLastReplicateScan", "TimeOfLastGetAllScan" }) do
    local t = state[key]
    if type(t) == "number" and (not latest or t > latest) then latest = t end
  end
  return latest
end

-- Auctionator zählt das Preisalter nur in ganzen Tagen und stempelt Scans mit
-- dem Tag des Spielstarts. Ein Preis gilt deshalb als aktuell, wenn er höchstens
-- einen Tag älter ist als der letzte Scan.
local function FreshLimit()
  local last = ns.LastScanTime()
  if not last then return 0 end
  local day0 = (Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0) or 1577833200
  local scanDays = math.floor((time() - day0) / 86400) - math.floor((last - day0) / 86400)
  return scanDays + 1
end

-- ---------------------------------------------------------------- Gelernte Rezepte

local function IsKnown(spellID)
  if charDB.known[spellID] then return true end
  if (IsPlayerSpell and SafeCall(IsPlayerSpell, spellID))
    or (IsSpellKnown and SafeCall(IsSpellKnown, spellID))
    or (C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, spellID)) then
    charDB.known[spellID] = true
    return true
  end
  return false
end

-- Liest das geöffnete Berufsfenster aus und merkt sich die gelernten Rezepte.
local function ScanTradeSkill()
  local found = 0
  if GetNumTradeSkills and GetTradeSkillRecipeLink then
    for i = 1, (SafeCall(GetNumTradeSkills) or 0) do
      local link = SafeCall(GetTradeSkillRecipeLink, i)
      local id = link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
      if id and RECIPES[id] and not charDB.known[id] then
        charDB.known[id] = true
        found = found + 1
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
    for _, id in ipairs(SafeCall(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
      local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, id)
      if info and info.learned and RECIPES[id] and not charDB.known[id] then
        charDB.known[id] = true
        found = found + 1
      end
    end
  end
  return found
end

function ns.KnownCount()
  local n = 0
  for spellID in pairs(RECIPES) do
    if IsKnown(spellID) then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------- Berechnung

local memo
local RecipeCost

-- Günstigster Weg, ein Material zu beschaffen: kaufen oder (falls erlaubt)
-- mit einem eigenen Rezept herstellen.
local function UnitCost(itemID, depth, visiting, allRecipes)
  local cached = memo[itemID]
  if cached then return cached[1], cached[2], cached[3] end
  local price, age, source = BuyPrice(itemID)
  if db.craftIntermediates and depth < MAX_DEPTH and producers[itemID] and not visiting[itemID] then
    visiting[itemID] = true
    for _, spellID in ipairs(producers[itemID]) do
      if allRecipes or IsKnown(spellID) then
        local cost, costAge = RecipeCost(spellID, depth + 1, visiting, allRecipes)
        if cost then
          local unit = cost / RECIPES[spellID][2]
          if not price or unit < price then
            price, age, source = unit, costAge, "selbst"
          end
        end
      end
    end
    visiting[itemID] = nil
  end
  if depth == 0 then memo[itemID] = { price, age, source } end
  return price, age, source
end

-- Materialkosten eines Rezepts. Rückgabe: Kosten, höchstes Preisalter,
-- Aufschlüsselung; Kosten = nil, wenn für ein Material kein Preis bekannt ist.
function RecipeCost(spellID, depth, visiting, allRecipes)
  local r = RECIPES[spellID]
  local total, maxAge, parts, missing = 0, 0, {}, false
  for i = 4, #r, 2 do
    local itemID, count = r[i], r[i + 1]
    local price, age, source = UnitCost(itemID, depth, visiting, allRecipes)
    if price then
      total = total + price * count
      if age and age > maxAge then maxAge = age end
    else
      missing = true
    end
    parts[#parts + 1] = { itemID = itemID, count = count, price = price, source = source }
  end
  if missing then return nil, maxAge, parts end
  return total, maxAge, parts
end

-- Liefert sortierte Liste der Rezepte mit Händlergewinn sowie Zähler.
-- ignoreFilter = true rechnet über alle Berufe (für die Chat-Meldung).
function ns.Compute(ignoreFilter)
  memo = {}
  pendingItems = false
  local allRecipes = not db.onlyKnown
  local freshLimit = FreshLimit()
  local rows, stats = {}, { considered = 0, noPrice = 0, noSell = 0, loading = 0, maxAge = 0, stale = 0 }
  local filter = not ignoreFilter and db.skillFilter or nil
  for spellID, r in pairs(RECIPES) do
    if (not filter or r[3] == filter) and (allRecipes or IsKnown(spellID)) then
      stats.considered = stats.considered + 1
      local name, link, quality, icon, sell = ItemData(r[1])
      if not name then
        stats.loading = stats.loading + 1
      elseif sell <= 0 then
        stats.noSell = stats.noSell + 1
      else
        local cost, age, parts = RecipeCost(spellID, 0, {}, allRecipes)
        if not cost then
          stats.noPrice = stats.noPrice + 1
        else
          local profit = sell * r[2] - cost
          if profit > 0 then
            rows[#rows + 1] = {
              spellID = spellID, itemID = r[1], count = r[2], skill = r[3],
              name = name, link = link, quality = quality, icon = icon,
              sell = sell, cost = cost, profit = profit, age = age, parts = parts,
              known = IsKnown(spellID), stale = age > freshLimit,
              cooldown = ns.COOLDOWNS[spellID],
            }
            if age > stats.maxAge then stats.maxAge = age end
            if age > freshLimit then stats.stale = stats.stale + 1 end
          end
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.name < b.name
  end)
  stats.pending = pendingItems
  return rows, stats
end

-- ---------------------------------------------------------------- Ausgabe

local COIN_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local COIN_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COIN_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

function ns.Money(copper)
  local neg = copper < 0
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = ""
  if g > 0 then out = out .. g .. COIN_GOLD .. " " end
  if g > 0 or s > 0 then out = out .. s .. COIN_SILVER .. " " end
  out = out .. c .. COIN_COPPER
  return (neg and "-" or "") .. out
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Händlerprofit:|r " .. msg)
end
ns.Print = Print

local function Announce()
  if not db.announce then return end
  local rows = ns.Compute(true)
  if #rows == 0 then return end
  local best = rows[1]
  Print(("%d Rezept(e) mit Händlergewinn, bestes: %s (+%s). /hp zeigt die Liste."):format(
    #rows, best.link or best.name, ns.Money(best.profit)))
end

-- ---------------------------------------------------------------- Ereignisse

local timers = {}
local function Debounce(key, delay, func)
  if timers[key] then return end
  timers[key] = true
  C_Timer.After(delay, function()
    timers[key] = nil
    func()
  end)
end

local function RefreshUI()
  if ns.Refresh then ns.Refresh() end
end

local frame = CreateFrame("Frame")
local function TryRegister(event)
  pcall(frame.RegisterEvent, frame, event)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    HaendlerprofitDB = HaendlerprofitDB or {}
    HaendlerprofitCharDB = HaendlerprofitCharDB or {}
    db, charDB = HaendlerprofitDB, HaendlerprofitCharDB
    if db.onlyKnown == nil then db.onlyKnown = true end
    if db.craftIntermediates == nil then db.craftIntermediates = true end
    if db.announce == nil then db.announce = true end
    charDB.known = charDB.known or {}
    ns.db, ns.charDB = db, charDB
  elseif event == "PLAYER_LOGIN" then
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
        "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED" }) do
      TryRegister(e)
    end
    local api = AuctionatorAPI()
    if api and api.RegisterForDBUpdate then
      pcall(api.RegisterForDBUpdate, CALLER, function()
        Debounce("db", 3, function()
          RefreshUI()
          Announce()
        end)
      end)
    else
      Print("Auctionator wurde nicht gefunden. Ohne Auctionator gibt es keine Preise.")
    end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    -- Nur reagieren, wenn ein von uns angefragter Gegenstand wirklich geladen wurde
    if arg2 ~= false and itemRequested[arg1] and not itemCache[arg1] and ns.IsShown and ns.IsShown() then
      Debounce("items", 0.5, RefreshUI)
    end
  elseif event == "NEW_RECIPE_LEARNED" then
    if type(arg1) == "number" and RECIPES[arg1] then charDB.known[arg1] = true end
    Debounce("skill", 0.5, RefreshUI)
  else -- Berufsfenster
    Debounce("skill", 0.5, function()
      if ScanTradeSkill() > 0 then RefreshUI() end
    end)
  end
end)

SLASH_HAENDLERPROFIT1 = "/hp"
SLASH_HAENDLERPROFIT2 = "/haendlerprofit"
SlashCmdList["HAENDLERPROFIT"] = function()
  if ns.Toggle then ns.Toggle() end
end
