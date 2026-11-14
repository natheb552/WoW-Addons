-- Preisanker: Kaufen. Jeder Kauf braucht einen Klick des Spielers; das Addon kauft nie von allein.
--   Einzelstück:  Klick → Sofortkauf des Loses.
--   Handelsware:  Klick → Preisangebot vom Server → zweiter Klick bestätigt (oder automatisch,
--                 wenn »/pa auto« an ist und das Angebot den erwarteten Gewinn hält).

local ADDON, ns = ...
local AH = C_AuctionHouse

local FEHLER = {
  NotEnoughMoney = "Nicht genug Geld.",
  ItemNotFound = "Die Auktion gibt es nicht mehr.",
  IsBusy = "Das Auktionshaus ist beschäftigt.",
  Unavailable = "Das Auktionshaus ist gerade nicht verfügbar.",
  HasRestriction = "Das Konto darf im Auktionshaus gerade nicht handeln.",
  DatabaseError = "Fehler im Auktionshaus.",
}

local function FehlerText(code)
  for name, wert in pairs(Enum.AuctionHouseError or {}) do
    if wert == code then return FEHLER[name] or ("Auktionshaus-Fehler: " .. name) end
  end
  return "Auktionshaus-Fehler " .. tostring(code)
end

local function Verbuchen(g, name, anzahl, kosten)
  local db = ns.db
  local k = g.itemID .. "|" .. (name or g.name)
  db.offen[k] = (db.offen[k] or 0) + anzahl
  db.bilanz.ausgegeben = db.bilanz.ausgegeben + kosten
end

-- Nimmt ein Los aus dem Geschäft und rechnet den Rest neu.
local function LosEntfernen(g, los)
  for i, l in ipairs(g.lose) do
    if l == los then table.remove(g.lose, i) break end
  end
  g.lose, g.kosten, g.gewinn, g.menge = ns.Lose(g.lose)
  g.status = g.menge > 0 and "bereit" or "gekauft"
end

-- Aufruf nur aus dem Klick auf den Knopf einer Zeile.
function ns.Kaufen(g)
  if not ns.ahOffen then return ns.Sag("Das Auktionshaus ist geschlossen.") end
  local kauf = ns.kauf
  if kauf then
    if kauf.g == g and kauf.phase == "bestaetigen" then
      kauf.phase, kauf.seit, g.status = "kauft", GetTime(), "kauft"
      AH.ConfirmCommoditiesPurchase(g.itemID, kauf.menge)
      ns.Neu()
    end
    return
  end
  if g.status ~= "bereit" then return end
  if ns.scan then return ns.Sag("Der Scan läuft noch.") end
  if g.art == "ware" then
    if GetMoney() < g.kosten then return ns.Sag("Nicht genug Geld.") end
    ns.kauf = { g = g, art = "ware", phase = "angebot", menge = g.menge, seit = GetTime() }
    g.status = "angebot"
    AH.StartCommoditiesPurchase(g.itemID, g.menge)
  else
    local los = g.lose and g.lose[1]
    if not los then return end
    if GetMoney() < los.preis then return ns.Sag("Nicht genug Geld.") end
    ns.kauf = { g = g, art = "los", phase = "kauft", los = los, seit = GetTime() }
    g.status = "kauft"
    AH.PlaceBid(los.auctionID, los.preis)
  end
  ns.Neu()
end

local function WareAbbrechen(grund)
  local kauf = ns.kauf
  if not (kauf and kauf.art == "ware") then return end
  if kauf.phase ~= "kauft" then AH.CancelCommoditiesPurchase() end
  ns.kauf = nil
  ns.NeuPruefen(kauf.g)
  if grund then ns.Sag((kauf.g.name or "?") .. ": " .. grund) end
end

ns.Bei("COMMODITY_PRICE_UPDATED", function(_, gesamt)
  local kauf = ns.kauf
  if not (kauf and kauf.art == "ware" and kauf.phase == "angebot") then return end
  local g = kauf.g
  local gewinn = g.wert * kauf.menge - gesamt
  -- Der Server nennt den echten Gesamtpreis. Nur weiter, wenn der Gewinn noch stimmt.
  if gewinn < math.max(1, ns.opt.minGewinn) then
    return WareAbbrechen("Der Preis hat sich geändert, wird neu geprüft.")
  end
  g.kosten, g.gewinn, kauf.kosten, kauf.seit = gesamt, gewinn, gesamt, GetTime()
  if ns.opt.autoBestaetigen then
    kauf.phase, g.status = "kauft", "kauft"
    AH.ConfirmCommoditiesPurchase(g.itemID, kauf.menge)
  else
    kauf.phase, g.status = "bestaetigen", "bestaetigen"
  end
  ns.Neu()
end)

ns.Bei("COMMODITY_PRICE_UNAVAILABLE", function()
  WareAbbrechen("Kein Preisangebot, wird neu geprüft.")
end)

ns.Bei("COMMODITY_PURCHASE_SUCCEEDED", function()
  local kauf = ns.kauf
  if not (kauf and kauf.art == "ware" and kauf.phase == "kauft") then return end
  Verbuchen(kauf.g, kauf.g.name, kauf.menge, kauf.kosten)
  ns.kauf = nil
  ns.NeuPruefen(kauf.g) -- vielleicht liegt noch mehr unter dem Händlerpreis
end)

ns.Bei("COMMODITY_PURCHASE_FAILED", function()
  local kauf = ns.kauf
  if not (kauf and kauf.art == "ware" and kauf.phase == "kauft") then return end
  ns.kauf = nil
  ns.NeuPruefen(kauf.g)
  ns.Sag((kauf.g.name or "?") .. ": Kauf fehlgeschlagen, wird neu geprüft.")
end)

ns.Bei("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
  local kauf = ns.kauf
  if not (kauf and kauf.art == "los" and kauf.los.auctionID == auctionID) then return end
  local g, los = kauf.g, kauf.los
  -- Ein Kauf holt ein Stück, auch wenn die Zeile mehrere gleiche Auktionen zusammenfasst.
  Verbuchen(g, ns.NameAusLink(los.link), 1, los.preis)
  ns.kauf = nil
  if (los.anzahl or 1) > 1 then
    -- Die übrigen Stücke haben eine andere Auktionsnummer: neu nachschlagen.
    los.anzahl = los.anzahl - 1
    g.lose, g.kosten, g.gewinn, g.menge = ns.Lose(g.lose)
    ns.NeuPruefen(g)
  else
    LosEntfernen(g, los)
  end
  ns.Neu()
end)

ns.Bei("AUCTION_HOUSE_SHOW_ERROR", function(code)
  local kauf = ns.kauf
  if not kauf then return end
  if kauf.art == "los" then
    ns.kauf = nil
    LosEntfernen(kauf.g, kauf.los)
    ns.Sag((kauf.g.name or "?") .. ": " .. FehlerText(code))
    ns.Neu()
  else
    WareAbbrechen(FehlerText(code))
  end
end)

-- Läuft im Takt mit: räumt auf, wenn der Server nicht antwortet oder der Spieler nicht bestätigt.
function ns.KaufWache()
  local kauf = ns.kauf
  if not kauf then return end
  local alt = GetTime() - kauf.seit
  if kauf.phase == "angebot" and alt > 8 then
    WareAbbrechen("Kein Preisangebot erhalten.")
  elseif kauf.phase == "bestaetigen" and alt > 25 then
    WareAbbrechen("Nicht bestätigt, Angebot verfallen.")
  elseif kauf.phase == "kauft" and alt > 10 then
    ns.kauf = nil
    ns.NeuPruefen(kauf.g)
    ns.Sag((kauf.g.name or "?") .. ": keine Rückmeldung zum Kauf. Bitte im Briefkasten nachsehen.")
  end
end

function ns.KaufAbbrechen()
  local kauf = ns.kauf
  if not kauf then return end
  if kauf.art == "ware" and kauf.phase ~= "kauft" then AH.CancelCommoditiesPurchase() end
  ns.kauf = nil
  kauf.g.status = "offen"
end
