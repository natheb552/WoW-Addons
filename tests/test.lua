-- Test von Händlerprofit (mit Preisanker) gegen die nachgebaute Spiel-API.
-- Aufruf: lua5.1 tests/test.lua  (aus wow-addons/)

local echo = print
package.path = "tests/?.lua;" .. package.path
local S = require("spiel")

-- Statt Data.lua: zwei Rezepte. [Zauber] = { Item, Anzahl, Beruf, Reagenz, Menge, ... }
local hp = {
  RECIPES = {
    [9001] = { 400, 1, 165, 100, 4 },         -- Lederweste aus 4 Leichtem Leder
    [9002] = { 401, 1, 165, 100, 2, 300, 1 }, -- Lederband aus 2 Leder und 1 Faden (Händlerware)
  },
  COOLDOWNS = {},
}
for _, datei in ipairs({ "Core", "Preisanker/Kern", "Preisanker/Scan", "Preisanker/Kauf",
    "Preisanker/Haendler", "Preisanker/Fenster", "UI" }) do
  assert(loadfile("Haendlerprofit/" .. datei .. ".lua"))("Haendlerprofit", hp)
end
local ns = hp.anker -- Preisanker

local fehler, geprueft = 0, 0
local function gleich(ist, soll, was)
  geprueft = geprueft + 1
  if ist ~= soll then
    fehler = fehler + 1
    echo(("FEHLER %s: ist %s, soll %s"):format(was, tostring(ist), tostring(soll)))
  end
end
local function ohneFarbe(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function gesagt(muster)
  for _, zeile in ipairs(S.ausgabe) do
    if zeile:find(muster, 1, true) then return true end
  end
  return false
end
local function geschaeft(itemID)
  for _, g in ipairs(ns.geschaefte) do
    if g.itemID == itemID then return g end
  end
end

---------------------------------------------------------------- Rechenkern

gleich(ohneFarbe(ns.Geld(12345)), "1g 23s", "Geld Gold")
gleich(ohneFarbe(ns.Geld(345)), "3s 45k", "Geld Silber")
gleich(ohneFarbe(ns.Geld(7)), "7k", "Geld Kupfer")
gleich(ohneFarbe(ns.Geld(-250)), "-2s 50k", "Geld negativ")
gleich(ns.GeldLesen("5s"), 500, "GeldLesen 5s")
gleich(ns.GeldLesen("1g 20s 5k"), 12005, "GeldLesen gemischt")
gleich(ns.GeldLesen("250"), 250, "GeldLesen Zahl")
gleich(ns.GeldLesen("viel"), nil, "GeldLesen Unsinn")
gleich(ns.GeldLesen("5x"), nil, "GeldLesen falsche Einheit")

do -- Preistreppe: nur Stufen unter dem Händlerpreis
  local stufen = { { preis = 10, menge = 300 }, { preis = 40, menge = 500 }, { preis = 60, menge = 1000 } }
  local m, k, g = ns.Handelsware(stufen, 50)
  gleich(m, 800, "Treppe Menge"); gleich(k, 23000, "Treppe Kosten"); gleich(g, 17000, "Treppe Gewinn")
  m, k, g = ns.Handelsware(stufen, 50, 400)
  gleich(m, 400, "Treppe gedeckelt Menge"); gleich(k, 7000, "Treppe gedeckelt Kosten"); gleich(g, 13000, "Treppe gedeckelt Gewinn")
  m, k = ns.Handelsware(stufen, 50, nil, 3400)
  gleich(m, 310, "Treppe nach Geld Menge"); gleich(k, 3400, "Treppe nach Geld Kosten")
  m = ns.Handelsware(stufen, 10)
  gleich(m, 0, "Treppe: gleicher Preis ist kein Geschäft")
end

do -- Lose: nur mit Gewinn, bester zuerst
  local gut, k, g = ns.Lose({ { preis = 900, wert = 1000 }, { preis = 1000, wert = 1000 }, { preis = 200, wert = 1000 }, { preis = 0, wert = 50 } })
  gleich(#gut, 2, "Lose Anzahl"); gleich(gut[1].preis, 200, "Lose Reihenfolge")
  gleich(k, 1100, "Lose Kosten"); gleich(g, 900, "Lose Gewinn")
  -- Zusammengefasste Zeile: Preis und Wert gelten je Stück.
  local _, k5, g5, n5 = ns.Lose({ { preis = 800, wert = 1000, anzahl = 5 } })
  gleich(k5, 4000, "Lose mit Anzahl: Kosten"); gleich(g5, 1000, "Lose mit Anzahl: Gewinn")
  gleich(n5, 5, "Lose mit Anzahl: Stück")
end
gleich(ns.HaendlerMarge(200, 100), 90, "Händlermarge mit Gebühr")
gleich(ns.HaendlerMarge(105, 100), -1, "Händlermarge knapp negativ")

---------------------------------------------------------------- Markt aufbauen

S.dinge = {
  [100] = { name = "Leichtes Leder", verkauf = 50, stapel = 20 },
  [101] = { name = "Kupfererz", verkauf = 5, stapel = 20 },      -- teurer als beim Händler: kein Geschäft
  [102] = { name = "Schrott", verkauf = 0, stapel = 20 },        -- Händler zahlt nichts
  [103] = { name = "Leinenstoff", verkauf = 13, stapel = 20 },   -- nur 3 Stück, Gewinn zu klein
  [200] = { name = "Banditenhandschuhe", verkauf = 1000,
            verkaufNachName = { ["Banditenhandschuhe des Affen"] = 1200 } },
  [300] = { name = "Feiner Faden", verkauf = 25, stapel = 20 },  -- Händlerware
  [301] = { name = "Rezept: Trank", verkauf = 100 },             -- Händlerware, begrenzt
  [400] = { name = "Lederweste", verkauf = 100 },                -- herstellbar (Rezept 9001)
  [401] = { name = "Lederband", verkauf = 150 },                 -- herstellbar (Rezept 9002)
}
local function Schluessel(itemID, suffix) return { itemID = itemID, itemLevel = 10, itemSuffix = suffix or 0, battlePetSpeciesID = 0 } end
S.markt = {
  { key = Schluessel(100), ware = true, stufen = { { preis = 10, menge = 300 }, { preis = 40, menge = 500, eigen = 100 }, { preis = 60, menge = 1000 } } },
  { key = Schluessel(101), ware = true, stufen = { { preis = 30, menge = 100 } } },
  { key = Schluessel(102), ware = true, stufen = { { preis = 1, menge = 5000 } } },
  { key = Schluessel(103), ware = true, stufen = { { preis = 10, menge = 3 } } },
  { key = Schluessel(200, 5), lose = {
      { auctionID = 1, preis = 500, link = S.Link(200, "Banditenhandschuhe des Affen") },
      { auctionID = 2, preis = 1100, link = S.Link(200, "Banditenhandschuhe des Affen") },
      { auctionID = 3, preis = 1500, link = S.Link(200, "Banditenhandschuhe des Affen") },
      { auctionID = 4, preis = 100, link = S.Link(200, "Banditenhandschuhe des Affen"), eigen = true },
  } },
  { key = Schluessel(300), ware = true, stufen = { { preis = 200, menge = 40 } } },
  { key = Schluessel(301), lose = { { auctionID = 9, preis = 5000, link = S.Link(301, "Rezept: Trank") } } },
}
-- Füllmaterial, damit der Überblick über mehrere Seiten geht
for i = 1, 1200 do
  S.dinge[1000 + i] = { name = "Kram " .. i, verkauf = 10, stapel = 20 }
  S.markt[#S.markt + 1] = { key = Schluessel(1000 + i), ware = true, stufen = { { preis = 500 + i, menge = 5 } } }
end

---------------------------------------------------------------- Start, Händler lernen

S.Ereignis("ADDON_LOADED", "AnderesAddon")
gleich(ns.db, nil, "fremdes ADDON_LOADED ignoriert")
S.Ereignis("ADDON_LOADED", "Haendlerprofit")
S.Ereignis("PLAYER_LOGIN")
gleich(type(HaendlerprofitDB.anker.vk), "table", "Datenbank angelegt")
gleich(hp.PriceSource(), "scan", "ohne Auctionator: eigener Scan als Preisquelle")
HaendlerprofitDB.onlyKnown = false -- im Test ist kein Rezept gelernt
gleich(ns.opt.minGewinn, 100, "Standardwert sichtbar")

S.haendler = {
  { itemID = 300, price = 500, stackCount = 5, numAvailable = -1 },       -- 100 je Stück
  { itemID = 301, price = 2000, stackCount = 1, numAvailable = 1 },
  { itemID = 101, price = 0, stackCount = 1, numAvailable = -1 },         -- ohne Preis: nicht lernen
  { itemID = 100, price = 10, stackCount = 1, numAvailable = -1, hasExtendedCost = true }, -- gegen Marken
}
S.Ereignis("MERCHANT_SHOW")
gleich(ns.db.haendler[300].p, 100, "Händlerpreis je Stück gelernt")
gleich(ns.db.haendler[301].n, 1, "begrenzter Vorrat gelernt")
gleich(ns.db.haendler[101], nil, "Ware ohne Preis nicht gelernt")
gleich(ns.db.haendler[100], nil, "Ware gegen Marken nicht gelernt")
S.Ereignis("MERCHANT_CLOSED")

---------------------------------------------------------------- Scan

SlashCmdList.PREISANKER("scan")
gleich(gesagt("Erst das Auktionshaus öffnen"), true, "Scan ohne Auktionshaus abgelehnt")

S.Ereignis("AUCTION_HOUSE_SHOW")
gleich(hp.IsShown(), true, "Fenster öffnet mit dem Auktionshaus")
gleich(HaendlerprofitPreisanker:IsShown(), true, "Reiter Unter Händlerpreis gewählt")
gleich(#hp.Compute(true), 0, "vor dem Scan: keine Preise, kein Rezept")
HaendlerprofitPreisanker.scanKnopf:Click()
gleich(ns.scan ~= nil, true, "Scan läuft")
S.Warten(3)
gleich(ns.zahl.zeilen, 1207, "alle Zeilen aus drei Seiten gelesen")
S.Warten(12)
gleich(ns.scan, nil, "Scan beendet")
gleich(ns.db.vk[100], 50, "Händlerpreis gemerkt")

-- Kandidaten: 100 (Leder) und 200 (Handschuhe); 103 ist zu klein und wird gar nicht erst geprüft
gleich(geschaeft(101), nil, "teurer als Händler: kein Kandidat")
gleich(geschaeft(102), nil, "Händlerpreis 0: kein Kandidat")
gleich(geschaeft(103).status, "weg", "zu kleiner Gewinn aussortiert")
S.Warten(4)

local leder, handschuhe = geschaeft(100), geschaeft(200)
gleich(leder.status, "bereit", "Leder bereit")
gleich(leder.art, "ware", "Leder ist Handelsware")
-- 20 Stapel x 20 = 400 Stück: 300 zu 10 und 100 zu 40 (von 400 fremden auf der Stufe)
gleich(leder.menge, 400, "Leder Menge (Deckel 20 Stapel)")
gleich(leder.kosten, 7000, "Leder Kosten")
gleich(leder.gewinn, 13000, "Leder Gewinn")
gleich(handschuhe.status, "bereit", "Handschuhe bereit")
gleich(handschuhe.menge, 2, "Handschuhe: zwei Lose mit Gewinn (eigenes und teures nicht)")
gleich(handschuhe.gewinn, 800, "Handschuhe Gewinn nach Preis der Ausführung (1200)")
gleich(handschuhe.name, "Banditenhandschuhe des Affen", "Name der Ausführung übernommen")

gleich(#ns.haendlerware, 2, "zwei Händlerwaren mit Gewinn")
gleich(ns.haendlerware[1].itemID, 301, "Rezept zuerst (größter Gewinn)")
gleich(ns.haendlerware[1].marge, 2750, "Rezept: 5000 x 0,95 - 2000")
gleich(ns.haendlerware[2].marge, 90, "Faden: 200 x 0,95 - 100")

-- Drossel: nie mehr als 100 Suchen je Minute, hier grob über den Abstand geprüft
for i = 2, #S.gesendet do
  if S.gesendet[i] - S.gesendet[i - 1] < 0.29 then gleich("zu dicht", "Abstand", "Anfragen-Abstand") end
end

-- Fenster zeichnet beide Listen ohne Fehler
S.Warten(0.2)
SlashCmdList.PREISANKER("info")
SlashCmdList.PREISANKER("hilfe")

---------------------------------------------------------------- Herstellen mit Preisen des eigenen Scans

gleich(ns.db.preise[100], 10, "billigster Auktionspreis gemerkt")
hp.Compute(true) -- fordert die Gegenstandsdaten an
S.Warten(0.5)
local rezepte = hp.Compute(true)
gleich(#rezepte, 2, "zwei Rezepte mit Händlergewinn")
gleich(rezepte[1].itemID, 400, "Lederweste zuerst")
gleich(rezepte[1].cost, 40, "Lederweste: 4 Leder zum Scan-Preis")
gleich(rezepte[1].profit, 60, "Lederweste Gewinn")
gleich(rezepte[2].profit, 30, "Lederband Gewinn")
gleich(rezepte[2].parts[2].source, "H", "Faden vom gelernten Händler (billiger als Auktion)")
gleich(rezepte[1].stale, false, "Scan-Preise gelten als aktuell")

-- Reiter wechseln zeichnet beide Teile ohne Fehler
hp.SelectTab(1)
gleich(HaendlerprofitPreisanker:IsShown(), false, "Reiter Herstellen: Preisanker-Listen verborgen")
S.Warten(0.5)
hp.SelectTab(3)
S.Warten(0.2)
SlashCmdList.HAENDLERPROFIT()
gleich(hp.IsShown(), false, "/hp schließt das Fenster")
SlashCmdList.PREISANKER("")
gleich(HaendlerprofitPreisanker:IsShown(), true, "/pa öffnet die Preisanker-Liste")
hp.SelectTab(2)

-- Preisquelle Auctionator: Auktionspreise kommen von dort, Händlerpreise weiter aus beiden
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, itemID) return itemID == 100 and 20 or nil end,
  GetVendorPriceByItemID = function() return nil end,
  GetAuctionAgeByItemID = function() return 0 end,
} } }
HaendlerprofitDB.priceSource = "auctionator"
rezepte = hp.Compute(true)
gleich(#rezepte, 2, "Auctionator: zwei Rezepte")
gleich(rezepte[1].cost, 80, "Auctionator: Lederweste zum Auctionator-Preis")
gleich(rezepte[2].cost, 140, "Auctionator: Faden weiter vom gelernten Händler")
Auctionator, HaendlerprofitDB.priceSource = nil, nil

---------------------------------------------------------------- Kauf Handelsware

local geldVorher = S.geld
ns.Kaufen(leder)
gleich(leder.status, "angebot", "Leder: Angebot angefragt")
S.Warten(0.5)
gleich(leder.status, "bestaetigen", "Leder: wartet auf Bestätigung")
gleich(S.geld, geldVorher, "noch nichts bezahlt")
ns.Kaufen(handschuhe)
gleich(handschuhe.status, "bereit", "während eines Kaufs kein zweiter")
ns.Kaufen(leder)
S.Warten(0.5)
gleich(S.geld, geldVorher - 7000, "Leder bezahlt")
gleich(ns.db.offen["100|Leichtes Leder"], 400, "Leder zum Verkaufen vorgemerkt")
gleich(ns.db.bilanz.ausgegeben, 7000, "Bilanz ausgegeben")
S.Warten(3)
-- Rest: noch 300 fremde Stück zu 40 → Gewinn 3000
gleich(leder.status, "bereit", "Leder: Rest neu geprüft")
gleich(leder.menge, 300, "Leder: Restmenge")
gleich(leder.gewinn, 3000, "Leder: Restgewinn")

-- Preis steigt zwischen Prüfung und Kauf: Abbruch statt Verlust
for _, z in ipairs(S.markt) do
  if z.key.itemID == 100 then z.stufen[2].preis = 55 end
end
geldVorher = S.geld
ns.Kaufen(leder)
S.Warten(0.5)
gleich(S.geld, geldVorher, "bei gestiegenem Preis nichts gekauft")
gleich(gesagt("Der Preis hat sich geändert"), true, "Preisänderung gemeldet")
S.Warten(3)
gleich(leder.status, "weg", "Leder: kein Geschäft mehr")

---------------------------------------------------------------- Kauf Einzelstücke

geldVorher = S.geld
ns.Kaufen(handschuhe)
gleich(handschuhe.status, "kauft", "Handschuhe: Kauf läuft")
S.Warten(0.6)
gleich(S.gebote[1].auctionID, 1, "bestes Los zuerst")
gleich(S.geld, geldVorher - 500, "Los bezahlt")
gleich(handschuhe.menge, 1, "ein Los übrig")
gleich(handschuhe.status, "bereit", "Handschuhe wieder bereit")
gleich(ns.db.offen["200|Banditenhandschuhe des Affen"], 1, "Handschuhe vorgemerkt")
-- Zweites Los hat inzwischen jemand anders gekauft
for _, z in ipairs(S.markt) do
  if z.key.itemID == 200 then z.lose[1].schonWeg = true end
end
ns.Kaufen(handschuhe)
S.Warten(0.6)
gleich(gesagt("Die Auktion gibt es nicht mehr"), true, "Fehler gemeldet")
gleich(handschuhe.status, "gekauft", "Handschuhe erledigt")
gleich(S.geld, geldVorher - 500, "für das verschwundene Los nichts bezahlt")
gleich(ns.kauf, nil, "kein hängender Kauf")

---------------------------------------------------------------- Verkauf beim Händler

S.taschen[0] = {
  [1] = { itemID = 100, name = "Leichtes Leder", anzahl = 20 },
  [2] = { itemID = 100, name = "Leichtes Leder", anzahl = 20 },
  [3] = { itemID = 200, name = "Banditenhandschuhe des Affen", anzahl = 1, gebunden = true }, -- getragen: behalten
  [4] = { itemID = 200, name = "Banditenhandschuhe des Adlers", anzahl = 1 },            -- andere Ausführung: behalten
  [5] = { itemID = 200, name = "Banditenhandschuhe des Affen", anzahl = 1 },
  [6] = { itemID = 101, name = "Kupfererz", anzahl = 20 },                               -- nie gekauft: behalten
}
ns.db.offen["100|Leichtes Leder"] = 30 -- nur noch 30 offen: ein voller Stapel passt, der zweite nicht
ns.Verkaufen()
gleich(gesagt("Händlerfenster offen"), true, "Verkauf ohne Händler abgelehnt")
S.Ereignis("MERCHANT_SHOW")
ns.Verkaufen()
S.Warten(2)
gleich(#S.verkauft, 2, "genau zwei Plätze verkauft")
gleich(S.taschen[0][2] ~= nil, true, "Stapel über der Einkaufsmenge bleibt")
gleich(S.taschen[0][4] ~= nil, true, "andere Ausführung bleibt")
gleich(S.taschen[0][3] ~= nil, true, "Gebundenes bleibt")
gleich(S.taschen[0][5], nil, "ersteigertes Stück verkauft")
gleich(S.taschen[0][6] ~= nil, true, "Fremdes bleibt")
gleich(ns.db.offen["100|Leichtes Leder"], 10, "Rest bleibt vorgemerkt")
gleich(ns.db.offen["200|Banditenhandschuhe des Affen"], nil, "Handschuhe abgehakt")
gleich(ns.db.bilanz.erloest, 20 * 50 + 1200, "Bilanz erlöst")
S.Ereignis("MERCHANT_CLOSED")

---------------------------------------------------------------- Störungen

-- Auktionshaus schließt mitten im Scan
ns.ScanStarten()
S.Warten(0.5)
S.Ereignis("AUCTION_HOUSE_CLOSED")
gleich(ns.scan, nil, "Scan beim Schließen abgebrochen")
S.Warten(3)

-- Einzelsuche ohne Antwort: wird übersprungen, der Rest läuft weiter
S.Ereignis("AUCTION_HOUSE_SHOW")
for _, z in ipairs(S.markt) do
  if z.key.itemID == 100 then z.stufen = { { preis = 10, menge = 100 } } end
  if z.key.itemID == 200 then z.lose = { { auctionID = 7, preis = 300, link = S.Link(200, "Banditenhandschuhe des Affen") } } end
end
S.stumm = { [100] = true }
ns.ScanStarten()
S.Warten(30)
gleich(geschaeft(100).status, "weg", "stumme Suche nach zwei Versuchen aufgegeben")
gleich(geschaeft(200).status, "bereit", "andere Geschäfte trotzdem geprüft")

-- Kauf ohne Bestätigung verfällt und wird abgebrochen
S.stumm = nil
ns.ScanStarten()
S.Warten(20)
leder = geschaeft(100)
gleich(leder.status, "bereit", "Leder wieder bereit")
local abbruch = S.abgebrochen or 0
ns.Kaufen(leder)
S.Warten(30)
gleich(ns.kauf, nil, "unbestätigter Kauf aufgeräumt")
gleich((S.abgebrochen or 0) > abbruch, true, "Angebot beim Server zurückgezogen")

-- Ohne zweiten Klick, wenn eingeschaltet
SlashCmdList.PREISANKER("auto")
gleich(ns.opt.autoBestaetigen, true, "auto eingeschaltet")
S.Warten(5)
leder = geschaeft(100)
geldVorher = S.geld
ns.Kaufen(leder)
S.Warten(1)
gleich(S.geld, geldVorher - 1000, "mit auto: ein Klick kauft")

SlashCmdList.PREISANKER("min 2s")
gleich(HaendlerprofitDB.anker.opt.minGewinn, 200, "Einstellung gespeichert")
S.Warten(1)

---------------------------------------------------------------- Preisanker mit Auctionator-Preisen

for _, z in ipairs(S.markt) do
  if z.key.itemID == 100 then z.stufen = { { preis = 10, menge = 100 } } end
  if z.key.itemID == 200 then z.lose = { { auctionID = 21, preis = 300, link = S.Link(200, "Banditenhandschuhe des Affen") } } end
end
local tag = math.floor((time() - 1577833200) / 86400)
local function Eintrag(preis, menge, alter)
  local t = tostring(tag - (alter or 0))
  return { m = preis, h = { [t] = preis }, l = {}, a = { [t] = menge } }
end
Auctionator = {
  API = { v1 = {} },
  SavedState = { TimeOfLastBrowseScan = time() },
  Database = { db = {
    version = 2,
    ["100"] = Eintrag(10, 100),      -- Leder unter dem Händlerpreis 50
    ["200"] = Eintrag(300, 1),       -- Handschuhe: Einzelstück, nur die Gegenstandsnummer bekannt
    ["g:200:10"] = Eintrag(300, 1),  -- derselbe Gegenstand je Stufe: wird übergangen
    ["101"] = Eintrag(30, 100),      -- teurer als beim Händler
    ["300"] = Eintrag(200, 40),      -- Händlerware
    ["103"] = Eintrag(1, 500, 5),    -- fünf Tage alt: nicht aus dem letzten Scan
  } },
}
HaendlerprofitDB.priceSource = "auctionator"
ns.db.preise[100] = 777
ns.ScanStarten()
gleich(ns.scan and ns.scan.phase, "preise", "Auctionator: kein Lesen des Auktionshauses nötig")
S.Warten(20)
gleich(ns.scan, nil, "Auctionator: Auswertung beendet")
gleich(ns.letzterScan.zeilen, 4, "Auctionator: nur aktuelle Preise mit Gegenstandsnummer")
gleich(geschaeft(103), nil, "Auctionator: alter Preis bleibt weg")
gleich(ns.db.preise[100], 777, "Auctionator: Preise des eigenen Scans bleiben unberührt")
leder, handschuhe = geschaeft(100), geschaeft(200)
gleich(leder.status, "bereit", "Auctionator: Leder bereit")
gleich(leder.gewinn, 4000, "Auctionator: Leder Gewinn nach Prüfung im Auktionshaus")
gleich(handschuhe.status, "bereit", "Auctionator: Handschuhe über die Suche aller Ausführungen gefunden")
gleich(handschuhe.gewinn, 900, "Auctionator: Handschuhe Gewinn")
gleich((S.verkaufsSuchen or 0) >= 1, true, "Auctionator: Einzelstück über alle Ausführungen gesucht")
gleich(ns.haendlerware[1] and ns.haendlerware[1].itemID, 300, "Auctionator: Händlerware erkannt")
ns.Kaufen(handschuhe)
S.Warten(0.6)
gleich(S.gebote[#S.gebote].auctionID, 21, "Auctionator: Handschuhe gekauft")
Auctionator.Database = nil
ns.ScanStarten()
gleich(gesagt("Auctionator ist nicht geladen"), true, "ohne Auctionator-Daten: Hinweis statt Auswertung")
Auctionator, HaendlerprofitDB.priceSource = nil, nil

echo(("%d Prüfungen, %d Fehler"):format(geprueft, fehler))
os.exit(fehler == 0 and 0 or 1)
