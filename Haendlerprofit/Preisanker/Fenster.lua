-- Preisanker: zwei Listen als Reiter im Händlerprofit-Fenster und die Befehle /preisanker und /pa.

local ADDON, hp = ...
hp.anker = hp.anker or {}
local ns = hp.anker -- eigener Namensraum im Addon Händlerprofit

local ZEILENHOEHE = 22
local BREITE = 660          -- Fensterbreite, für die die Spalten ausgelegt sind
local OBEN, UNTEN = 84, 30  -- Platz über und unter den Zeilen

-- Spalten je Liste: Titel, Breite, Ausrichtung. Die letzte Spalte der ersten Liste ist der Knopf.
local SPALTEN = {
  { { "Gegenstand", 250, "LEFT" }, { "Menge", 55, "RIGHT" }, { "Kosten", 95, "RIGHT" },
    { "Gewinn", 95, "RIGHT" }, { "", 100, "CENTER" } },
  { { "Gegenstand", 185, "LEFT" }, { "Händler", 80, "RIGHT" }, { "Auktion ab", 80, "RIGHT" },
    { "Gewinn/Stück", 85, "RIGHT" }, { "Angebot", 55, "RIGHT" }, { "Wo", 100, "LEFT" } },
}

local KNOPF = { -- Zustand → Beschriftung, anklickbar
  bereit = { "Kaufen", true }, bestaetigen = { "Bestätigen", true },
  angebot = { "Angebot...", false }, kauft = { "kauft...", false },
  offen = { "wartet", false }, laeuft = { "prüft...", false }, gekauft = { "gekauft", false },
}

local fenster, kopf, statusText, fussText
local zeilen = {}
local liste = {}
local blatt, versatz = 1, 0
local Zeile -- legt Zeilen bei Bedarf an (weiter unten)

local function Grau(text) return "|cff808080" .. text .. "|r" end
local function Gruen(text) return "|cff40ff40" .. text .. "|r" end

---------------------------------------------------------------- Inhalt

local function ListeBauen()
  local neu = {}
  if blatt == 1 then
    for _, g in ipairs(ns.geschaefte) do
      if g.status ~= "weg" then neu[#neu + 1] = g end
    end
    ns.Sortieren(neu)
  else
    for i, w in ipairs(ns.haendlerware) do neu[i] = w end
  end
  liste = neu
end

local function StatusZeile()
  local scan = ns.scan
  if scan then
    if scan.phase == "liste" then
      return ("Lese das Auktionshaus: %d Gegenstände..."):format(ns.zahl.zeilen)
    end
    return ("Lade Händlerpreise: noch %d..."):format(
      (scan.anzahlWartet or 0) + math.max(0, #(scan.ids or {}) - (scan.pos or 1) + 1))
  end
  if not ns.letzterScan then
    return ns.ahOffen and "»Scannen« liest das Auktionshaus (etwa eine halbe Minute)."
      or "Öffne das Auktionshaus und drücke »Scannen«."
  end
  if blatt == 2 then
    if #ns.haendlerware == 0 then
      return "Keine Händlerware mit Gewinn. Das Addon lernt Händlerpreise bei jedem Händlerbesuch."
    end
    return ("%d Waren kosten beim Händler weniger, als sie im Auktionshaus bringen (5 %% Gebühr abgezogen).")
      :format(#ns.haendlerware)
  end
  local bereit, gewinn, wartet = 0, 0, 0
  for _, g in ipairs(ns.geschaefte) do
    if g.status == "bereit" or g.status == "bestaetigen" then
      bereit, gewinn = bereit + 1, gewinn + g.gewinn
    elseif g.status == "offen" or g.status == "laeuft" then
      wartet = wartet + 1
    end
  end
  local text = ("%d Gegenstände gelesen · %d Geschäfte bereit, Gewinn %s"):format(
    ns.letzterScan.zeilen, bereit, ns.Geld(gewinn))
  if wartet > 0 then text = text .. (" · %d werden noch geprüft"):format(wartet) end
  if ns.zahl.ohnePreis > 0 then text = text .. (" · %d ohne Händlerpreis"):format(ns.zahl.ohnePreis) end
  return text
end

local function ZeileFuellen(zeile, e)
  zeile.eintrag = e
  zeile.bild:SetTexture(e.bild)
  local z = zeile.zellen
  z[1]:SetText(e.link or e.name)
  if blatt == 1 then
    if e.geprueft then
      z[2]:SetText(e.menge)
      z[3]:SetText(ns.Geld(e.kosten))
      z[4]:SetText(Gruen("+") .. ns.Geld(e.gewinn))
    else
      z[2]:SetText(Grau("?"))
      z[3]:SetText(Grau("ab ") .. ns.Geld(e.ahPreis))
      z[4]:SetText(Grau("bis ") .. ns.Geld(e.hoechstens))
    end
    local k = KNOPF[e.status] or KNOPF.offen
    zeile.knopf:SetText(k[1])
    zeile.knopf:SetEnabled(k[2] and ns.ahOffen and true or false)
    zeile.knopf:Show()
  else
    z[2]:SetText(ns.Geld(e.haendler))
    z[3]:SetText(ns.Geld(e.ah))
    z[4]:SetText(Gruen("+") .. ns.Geld(e.marge))
    z[5]:SetText(e.menge)
    z[6]:SetText((e.vorrat and e.vorrat >= 0 and "|cffff8040begrenzt|r " or "") .. (e.wer or ""))
    zeile.knopf:Hide()
  end
  zeile:Show()
end

local function Zeichnen()
  ListeBauen()
  -- So viele Zeilen, wie in die aktuelle Fensterhöhe passen.
  local sichtbar = math.max(1, math.floor(((fenster:GetHeight() or 0) - OBEN - UNTEN) / ZEILENHOEHE))
  versatz = math.max(0, math.min(versatz, #liste - sichtbar))
  for i = 1, math.max(sichtbar, #zeilen) do
    local e = i <= sichtbar and liste[i + versatz]
    if e then ZeileFuellen(Zeile(i), e) elseif zeilen[i] then zeilen[i]:Hide() end
  end
  statusText:SetText(StatusZeile())
  local b = ns.db.bilanz
  local fuss = ("Bilanz: ausgegeben %s, beim Händler erlöst %s"):format(ns.Geld(b.ausgegeben), ns.Geld(b.erloest))
  local offen = ns.OffeneTeile()
  if offen > 0 then fuss = fuss .. (" · noch zu verkaufen: %d Teile"):format(offen) end
  if #liste > sichtbar then
    fuss = fuss .. (" · Zeile %d-%d von %d (Mausrad)"):format(versatz + 1, math.min(versatz + sichtbar, #liste), #liste)
  end
  fussText:SetText(fuss)
  fenster.scanKnopf:SetEnabled(ns.ahOffen and not ns.scan and not ns.kauf and true or false)
end

-- Richtet die Zellen einer Zeile (oder des Kopfs) nach den Spalten der gewählten Liste aus.
-- Die Namensspalte bekommt die Breite, um die das Fenster breiter ist als ausgelegt.
local function SpaltenFuer(ziel)
  local spalten = SPALTEN[blatt]
  local mehr = math.max(0, (fenster:GetWidth() or BREITE) - BREITE)
  local x = 28
  for i = 1, 6 do
    local zelle, spalte = ziel.zellen[i], spalten[i]
    if spalte then
      local breite = spalte[2] + (i == 1 and mehr or 0)
      zelle:ClearAllPoints()
      zelle:SetPoint("LEFT", ziel, "LEFT", x, 0)
      zelle:SetWidth(breite)
      zelle:SetJustifyH(spalte[3])
      zelle:Show()
      if ziel == kopf then zelle:SetText(spalte[1]) end
      x = x + breite + 6
    else
      zelle:Hide()
    end
  end
end

local function SpaltenSetzen()
  SpaltenFuer(kopf)
  for _, zeile in ipairs(zeilen) do SpaltenFuer(zeile) end
end

-- Zeigt die Liste mit dieser Nummer (1 Unter Händlerpreis, 2 Händlerware); nil verbirgt beide.
function ns.BlattZeigen(nummer)
  if not fenster then return end
  if not nummer then return fenster:Hide() end
  if nummer ~= blatt then blatt, versatz = nummer, 0 end
  SpaltenSetzen()
  fenster:Show()
  ns.Neu()
end

---------------------------------------------------------------- Aufbau

local function Zellen(eltern, schrift)
  local zellen = {}
  for i = 1, 6 do
    local zelle = eltern:CreateFontString(nil, "OVERLAY", schrift)
    zelle:SetWordWrap(false)
    zellen[i] = zelle
  end
  return zellen
end

-- Sucht den Gegenstand im Blizzard-Fenster, damit man ihn dort ansehen kann.
local function ImAuktionshausSuchen(name)
  local ah = AuctionHouseFrame
  if not (name and ah and ah:IsShown() and ah.SearchBar and ah.SearchBar.SearchBox) then return end
  pcall(function()
    ah.SearchBar.SearchBox:SetText(name)
    ah.SearchBar:StartSearch()
  end)
end

local function Tipp(zeile)
  local e = zeile.eintrag
  if not e then return end
  GameTooltip:SetOwner(zeile, "ANCHOR_RIGHT")
  if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetText(e.name or "?") end
  GameTooltip:AddLine(" ")
  if blatt == 1 then
    GameTooltip:AddDoubleLine("Händler zahlt je Stück", ns.Geld(e.wert), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Auktionshaus ab", ns.Geld(e.ahPreis), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("Kaufen, aus dem Briefkasten holen, beim Händler verkaufen.", 0.6, 0.6, 0.6, true)
  else
    GameTooltip:AddDoubleLine("Händler", (e.wer or "?") .. (e.wo ~= "" and (" (" .. e.wo .. ")") or ""), 1, 1, 1, 1, 1, 1)
    if e.vorrat and e.vorrat >= 0 then
      GameTooltip:AddLine("Begrenzter Vorrat beim Händler: knappe Ware hält ihren Preis am längsten.", 1, 0.5, 0.25, true)
    else
      GameTooltip:AddLine("Unbegrenzter Vorrat: nur kleine Mengen einstellen, der Preis fällt schnell.", 0.6, 0.6, 0.6, true)
    end
  end
  GameTooltip:Show()
end

function Zeile(i)
  local zeile = zeilen[i]
  if zeile then return zeile end
  zeile = CreateFrame("Button", nil, fenster)
  zeile:SetPoint("TOPLEFT", 8, -OBEN - (i - 1) * ZEILENHOEHE)
  zeile:SetPoint("TOPRIGHT", -8, -OBEN - (i - 1) * ZEILENHOEHE)
  zeile:SetHeight(ZEILENHOEHE)
  local streifen = zeile:CreateTexture(nil, "BACKGROUND")
  streifen:SetAllPoints()
  streifen:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
  local leuchten = zeile:CreateTexture(nil, "HIGHLIGHT")
  leuchten:SetAllPoints()
  leuchten:SetColorTexture(1, 0.82, 0, 0.12)
  zeile.bild = zeile:CreateTexture(nil, "ARTWORK")
  zeile.bild:SetSize(18, 18)
  zeile.bild:SetPoint("LEFT", 4, 0)
  zeile.zellen = Zellen(zeile, "GameFontHighlightSmall")
  zeile.knopf = CreateFrame("Button", nil, zeile, "UIPanelButtonTemplate")
  zeile.knopf:SetSize(100, 20)
  zeile.knopf:SetPoint("RIGHT", -4, 0)
  zeile.knopf:SetScript("OnClick", function()
    if zeile.eintrag then ns.Kaufen(zeile.eintrag) end
  end)
  zeile:RegisterForClicks("LeftButtonUp")
  zeile:SetScript("OnEnter", Tipp)
  zeile:SetScript("OnLeave", function() GameTooltip:Hide() end)
  zeile:SetScript("OnClick", function(self)
    local e = self.eintrag
    if not e then return end
    -- Umschalt-Klick stellt den Link in den Chat, ein einfacher Klick sucht im Auktionshaus.
    if e.link and HandleModifiedItemClick(e.link) then return end
    ImAuktionshausSuchen(e.name)
  end)
  zeilen[i] = zeile
  SpaltenFuer(zeile)
  return zeile
end

-- Baut die Listen als Rahmen im Händlerprofit-Fenster, unter dessen Titel und Reitern.
function ns.FensterBauen(eltern)
  if fenster then return end
  local f = CreateFrame("Frame", "HaendlerprofitPreisanker", eltern)
  fenster = f
  f:SetPoint("TOPLEFT", eltern, "TOPLEFT", 0, -26)
  f:SetPoint("BOTTOMRIGHT", eltern, "BOTTOMRIGHT", 0, 0)
  f:Hide()

  f.scanKnopf = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.scanKnopf:SetSize(110, 22)
  f.scanKnopf:SetPoint("TOPRIGHT", -12, -34)
  f.scanKnopf:SetText("Scannen")
  f.scanKnopf:SetScript("OnClick", function() ns.ScanStarten() end)

  statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", 14, -39)
  statusText:SetPoint("TOPRIGHT", -130, -39)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(false)

  kopf = CreateFrame("Frame", nil, f)
  kopf:SetPoint("TOPLEFT", 8, -64)
  kopf:SetPoint("TOPRIGHT", -8, -64)
  kopf:SetHeight(18)
  kopf.zellen = Zellen(kopf, "GameFontNormalSmall")

  fussText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fussText:SetPoint("BOTTOMLEFT", 14, 11)
  fussText:SetPoint("BOTTOMRIGHT", -26, 11)
  fussText:SetJustifyH("LEFT")
  fussText:SetWordWrap(false)

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, richtung)
    versatz = versatz - richtung * 3
    ns.Neu()
  end)
  f:SetScript("OnShow", ns.Neu)
  f:SetScript("OnSizeChanged", function()
    SpaltenSetzen()
    ns.Neu()
  end)
  f:SetScript("OnUpdate", function()
    if ns.schmutzig then
      ns.schmutzig = false
      Zeichnen()
    end
  end)

  SpaltenSetzen()
end

-- Öffnet oder schließt das Händlerprofit-Fenster mit der zuletzt gezeigten Preisanker-Liste.
function ns.FensterZeigen(an)
  local offen = hp.IsShown() and fenster and fenster:IsShown()
  if an == nil then an = not offen end
  if an then hp.Open(blatt + 1) else hp.Close() end
end

-- Mit dem Auktionshaus öffnen; beim ersten Mal daneben setzen, danach bleibt das Fenster,
-- wo der Spieler es hinzieht. Ein schon offenes Fenster bleibt, wie es ist.
local angedockt
function ns.AuktionshausAuf()
  if not ns.opt.mitAuktionshaus or hp.IsShown() then return end
  hp.Open(blatt + 1)
  if not angedockt and AuctionHouseFrame then
    angedockt = true
    hp.Dock(AuctionHouseFrame)
  end
end

---------------------------------------------------------------- Befehle

local function AnAus(wert) return wert and "an" or "aus" end

local HILFE = {
  "/pa - Fenster zeigen oder verbergen",
  "/pa scan - Auktionshaus lesen (muss offen sein)",
  "/pa min 2s - kleinster Gewinn je Geschäft (g, s, k)",
  "/pa stapel 20 - so viele Stapel einer Handelsware höchstens auf einmal",
  "/pa auto - Handelsware ohne zweiten Klick kaufen, wenn der Preis stimmt (an/aus)",
  "/pa fenster - Fenster mit dem Auktionshaus öffnen (an/aus)",
  "/pa verkaufen - Einkäufe beim offenen Händler verkaufen",
  "/pa vergessen - Liste der noch zu verkaufenden Einkäufe leeren",
  "/pa info - Stand und Einstellungen",
}

SLASH_PREISANKER1, SLASH_PREISANKER2 = "/preisanker", "/pa"
SlashCmdList.PREISANKER = function(eingabe)
  local befehl, rest = (eingabe or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local opt = ns.opt
  if befehl == "" then
    ns.FensterZeigen()
  elseif befehl == "scan" then
    ns.FensterZeigen(true)
    ns.ScanStarten()
  elseif befehl == "min" then
    local kupfer = ns.GeldLesen(rest)
    if not kupfer then return ns.Sag("Beispiel: /pa min 2s") end
    opt.minGewinn = kupfer
    ns.Sag("Kleinster Gewinn je Geschäft: " .. ns.Geld(kupfer) .. ". Gilt ab dem nächsten Scan.")
  elseif befehl == "stapel" then
    local n = tonumber(rest)
    if not n or n < 1 then return ns.Sag("Beispiel: /pa stapel 20") end
    opt.maxStapel = math.floor(n)
    ns.Sag(("Höchstens %d Stapel je Kauf."):format(opt.maxStapel))
  elseif befehl == "auto" then
    opt.autoBestaetigen = not opt.autoBestaetigen
    ns.Sag("Handelsware ohne zweiten Klick kaufen: " .. AnAus(opt.autoBestaetigen))
  elseif befehl == "fenster" then
    opt.mitAuktionshaus = not opt.mitAuktionshaus
    ns.Sag("Fenster mit dem Auktionshaus öffnen: " .. AnAus(opt.mitAuktionshaus))
  elseif befehl == "verkaufen" then
    ns.Verkaufen()
  elseif befehl == "vergessen" then
    ns.db.offen = {}
    ns.HaendlerKnopf()
    ns.Sag("Liste der noch zu verkaufenden Einkäufe geleert.")
  elseif befehl == "info" then
    local version, build, _, interface = GetBuildInfo()
    local haendler = 0
    for _ in pairs(ns.db.haendler) do haendler = haendler + 1 end
    ns.Sag(("Spiel %s (%s), Interface %s."):format(version, build, tostring(interface)))
    ns.Sag(("Kleinster Gewinn %s, höchstens %d Stapel, ohne zweiten Klick: %s."):format(
      ns.Geld(opt.minGewinn), opt.maxStapel, AnAus(opt.autoBestaetigen)))
    ns.Sag(("Gelernte Händlerwaren: %d. Noch zu verkaufen: %d Teile."):format(haendler, ns.OffeneTeile()))
  else
    for _, zeile in ipairs(HILFE) do ns.Sag(zeile) end
  end
  ns.Neu()
end
