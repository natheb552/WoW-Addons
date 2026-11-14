-- Preisanker: Rechenkern ohne Spiel-API (läuft auch im Test außerhalb des Spiels).
--
-- Die Idee: NPC-Händler zahlen und verlangen feste Preise, Spieler im Auktionshaus nicht.
--   1. Liegt eine Auktion UNTER dem Preis, den ein Händler dafür zahlt, ist Kaufen und
--      beim Händler Verkaufen ein sicherer Gewinn.
--   2. Liegt der Auktionspreis ÜBER dem Preis, zu dem ein Händler die Ware verkauft,
--      lohnt Einkaufen beim Händler und Einstellen im Auktionshaus.

local ADDON, ns = ...

ns.GEBUEHR = 0.05 -- Anteil, den das Auktionshaus vom Verkaufspreis behält

ns.standard = {
  minGewinn = 100,    -- Kupfer: kleinster Gewinn, ab dem ein Geschäft gezeigt wird
  maxStapel = 20,     -- so viele Stapel einer Handelsware höchstens auf einmal kaufen
  mitAuktionshaus = true, -- Fenster zusammen mit dem Auktionshaus öffnen
  autoBestaetigen = false, -- Handelsware nach dem Preisangebot ohne zweiten Klick kaufen
}

-- 12345 → "1g 23s 45k"
function ns.Geld(kupfer)
  kupfer = math.floor((kupfer or 0) + 0.5)
  local minus = kupfer < 0 and "-" or ""
  if kupfer < 0 then kupfer = -kupfer end
  local g, s, k = math.floor(kupfer / 10000), math.floor(kupfer / 100) % 100, kupfer % 100
  if g > 0 then return ("%s%d|cffffd100g|r %d|cffc7c7cfs|r"):format(minus, g, s) end
  if s > 0 then return ("%s%d|cffc7c7cfs|r %d|cffeda55fk|r"):format(minus, s, k) end
  return ("%s%d|cffeda55fk|r"):format(minus, k)
end

-- "5s", "1g 20s", "1g20s5k", "250" (Kupfer) → Kupfer; nil bei Unsinn
function ns.GeldLesen(text)
  text = (text or ""):lower():gsub("%s+", "")
  if text == "" then return nil end
  if text:match("^%d+$") then return tonumber(text) end
  local summe, rest = 0, text
  for zahl, einheit in text:gmatch("(%d+)([gsk])") do
    summe = summe + tonumber(zahl) * (einheit == "g" and 10000 or einheit == "s" and 100 or 1)
  end
  rest = text:gsub("%d+[gsk]", "")
  if rest ~= "" then return nil end
  return summe
end

-- Schlüssel einer Zeile des Auktionshauses (Gegenstand + Stufe + Zufallsverzauberung).
function ns.Schluessel(itemKey)
  return ("%d:%d:%d"):format(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
end

-- Name aus einem Gegenstands-Link: "|Hitem:..|h[Name]|h" → "Name"
function ns.NameAusLink(link)
  return link and link:match("%[(.-)%]") or nil
end

-- Handelsware: Preisstufen {preis=Stückpreis, menge=Anzahl}, billigste zuerst.
-- Liefert, wie viele Stück unter dem Händlerpreis liegen, was sie kosten und was sie bringen.
-- maxMenge und maxKosten begrenzen den Einkauf (Taschenplatz, Geldbeutel).
function ns.Handelsware(stufen, haendlerPreis, maxMenge, maxKosten)
  local menge, kosten = 0, 0
  for _, stufe in ipairs(stufen) do
    if stufe.preis >= haendlerPreis then break end
    local nimm = stufe.menge
    if maxMenge then nimm = math.min(nimm, maxMenge - menge) end
    if maxKosten then nimm = math.min(nimm, math.floor((maxKosten - kosten) / stufe.preis)) end
    if nimm <= 0 then break end
    menge, kosten = menge + nimm, kosten + nimm * stufe.preis
    if nimm < stufe.menge then break end
  end
  return menge, kosten, menge * haendlerPreis - kosten
end

-- Einzelstücke: Lose {preis=Sofortkauf, wert=Händlerpreis des Loses, ...}.
-- Behält nur Lose mit Gewinn, die teuersten Gewinne zuerst.
function ns.Lose(lose)
  local gut, kosten, gewinn = {}, 0, 0
  for _, los in ipairs(lose) do
    if los.preis > 0 and los.wert > los.preis then
      gut[#gut + 1] = los
      kosten, gewinn = kosten + los.preis, gewinn + (los.wert - los.preis)
    end
  end
  table.sort(gut, function(a, b) return (a.wert - a.preis) > (b.wert - b.preis) end)
  return gut, kosten, gewinn
end

-- Händlerware: Gewinn je Stück, wenn man beim Händler kauft und zum billigsten
-- Auktionspreis einstellt (abzüglich Gebühr des Auktionshauses).
function ns.HaendlerMarge(auktionsPreis, haendlerPreis)
  return math.floor(auktionsPreis * (1 - ns.GEBUEHR)) - haendlerPreis
end

-- Sortiert Geschäfte: Geprüftes mit dem größten Gewinn zuerst, Ungeprüftes danach.
function ns.Sortieren(liste)
  table.sort(liste, function(a, b)
    local ag, bg = a.geprueft and 1 or 0, b.geprueft and 1 or 0
    if ag ~= bg then return ag > bg end
    if a.gewinn ~= b.gewinn then return a.gewinn > b.gewinn end
    return a.id < b.id
  end)
  return liste
end
