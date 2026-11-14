-- Preisanker: Händler.
--   Lernen:    Bei jedem Händlerbesuch merkt sich das Addon, was er zu welchem Preis verkauft.
--              Daraus entsteht die Liste »Händlerware«, ohne dass eine Datenbank nötig ist.
--   Verkaufen: Ein Knopf am Händlerfenster verkauft, was über Preisanker ersteigert wurde.

local ADDON, hp = ...
hp.anker = hp.anker or {}
local ns = hp.anker -- eigener Namensraum im Addon Händlerprofit

-- Werte, die das Spiel im Kampf unlesbar macht, nicht anfassen.
local function Klar(wert)
  if issecretvalue and issecretvalue(wert) then return nil end
  return wert
end

---------------------------------------------------------------- Lernen

local function Lernen()
  if not (ns.db and ns.haendlerOffen) then return end
  local wer = Klar(UnitName("npc")) or "Händler"
  local zone = GetRealZoneText or GetZoneText
  local wo = zone and Klar(zone()) or ""
  for i = 1, GetMerchantNumItems() do
    local info = C_MerchantFrame.GetItemInfo(i)
    local itemID = GetMerchantItemID(i)
    -- Nur Ware gegen Geld; Marken und andere Währungen lassen sich nicht in Gold rechnen.
    if info and itemID and (info.price or 0) > 0 and not info.hasExtendedCost and not info.currencyID then
      local stueck = math.ceil(info.price / math.max(1, info.stackCount or 1))
      local alt = ns.db.haendler[itemID]
      if not alt or stueck <= alt.p or alt.wer == wer then
        ns.db.haendler[itemID] = { p = stueck, n = info.numAvailable or -1, wer = wer, wo = wo, t = time() }
      end
    end
  end
end

---------------------------------------------------------------- Verkaufen

function ns.OffeneTeile()
  local summe = 0
  for _, n in pairs(ns.db and ns.db.offen or {}) do summe = summe + n end
  return summe
end

-- Taschenplätze, die zu den Einkäufen passen. Gebundenes und Stapel, in denen mehr liegt
-- als eingekauft wurde, bleiben unangetastet.
local function Verkaufsliste()
  local liste, rest = {}, {}
  for k, n in pairs(ns.db.offen) do rest[k] = n end
  for tasche = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for platz = 1, C_Container.GetContainerNumSlots(tasche) or 0 do
      local info = C_Container.GetContainerItemInfo(tasche, platz)
      if info and info.itemID and not info.isBound and not info.isLocked and not info.hasNoValue then
        local anzahl = info.stackCount or 1
        local k = info.itemID .. "|" .. (ns.NameAusLink(info.hyperlink) or info.itemName or "")
        if rest[k] and rest[k] >= anzahl then
          rest[k] = rest[k] - anzahl
          liste[#liste + 1] = {
            tasche = tasche, platz = platz, k = k, anzahl = anzahl,
            itemID = info.itemID, link = info.hyperlink,
          }
        end
      end
    end
  end
  return liste
end

local laeuft

function ns.Verkaufen()
  if laeuft then return end
  if not ns.haendlerOffen then return ns.Sag("Dafür muss ein Händlerfenster offen sein.") end
  local liste = Verkaufsliste()
  if #liste == 0 then
    return ns.Sag("Nichts Passendes in den Taschen. Liegen die Einkäufe noch im Briefkasten?")
  end
  local i, erloes, teile = 0, 0, 0
  laeuft = C_Timer.NewTicker(0.25, function(ticker)
    i = i + 1
    local e = liste[i]
    if not e or not ns.haendlerOffen then
      ticker:Cancel()
      laeuft = nil
      ns.Sag(("%d Teile verkauft für %s. Noch offen: %d."):format(teile, ns.Geld(erloes), ns.OffeneTeile()))
      if ns.HaendlerKnopf then ns.HaendlerKnopf() end
      ns.Neu()
      return
    end
    -- Der Platz muss noch denselben Stapel enthalten wie beim Zusammenstellen der Liste.
    local info = C_Container.GetContainerItemInfo(e.tasche, e.platz)
    if info and info.itemID == e.itemID and (info.stackCount or 1) == e.anzahl and not info.isLocked then
      local preis = select(11, C_Item.GetItemInfo(e.link or e.itemID)) or ns.db.vk[e.itemID] or 0
      C_Container.UseContainerItem(e.tasche, e.platz)
      local offen = (ns.db.offen[e.k] or 0) - e.anzahl
      ns.db.offen[e.k] = offen > 0 and offen or nil
      ns.db.bilanz.erloest = ns.db.bilanz.erloest + preis * e.anzahl
      erloes, teile = erloes + preis * e.anzahl, teile + e.anzahl
    end
  end)
end

---------------------------------------------------------------- Knopf am Händlerfenster

local knopf

function ns.HaendlerKnopf()
  local offen = ns.OffeneTeile()
  if not knopf then
    if offen == 0 or not MerchantFrame then return end
    knopf = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
    knopf:SetSize(230, 22)
    knopf:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 0, 2)
    knopf:SetScript("OnClick", ns.Verkaufen)
  end
  knopf:SetText(("Preisanker: %d Teile verkaufen"):format(offen))
  knopf:SetShown(offen > 0)
end

local lernenGeplant

ns.Bei("MERCHANT_SHOW", function()
  ns.haendlerOffen = true
  Lernen()
  ns.HaendlerKnopf()
end)

-- Kommt oft hintereinander (Vorrat, Filter): gebündelt einmal nachlernen.
ns.Bei("MERCHANT_UPDATE", function()
  if lernenGeplant then return end
  lernenGeplant = true
  C_Timer.After(0.5, function()
    lernenGeplant = false
    Lernen()
  end)
end)

ns.Bei("MERCHANT_CLOSED", function()
  ns.haendlerOffen = false
end)
