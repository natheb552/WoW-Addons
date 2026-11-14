-- Nachgebaute Spiel-API für Tests außerhalb von WoW (Lua 5.1).
-- Bildet nur nach, was Händlerprofit mit Preisanker benutzt: Uhr und Timer, Rahmen, Auktionshaus mit Drossel,
-- Gegenstandsdaten mit verzögertem Laden, Händler und Taschen.

local S = { jetzt = 1000, timer = {}, rahmen = {}, ausgabe = {}, gesendet = {} }

---------------------------------------------------------------- Uhr und Timer

function GetTime() return S.jetzt end
function time() return 1700000000 + math.floor(S.jetzt) end

C_Timer = {}
function C_Timer.After(sek, fn)
  S.timer[#S.timer + 1] = { um = S.jetzt + sek, fn = fn }
end
function C_Timer.NewTicker(sek, fn)
  local t = { aktiv = true }
  function t:Cancel() self.aktiv = false end
  local function lauf()
    if not t.aktiv then return end
    fn(t)
    if t.aktiv then C_Timer.After(sek, lauf) end
  end
  C_Timer.After(sek, lauf)
  return t
end

-- Lässt die Zeit in kleinen Schritten vergehen und führt fällige Timer aus.
function S.Warten(sek)
  local ziel = S.jetzt + sek
  while S.jetzt < ziel do
    S.jetzt = S.jetzt + 0.05
    local faellig = {}
    for i = #S.timer, 1, -1 do
      if S.timer[i].um <= S.jetzt then faellig[#faellig + 1] = table.remove(S.timer, i) end
    end
    table.sort(faellig, function(a, b) return a.um < b.um end)
    for _, t in ipairs(faellig) do t.fn() end
    for _, r in ipairs(S.rahmen) do
      if r.gezeigt and r.skripte.OnUpdate then r.skripte.OnUpdate(r, 0.05) end
    end
  end
end

---------------------------------------------------------------- Rahmen

local Rahmen = {}
Rahmen.__index = function(_, name)
  return Rahmen[name] or function() end -- unbekannte Methoden tun nichts
end
function Rahmen:RegisterEvent(e)
  assert(S.bekannt[e], "unbekanntes Ereignis: " .. tostring(e))
  self.ereignisse[e] = true
end
function Rahmen:SetScript(name, fn) self.skripte[name] = fn end
function Rahmen:GetScript(name) return self.skripte[name] end
function Rahmen:Show() self.gezeigt = true; if self.skripte.OnShow then self.skripte.OnShow(self) end end
function Rahmen:Hide() self.gezeigt = false end
function Rahmen:SetShown(an) if an then self:Show() else self:Hide() end end
function Rahmen:IsShown() return self.gezeigt end
function Rahmen:SetText(t) self.text = tostring(t) end
function Rahmen:GetText() return self.text end
function Rahmen:SetEnabled(an) self.an = an end
function Rahmen:IsEnabled() return self.an end
function Rahmen:CreateTexture() return setmetatable({ skripte = {}, ereignisse = {} }, Rahmen) end
function Rahmen:CreateFontString() return setmetatable({ skripte = {}, ereignisse = {} }, Rahmen) end
function Rahmen:SetSize(b, h) self.breite, self.hoehe = b, h end
function Rahmen:SetWidth(b) self.breite = b end
function Rahmen:SetHeight(h) self.hoehe = h end
function Rahmen:GetWidth() return rawget(self, "breite") or 660 end
function Rahmen:GetHeight() return rawget(self, "hoehe") or 400 end
function Rahmen:GetSize() return self:GetWidth(), self:GetHeight() end
function Rahmen:Click() if self.skripte.OnClick then self.skripte.OnClick(self, "LeftButton") end end

function CreateFrame(_, name)
  local r = setmetatable({ skripte = {}, ereignisse = {}, gezeigt = true, an = true }, Rahmen)
  S.rahmen[#S.rahmen + 1] = r
  if name then _G[name] = r end
  return r
end

function S.Ereignis(e, ...)
  for _, r in ipairs(S.rahmen) do
    if r.ereignisse[e] and r.skripte.OnEvent then r.skripte.OnEvent(r, e, ...) end
  end
end

S.bekannt = {}
for _, e in ipairs({
  "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "GET_ITEM_INFO_RECEIVED",
  "ITEM_DATA_LOAD_RESULT", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED",
  "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "NEW_RECIPE_LEARNED",
}) do S.bekannt[e] = true end

UIParent = CreateFrame("Frame")
MerchantFrame = CreateFrame("Frame")
GameTooltip = CreateFrame("Frame")
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
function HandleModifiedItemClick() return false end
function print(...)
  local teile = {}
  for i = 1, select("#", ...) do teile[i] = tostring((select(i, ...))) end
  S.ausgabe[#S.ausgabe + 1] = table.concat(teile, " ")
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) print(text) end }
function GetBuildInfo() return "1.60.1", "70938", "Nov 12 2026", 16001 end
function UnitName() return S.npc or "Testhändler" end
function GetRealZoneText() return "Testzone" end

S.geld = 1000000
function GetMoney() return S.geld end

Enum = {
  AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
  AuctionHouseFilter = {
    PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8, RareQuality = 9,
    EpicQuality = 10, LegendaryQuality = 11, ArtifactQuality = 12,
  },
  AuctionHouseError = { NotEnoughMoney = 0, ItemNotFound = 4, IsBusy = 7 },
}

---------------------------------------------------------------- Gegenstände

-- S.dinge[itemID] = { name, verkauf (Händler zahlt), stapel }
S.dinge, S.geladen = {}, {}

local function Link(itemID, name) return ("|cffffffff|Hitem:%d::::::::30:::::|h[%s]|h|r"):format(itemID, name) end
S.Link = Link

C_Item = {}
function C_Item.GetItemInfo(was)
  local itemID, nameImLink = was, nil
  if type(was) == "string" then
    itemID, nameImLink = tonumber(was:match("item:(%d+)")), was:match("%[(.-)%]")
  end
  local d = S.dinge[itemID]
  if not d then return nil end
  if not S.geladen[itemID] then
    -- wie im Spiel: erster Zugriff liefert nichts, die Daten kommen kurz danach
    if S.geladen[itemID] == nil then
      S.geladen[itemID] = false
      C_Timer.After(0.3, function()
        S.geladen[itemID] = true
        S.Ereignis("GET_ITEM_INFO_RECEIVED", itemID, true)
      end)
    end
    return nil
  end
  local name = nameImLink or d.name
  -- Ausführungen mit Zusatz im Namen dürfen einen eigenen Händlerpreis haben
  local verkauf = d.verkaufNachName and d.verkaufNachName[name] or d.verkauf
  return name, Link(itemID, name), 1, 10, 1, "", "", d.stapel or 1, "", 134400, verkauf
end
function C_Item.RequestLoadItemDataByID(itemID) C_Item.GetItemInfo(itemID) end
function C_Item.GetItemMaxStackSizeByID(itemID) return S.dinge[itemID] and S.dinge[itemID].stapel or 1 end

---------------------------------------------------------------- Auktionshaus

-- S.markt: Liste von Zeilen { key = {itemID, itemLevel, itemSuffix}, ware = bool,
--   stufen = { {preis, menge, eigen} }            (Handelsware)
--   lose   = { {auctionID, preis, link, eigen} }  (Einzelstücke)
S.markt = {}
S.seite = 500
local bereit, angebot = true, nil
local stoebern = { voll = true, zeilen = {}, geliefert = 0 }

-- Lese-Anfragen müssen warten, bis das Spiel bereit ist. Käufe dürfen jederzeit kommen:
-- das Spiel stellt sie selbst in die Warteschlange (so macht es auch Blizzards Fenster).
local function Drossel(kauf)
  assert(bereit or kauf, "Lese-Anfrage gesendet, obwohl das Auktionshaus nicht bereit war")
  bereit = false
  S.gesendet[#S.gesendet + 1] = S.jetzt
  C_Timer.After(0.3, function()
    bereit = true
    S.Ereignis("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  end)
end

-- S.verkaufsSucheLeer[itemID]: die Suche über alle Ausführungen findet hier nichts.
local leereSuche = {}
-- Nach einer Suche über alle Ausführungen (SendSellSearchQuery) zählt nur die Gegenstandsnummer.
local alleAusfuehrungen = {}
local function MarktZeile(key)
  for _, z in ipairs(S.markt) do
    if z.key.itemID == key.itemID
        and (alleAusfuehrungen[key.itemID] or z.key.itemSuffix == (key.itemSuffix or 0)) then
      return z
    end
  end
end

local function Uebersicht(z)
  local min, menge = nil, 0
  for _, s in ipairs(z.stufen or {}) do
    if s.menge > 0 then
      menge = menge + s.menge
      if not min or s.preis < min then min = s.preis end
    end
  end
  for _, l in ipairs(z.lose or {}) do
    menge = menge + 1
    if not min or l.preis < min then min = l.preis end
  end
  return { itemKey = z.key, minPrice = min or 0, totalQuantity = menge, containsOwnerItem = false }
end

local function Seite()
  local teil = {}
  for i = stoebern.geliefert + 1, math.min(stoebern.geliefert + S.seite, #stoebern.zeilen) do
    teil[#teil + 1] = stoebern.zeilen[i]
  end
  stoebern.geliefert = stoebern.geliefert + #teil
  stoebern.voll = stoebern.geliefert >= #stoebern.zeilen
  return teil
end

C_AuctionHouse = {}
function C_AuctionHouse.IsThrottledMessageSystemReady() return bereit end
function C_AuctionHouse.SendBrowseQuery(anfrage)
  assert(anfrage.searchString == "" and #anfrage.sorts == 2 and #anfrage.filters > 0)
  Drossel()
  stoebern = { voll = false, zeilen = {}, geliefert = 0 }
  for _, z in ipairs(S.markt) do stoebern.zeilen[#stoebern.zeilen + 1] = Uebersicht(z) end
  C_Timer.After(0.2, function()
    stoebern.alle = Seite()
    -- das Spiel meldet solche Ereignisse doppelt
    S.Ereignis("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    S.Ereignis("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  end)
end
function C_AuctionHouse.GetBrowseResults() return stoebern.alle or {} end
function C_AuctionHouse.HasFullBrowseResults() return stoebern.voll end
function C_AuctionHouse.RequestMoreBrowseResults()
  Drossel()
  C_Timer.After(0.2, function()
    local teil = Seite()
    for _, e in ipairs(teil) do stoebern.alle[#stoebern.alle + 1] = e end
    S.Ereignis("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", teil)
  end)
end
function C_AuctionHouse.GetItemKeyInfo(key)
  local d = S.dinge[key.itemID]
  local z = MarktZeile(key)
  return d and { itemID = key.itemID, itemName = d.name, isCommodity = z and z.ware or false }
end
function C_AuctionHouse.SendSearchQuery(key, sorts, getrennt)
  assert(type(sorts) == "table" and getrennt == false)
  Drossel()
  leereSuche[key.itemID] = nil
  local z = MarktZeile(key)
  if S.stumm and S.stumm[key.itemID] then return end
  C_Timer.After(0.2, function()
    if z and z.ware then
      S.Ereignis("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
      S.Ereignis("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
    else
      S.Ereignis("ITEM_SEARCH_RESULTS_UPDATED", key)
      S.Ereignis("ITEM_SEARCH_RESULTS_UPDATED", key)
    end
  end)
end
function C_AuctionHouse.SendSellSearchQuery(key, sorts, getrennt)
  local leer = S.verkaufsSucheLeer and S.verkaufsSucheLeer[key.itemID]
  if not leer then alleAusfuehrungen[key.itemID] = true end
  S.verkaufsSuchen = (S.verkaufsSuchen or 0) + 1
  C_AuctionHouse.SendSearchQuery(key, sorts, getrennt)
  leereSuche[key.itemID] = leer or nil
end
function C_AuctionHouse.MakeItemKey(itemID)
  return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end
function C_AuctionHouse.GetItemCommodityStatus(itemID)
  for _, z in ipairs(S.markt) do
    if z.key.itemID == itemID then return z.ware and 2 or 1 end
  end
  return 0
end
local function Stufen(itemID)
  local z = MarktZeile({ itemID = itemID })
  local liste = {}
  for _, s in ipairs(z and z.stufen or {}) do
    if s.menge > 0 then liste[#liste + 1] = s end
  end
  table.sort(liste, function(a, b) return a.preis < b.preis end)
  return liste
end
function C_AuctionHouse.GetNumCommoditySearchResults(itemID) return #Stufen(itemID) end
function C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
  local s = Stufen(itemID)[i]
  return s and {
    itemID = itemID, quantity = s.menge, unitPrice = s.preis, auctionID = 9000 + i,
    numOwnerItems = s.eigen or 0, containsOwnerItem = (s.eigen or 0) > 0, owners = {},
  }
end
function C_AuctionHouse.GetNumItemSearchResults(key)
  if leereSuche[key.itemID] then return 0 end
  local z = MarktZeile(key)
  return z and #(z.lose or {}) or 0
end
function C_AuctionHouse.GetItemSearchResultInfo(key, i)
  local l = MarktZeile(key).lose[i]
  return l and {
    itemKey = key, auctionID = l.auctionID, quantity = l.anzahl or 1, itemLink = l.link,
    buyoutAmount = l.preis, containsOwnerItem = l.eigen or false, owners = {},
  }
end

-- Was der Server für die billigsten n Stück wirklich verlangt (eigene Ware ausgenommen).
local function Gesamtpreis(itemID, menge)
  local summe, rest = 0, menge
  for _, s in ipairs(Stufen(itemID)) do
    local nimm = math.min(rest, s.menge - (s.eigen or 0))
    summe, rest = summe + nimm * s.preis, rest - nimm
    if rest == 0 then return summe end
  end
end
function C_AuctionHouse.StartCommoditiesPurchase(itemID, menge)
  Drossel(true)
  angebot = { itemID = itemID, menge = menge }
  C_Timer.After(0.2, function()
    if not angebot then return end
    local summe = Gesamtpreis(itemID, menge)
    if summe then
      S.Ereignis("COMMODITY_PRICE_UPDATED", math.ceil(summe / menge), summe)
    else
      S.Ereignis("COMMODITY_PRICE_UNAVAILABLE")
    end
  end)
end
function C_AuctionHouse.CancelCommoditiesPurchase() angebot = nil; S.abgebrochen = (S.abgebrochen or 0) + 1 end
function C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, menge)
  assert(angebot and angebot.itemID == itemID and angebot.menge == menge, "Bestätigung passt nicht zum Angebot")
  angebot = nil
  C_Timer.After(0.2, function()
    local summe = Gesamtpreis(itemID, menge)
    if not summe or S.geld < summe then return S.Ereignis("COMMODITY_PURCHASE_FAILED") end
    S.geld = S.geld - summe
    local rest = menge
    for _, s in ipairs(Stufen(itemID)) do
      local nimm = math.min(rest, s.menge - (s.eigen or 0))
      s.menge, rest = s.menge - nimm, rest - nimm
    end
    S.Ereignis("COMMODITY_PURCHASE_SUCCEEDED")
  end)
end
function C_AuctionHouse.PlaceBid(auctionID, betrag)
  Drossel(true)
  S.gebote = S.gebote or {}
  S.gebote[#S.gebote + 1] = { auctionID = auctionID, betrag = betrag }
  C_Timer.After(0.2, function()
    for _, z in ipairs(S.markt) do
      for i, l in ipairs(z.lose or {}) do
        if l.auctionID == auctionID and not l.schonWeg then
          assert(l.preis == betrag, "Gebot weicht vom Sofortkaufpreis ab")
          -- Zusammengefasste Zeile: ein Stück weg, der Rest bekommt eine neue Auktionsnummer.
          if (l.anzahl or 1) > 1 then
            l.anzahl, l.auctionID = l.anzahl - 1, l.auctionID + 10000
          else
            table.remove(z.lose, i)
          end
          S.geld = S.geld - betrag
          return S.Ereignis("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
        end
      end
    end
    S.Ereignis("AUCTION_HOUSE_SHOW_ERROR", Enum.AuctionHouseError.ItemNotFound)
  end)
end

---------------------------------------------------------------- Händler und Taschen

S.haendler = {} -- { itemID, price, stackCount, numAvailable, hasExtendedCost }
function GetMerchantNumItems() return #S.haendler end
function GetMerchantItemID(i) return S.haendler[i].itemID end
C_MerchantFrame = {}
function C_MerchantFrame.GetItemInfo(i) return S.haendler[i] end

S.taschen = { [0] = {} } -- S.taschen[tasche][platz] = { itemID, name, anzahl, gebunden }
S.verkauft = {}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0
C_Container = {}
function C_Container.GetContainerNumSlots(t) return S.taschen[t] and 16 or 0 end
function C_Container.GetContainerItemInfo(t, p)
  local e = S.taschen[t] and S.taschen[t][p]
  return e and {
    itemID = e.itemID, stackCount = e.anzahl, hyperlink = Link(e.itemID, e.name), itemName = e.name,
    isBound = e.gebunden or false, isLocked = false, hasNoValue = false,
  }
end
function C_Container.UseContainerItem(t, p)
  local e = S.taschen[t][p]
  S.verkauft[#S.verkauft + 1] = e
  S.taschen[t][p] = nil
end

return S
