-- Preisanker: Auktionshaus lesen.
--   1. Überblick: eine leere Suche liefert je Gegenstand den billigsten Preis (ca. 20 s).
--   2. Händlerpreise der gefundenen Gegenstände laden (einmalig, danach gemerkt).
--   3. Jeden Kandidaten einzeln nachschlagen, um die echten Lose und Mengen zu sehen.

local ADDON, hp = ...
hp.anker = hp.anker or {}
local ns = hp.anker -- eigener Namensraum im Addon Händlerprofit
local AH = C_AuctionHouse

local SUCH_ABSTAND = 0.75 -- s zwischen Einzelsuchen; Blizzard erlaubt 100 Suchen je Minute
local SUCH_GEDULD = 6     -- s, bis eine unbeantwortete Einzelsuche übersprungen wird
local LISTE_GEDULD = 20   -- s ohne Antwort, bis der Überblick abgebrochen wird
local PREIS_GEDULD = 8    -- s ohne Fortschritt, bis fehlende Händlerpreise aufgegeben werden

ns.zeilen = {}       -- Schlüssel → { key, itemID, preis, menge } aus dem Überblick
ns.geschaefte = {}   -- Auktionen unter Händlerpreis
ns.haendlerware = {} -- Händlerware, die im Auktionshaus teurer ist
ns.nachId = {}       -- Schlüssel → Geschäft
ns.zahl = { zeilen = 0, ohnePreis = 0 }

---------------------------------------------------------------- Ereignisse

local frame = CreateFrame("Frame")
local horcher = {}

function ns.Bei(ereignis, fn)
  if not horcher[ereignis] then
    horcher[ereignis] = {}
    if not pcall(frame.RegisterEvent, frame, ereignis) then
      print("|cffffd100Preisanker:|r Ereignis fehlt in diesem Spiel: " .. ereignis)
    end
  end
  table.insert(horcher[ereignis], fn)
end

frame:SetScript("OnEvent", function(_, ereignis, ...)
  local liste = horcher[ereignis]
  if not liste then return end
  for i = 1, #liste do liste[i](...) end
end)

function ns.Sag(...)
  print("|cffffd100Preisanker:|r", ...)
end

-- Das Fenster ersetzt das: zeichnet beim nächsten Bild neu.
function ns.Neu() ns.schmutzig = true end

ns.Bei("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  HaendlerprofitDB = HaendlerprofitDB or {}
  HaendlerprofitDB.anker = HaendlerprofitDB.anker or {}
  local db = HaendlerprofitDB.anker
  db.opt = db.opt or {}
  db.vk = db.vk or {}             -- itemID → Preis, den Händler zahlen
  db.haendler = db.haendler or {} -- itemID → Ware, die ein Händler verkauft
  db.offen = db.offen or {}       -- gekauft, noch nicht beim Händler verkauft
  db.bilanz = db.bilanz or { ausgegeben = 0, erloest = 0 }
  db.preise = db.preise or {}     -- itemID → billigster Auktionspreis aus dem letzten eigenen Scan
  -- Händlerpreise können sich mit einem Patch ändern: dann neu laden.
  local build = select(2, GetBuildInfo())
  if db.vkBuild ~= build then db.vk, db.vkBuild = {}, build end
  ns.db = db
  ns.opt = setmetatable(db.opt, { __index = ns.standard })
end)

---------------------------------------------------------------- Senden mit Drossel

-- Das Auktionshaus nimmt Anfragen nur einzeln an. Alles, was nicht auf einen Klick hin
-- passiert, wartet hier, bis das Spiel wieder bereit ist.
local wartend = {}

function ns.Senden(fn)
  wartend[#wartend + 1] = fn
end

local function Pumpen()
  if #wartend == 0 or ns.kauf then return end
  if not AH.IsThrottledMessageSystemReady() then return end
  table.remove(wartend, 1)()
end

---------------------------------------------------------------- Händlerpreis

-- Preis, den ein Händler für den Gegenstand zahlt; nil, solange die Daten nicht geladen sind.
local function Haendlerpreis(itemID)
  local preis = ns.db.vk[itemID]
  if preis then return preis end
  local name, _, _, _, _, _, _, _, _, _, verkauf = C_Item.GetItemInfo(itemID)
  if not name then return nil end
  ns.db.vk[itemID] = verkauf or 0
  return verkauf or 0
end

local function NameLinkBild(itemID)
  local name, link, _, _, _, _, _, _, _, bild = C_Item.GetItemInfo(itemID)
  return name or ("Gegenstand " .. itemID), link, bild
end

---------------------------------------------------------------- 3. Einzelprüfung

local aktuell        -- { g = Geschäft, gesendet = Zeit } der laufenden Einzelsuche
local letzteSuche = 0
local SORT_KAUF = {
  { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
  { sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
}

local function Fertig(g)
  if aktuell and aktuell.g == g then aktuell = nil end
  ns.Neu()
end

-- Handelsware: Antwort ist eine Preistreppe (Stückpreis, Menge).
local function ErgebnisWare(itemID)
  for _, g in ipairs(ns.geschaefte) do
    if g.itemID == itemID and not (ns.kauf and ns.kauf.g == g) then
      local stufen = {}
      for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 then
          local menge = (r.quantity or 0) - (r.numOwnerItems or 0)
          if menge > 0 then stufen[#stufen + 1] = { preis = r.unitPrice, menge = menge } end
        end
      end
      table.sort(stufen, function(a, b) return a.preis < b.preis end)
      local stapel = C_Item.GetItemMaxStackSizeByID(itemID) or 1
      g.art, g.geprueft = "ware", true
      g.menge, g.kosten, g.gewinn =
        ns.Handelsware(stufen, g.wert, ns.opt.maxStapel * math.max(1, stapel), GetMoney())
      g.status = (g.menge > 0 and g.gewinn >= ns.opt.minGewinn) and "bereit" or "weg"
      Fertig(g)
    end
  end
end

-- Einzelstücke: Antwort ist eine Liste von Losen, jedes mit eigenem Link.
local function ErgebnisLose(itemKey)
  local g = itemKey and ns.nachId[ns.Schluessel(itemKey)]
  if not g or (ns.kauf and ns.kauf.g == g) then return end
  local lose = {}
  for i = 1, AH.GetNumItemSearchResults(itemKey) do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local wert = g.wert
      if r.itemLink then
        -- Der Link kennt die genaue Ausführung; ihr Händlerpreis kann vom Grundgegenstand abweichen.
        local name, _, _, _, _, _, _, _, _, _, verkauf = C_Item.GetItemInfo(r.itemLink)
        if name and verkauf then wert = verkauf end
      end
      lose[#lose + 1] = {
        auctionID = r.auctionID, preis = r.buyoutAmount,
        wert = wert, anzahl = math.max(1, r.quantity or 1), link = r.itemLink,
      }
    end
  end
  g.art, g.geprueft = "los", true
  g.lose, g.kosten, g.gewinn, g.menge = ns.Lose(lose)
  if g.lose[1] and g.lose[1].link then
    g.link = g.lose[1].link
    g.name = ns.NameAusLink(g.link) or g.name
  end
  g.status = (g.menge > 0 and g.gewinn >= ns.opt.minGewinn) and "bereit" or "weg"
  Fertig(g)
end

ns.Bei("COMMODITY_SEARCH_RESULTS_UPDATED", ErgebnisWare)
ns.Bei("ITEM_SEARCH_RESULTS_UPDATED", ErgebnisLose)

local function Pruefen()
  if ns.scan or ns.kauf then return end
  local jetzt = GetTime()
  if aktuell then
    if jetzt - aktuell.gesendet < SUCH_GEDULD then return end
    -- Keine Antwort: einmal neu versuchen, dann aufgeben.
    local g = aktuell.g
    g.versuche = (g.versuche or 0) + 1
    g.status = g.versuche < 2 and "offen" or "weg"
    aktuell = nil
    ns.Neu()
  end
  if jetzt - letzteSuche < SUCH_ABSTAND then return end
  if not AH.IsThrottledMessageSystemReady() then return end
  for _, g in ipairs(ns.pruefFolge or {}) do
    if g.status == "offen" then
      -- Das Spiel muss den Gegenstand kennen, bevor es ihn suchen kann; kurz darauf warten.
      if not AH.GetItemKeyInfo(g.key) then
        g.wartetSeit = g.wartetSeit or jetzt
        if jetzt - g.wartetSeit < 3 then return end
      end
      g.status = "laeuft"
      aktuell, letzteSuche = { g = g, gesendet = jetzt }, jetzt
      AH.SendSearchQuery(g.key, SORT_KAUF, false)
      ns.Neu()
      return
    end
  end
end

-- Nach einem Kauf oder einer Preisänderung: Geschäft neu nachschlagen.
function ns.NeuPruefen(g)
  g.status, g.versuche, g.wartetSeit = "offen", nil, nil
  ns.Neu()
end

---------------------------------------------------------------- 2. Händlerpreise und Auswertung

local function Auswerten()
  local scan = ns.scan
  local geschaefte, nachId, billigst = {}, {}, {}
  for id, z in pairs(ns.zeilen) do
    local wert = ns.db.vk[z.itemID]
    if wert and wert > 0 and z.preis < wert then
      local name, link, bild = NameLinkBild(z.itemID)
      local g = {
        id = id, key = z.key, itemID = z.itemID, name = name, link = link, bild = bild,
        wert = wert, ahPreis = z.preis, ahMenge = z.menge,
        geprueft = false, gewinn = wert - z.preis,
        hoechstens = (wert - z.preis) * z.menge, -- mehr Gewinn kann die Zeile nicht bringen
      }
      g.status = g.hoechstens >= ns.opt.minGewinn and "offen" or "weg"
      geschaefte[#geschaefte + 1], nachId[id] = g, g
    end
    local b = billigst[z.itemID]
    if not b then
      billigst[z.itemID] = { preis = z.preis, menge = z.menge }
    else
      b.menge = b.menge + z.menge
      if z.preis < b.preis then b.preis = z.preis end
    end
  end

  -- Die Preise bleiben gespeichert: der Reiter »Herstellen« rechnet damit Materialkosten.
  local preise = {}
  for itemID, b in pairs(billigst) do preise[itemID] = b.preis end
  ns.db.preise, ns.db.preisZeit = preise, time()

  local ware = {}
  for itemID, h in pairs(ns.db.haendler) do
    local b = billigst[itemID]
    local marge = b and ns.HaendlerMarge(b.preis, h.p)
    if marge and marge > 0 then
      local name, link, bild = NameLinkBild(itemID)
      ware[#ware + 1] = {
        itemID = itemID, name = name, link = link, bild = bild,
        haendler = h.p, ah = b.preis, marge = marge, menge = b.menge,
        wer = h.wer, wo = h.wo, vorrat = h.n,
      }
    end
  end
  table.sort(ware, function(a, b)
    if a.marge ~= b.marge then return a.marge > b.marge end
    return a.itemID < b.itemID
  end)

  -- Prüfreihenfolge: wo am meisten zu holen sein könnte, zuerst.
  local folge = {}
  for i, g in ipairs(geschaefte) do folge[i] = g end
  table.sort(folge, function(a, b)
    if a.hoechstens ~= b.hoechstens then return a.hoechstens > b.hoechstens end
    return a.id < b.id
  end)

  ns.geschaefte, ns.nachId, ns.haendlerware, ns.pruefFolge = geschaefte, nachId, ware, folge
  ns.zahl.ohnePreis = scan.fehlend or 0
  ns.letzterScan = { zeit = time(), zeilen = ns.zahl.zeilen, dauer = GetTime() - scan.start }
  ns.scan, aktuell = nil, nil
  -- Das Spiel soll die Kandidaten schon einmal laden, bevor die Einzelsuche sie braucht.
  for i = 1, math.min(#folge, 200) do AH.GetItemKeyInfo(folge[i].key) end
  ns.Neu()
  if ns.NachScan then ns.NachScan() end
end

local function PreiseLaden()
  local scan = ns.scan
  scan.phase, scan.aktiv = "preise", GetTime()
  local ids, gesehen = {}, {}
  for _, z in pairs(ns.zeilen) do
    if not gesehen[z.itemID] then
      gesehen[z.itemID] = true
      if not ns.db.vk[z.itemID] then ids[#ids + 1] = z.itemID end
    end
  end
  scan.ids, scan.pos, scan.wartet, scan.anzahlWartet = ids, 1, {}, 0
end

-- Fragt Händlerpreise portionsweise an, damit das Spiel nicht ruckelt.
local function PreiseWeiter()
  local scan = ns.scan
  local jetzt = GetTime()
  local ende = math.min(scan.pos + 299, #scan.ids)
  for i = scan.pos, ende do
    local id = scan.ids[i]
    if Haendlerpreis(id) == nil then
      scan.wartet[id] = true
      scan.anzahlWartet = scan.anzahlWartet + 1
      C_Item.RequestLoadItemDataByID(id)
    end
  end
  if ende >= scan.pos then scan.aktiv = jetzt end
  scan.pos = ende + 1
  if scan.pos <= #scan.ids then return end

  -- Alles angefragt: Nachzügler einmal je Sekunde erneut lesen.
  if scan.anzahlWartet > 0 and jetzt - (scan.nachgelesen or 0) >= 1 then
    scan.nachgelesen = jetzt
    for id in pairs(scan.wartet) do
      if Haendlerpreis(id) ~= nil then
        scan.wartet[id] = nil
        scan.anzahlWartet = scan.anzahlWartet - 1
        scan.aktiv = jetzt
      end
    end
  end
  if scan.anzahlWartet <= 0 or jetzt - scan.aktiv > PREIS_GEDULD then
    scan.fehlend = math.max(0, scan.anzahlWartet)
    Auswerten()
  end
end

local function PreisGeladen(itemID, erfolg)
  local scan = ns.scan
  if not (scan and scan.phase == "preise" and scan.wartet[itemID]) then return end
  if erfolg == false or Haendlerpreis(itemID) ~= nil then
    scan.wartet[itemID] = nil
    scan.anzahlWartet = scan.anzahlWartet - 1
    scan.aktiv = GetTime()
  end
end

ns.Bei("GET_ITEM_INFO_RECEIVED", PreisGeladen)
ns.Bei("ITEM_DATA_LOAD_RESULT", PreisGeladen)

---------------------------------------------------------------- 1. Überblick

local function Aufnehmen(ergebnisse)
  for _, e in ipairs(ergebnisse or {}) do
    local key = e.itemKey
    if key and key.itemID and (key.battlePetSpeciesID or 0) == 0
        and e.minPrice and e.minPrice > 0 and (e.totalQuantity or 0) > 0 then
      local id = ns.Schluessel(key)
      if not ns.zeilen[id] then ns.zahl.zeilen = ns.zahl.zeilen + 1 end
      ns.zeilen[id] = { key = key, itemID = key.itemID, preis = e.minPrice, menge = e.totalQuantity }
    end
  end
end

local function ListeWeiter()
  local scan = ns.scan
  scan.aktiv, scan.nachgehakt = GetTime(), false
  if AH.HasFullBrowseResults() then
    PreiseLaden()
  elseif not scan.mehrBestellt then
    scan.mehrBestellt = true
    ns.Senden(function() AH.RequestMoreBrowseResults() end)
  end
  ns.Neu()
end

ns.Bei("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local scan = ns.scan
  if not (scan and scan.phase == "liste" and scan.gesendet) then return end
  Aufnehmen(AH.GetBrowseResults())
  ListeWeiter()
end)

ns.Bei("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(neue)
  local scan = ns.scan
  if not (scan and scan.phase == "liste" and scan.gesendet) then return end
  Aufnehmen(neue)
  scan.mehrBestellt = false
  ListeWeiter()
end)

ns.Bei("AUCTION_HOUSE_BROWSE_FAILURE", function()
  if ns.scan and ns.scan.phase == "liste" then
    ns.scan = nil
    ns.Sag("Das Auktionshaus hat die Suche abgelehnt. Bitte gleich noch einmal scannen.")
    ns.Neu()
  end
end)

function ns.ScanStarten()
  if not ns.ahOffen then return ns.Sag("Erst das Auktionshaus öffnen.") end
  if ns.scan then return end
  if ns.kauf then return ns.Sag("Erst den laufenden Kauf abschließen.") end
  local F, S = Enum.AuctionHouseFilter, Enum.AuctionHouseSortOrder
  wartend, aktuell = {}, nil
  ns.zeilen, ns.zahl.zeilen = {}, 0
  ns.geschaefte, ns.haendlerware, ns.nachId, ns.pruefFolge = {}, {}, {}, {}
  local scan = { phase = "liste", start = GetTime(), aktiv = GetTime() }
  ns.scan = scan
  ns.Senden(function()
    scan.gesendet, scan.aktiv = true, GetTime()
    -- Dieselbe Anfrage wie die leere Suche im Blizzard-Fenster: alle Qualitäten, keine Kategorie.
    AH.SendBrowseQuery({
      searchString = "",
      sorts = {
        { sortOrder = S.Price, reverseSort = false },
        { sortOrder = S.Name, reverseSort = false },
      },
      filters = {
        F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality,
        F.EpicQuality, F.LegendaryQuality, F.ArtifactQuality,
      },
      itemClassFilters = {},
    })
  end)
  ns.Neu()
end

---------------------------------------------------------------- Takt

local takt

local function Takt()
  Pumpen()
  local scan = ns.scan
  if scan then
    if scan.phase == "liste" then
      local still = GetTime() - scan.aktiv
      if still > LISTE_GEDULD then
        ns.scan = nil
        ns.Sag("Keine Antwort vom Auktionshaus, Scan abgebrochen.")
      elseif still > 5 and scan.gesendet and not scan.nachgehakt then
        -- Eine Nachbestellung kann verloren gehen: einmal nachhaken, ohne die Geduld zu verlängern.
        scan.nachgehakt = true
        if AH.HasFullBrowseResults() and ns.zahl.zeilen > 0 then
          PreiseLaden()
        else
          ns.Senden(function() AH.RequestMoreBrowseResults() end)
        end
      end
    else
      PreiseWeiter()
    end
    ns.Neu()
  else
    Pruefen()
  end
  if ns.KaufWache then ns.KaufWache() end
end

ns.Bei("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", Pumpen)

ns.Bei("AUCTION_HOUSE_SHOW", function()
  ns.ahOffen = true
  if takt then takt:Cancel() end
  takt = C_Timer.NewTicker(0.2, Takt)
  if ns.AuktionshausAuf then ns.AuktionshausAuf() end
  ns.Neu()
end)

ns.Bei("AUCTION_HOUSE_CLOSED", function()
  ns.ahOffen = false
  if takt then takt:Cancel() end
  takt, wartend = nil, {}
  if ns.scan then
    ns.scan = nil
    ns.Sag("Auktionshaus geschlossen, Scan abgebrochen.")
  end
  if aktuell then
    aktuell.g.status = "offen"
    aktuell = nil
  end
  if ns.KaufAbbrechen then ns.KaufAbbrechen() end
  ns.Neu()
end)
