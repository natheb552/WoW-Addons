-- Preisanker: zwei Listen als Reiter im Händlerprofit-Fenster und die Befehle /preisanker und /pa.
-- Aufbau und Aussehen folgen dem Reiter »Herstellen« (UI.lua); die Bausteine kommen aus hp.ui.

local ADDON, hp = ...
hp.anker = hp.anker or {}
local ns = hp.anker -- eigener Namensraum im Addon Händlerprofit

local ZEILENHOEHE = 24
local OBEN, UNTEN = 120, 34 -- Platz über und unter den Zeilen, wie im Reiter »Herstellen«

-- Spalten je Liste: Titel, Breite, Ausrichtung. Die erste nimmt den Platz, der übrig bleibt.
-- Die letzte Spalte der ersten Liste ist der Knopf.
local SPALTEN = {
  { { "Gegenstand", 0, "LEFT" }, { "Menge", 45, "RIGHT" }, { "Kosten", 90, "RIGHT" },
    { "Gewinn", 150, "RIGHT" }, { "", 90, "CENTER" } },
  { { "Gegenstand", 0, "LEFT" }, { "Händler", 85, "RIGHT" }, { "Auktion ab", 85, "RIGHT" },
    { "Gewinn/Stück", 95, "RIGHT" }, { "Angebot", 55, "RIGHT" }, { "Wo", 110, "LEFT" } },
}

local KNOPF = { -- Zustand → Beschriftung, anklickbar
  bereit = { "Kaufen", true }, bestaetigen = { "Bestätigen", true },
  angebot = { "Angebot...", false }, kauft = { "kauft...", false },
  offen = { "wartet", false }, laeuft = { "prüft...", false }, gekauft = { "gekauft", false },
}

local fenster, kopf, regler, zusammenText, leerText, fussText, bedienung
local zeilen, haken = {}, {}
local liste = {}
local blatt, versatz = 1, 0
local Zeile -- legt Zeilen bei Bedarf an (weiter unten)

local function Grau(text) return "|cff808080" .. text .. "|r" end
local function Gruen(text) return "|cff33ff33" .. text .. "|r" end

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

-- Zusammenfassung, Hinweis für die leere Liste und Fußzeile
local function Texte()
  local b = ns.db.bilanz
  local fuss = ("Bilanz: ausgegeben %s, beim Händler erlöst %s"):format(hp.Money(b.ausgegeben), hp.Money(b.erloest))
  local offen = ns.OffeneTeile()
  if offen > 0 then fuss = fuss .. (" · noch zu verkaufen: %d Teile"):format(offen) end

  local scan = ns.scan
  if scan then
    if scan.phase == "liste" then
      return "Lese das Auktionshaus", ("%d Gegenstände gelesen."):format(ns.zahl.zeilen), fuss
    end
    return "Lade Händlerpreise", ("Noch %d Gegenstände."):format(
      (scan.anzahlWartet or 0) + math.max(0, #(scan.ids or {}) - (scan.pos or 1) + 1)), fuss
  end
  if not ns.letzterScan then
    local wie = hp.PriceSource() == "scan" and "»Scannen« liest das Auktionshaus (etwa eine halbe Minute)."
      or "»Auswerten« nimmt die Preise aus dem letzten Auctionator-Scan."
    return "Noch nicht ausgewertet", (ns.ahOffen and "" or "Öffne das Auktionshaus.\n") .. wie, fuss
  end

  fuss = ("%d Gegenstände gelesen · "):format(ns.letzterScan.zeilen) .. fuss
  if ns.zahl.ohnePreis > 0 then fuss = fuss .. (" · %d ohne Händlerpreis"):format(ns.zahl.ohnePreis) end
  if blatt == 2 then
    if #ns.haendlerware == 0 then
      return "Keine Händlerware mit Gewinn", "Das Addon lernt Händlerpreise bei jedem Händlerbesuch.", fuss
    end
    return ("|cff33ff33%d|r Waren beim Händler billiger als im Auktionshaus (5 %% Gebühr abgezogen)")
      :format(#ns.haendlerware), "", fuss
  end
  local bereit, gewinn, wartet = 0, 0, 0
  for _, g in ipairs(ns.geschaefte) do
    if g.status == "bereit" or g.status == "bestaetigen" then
      bereit, gewinn = bereit + 1, gewinn + g.gewinn
    elseif g.status == "offen" or g.status == "laeuft" then
      wartet = wartet + 1
    end
  end
  local text = "Kein Geschäft bereit"
  if bereit > 0 then
    text = ("|cff33ff33%d|r Geschäft%s bereit, Gewinn |cff33ff33+|r%s"):format(
      bereit, bereit == 1 and "" or "e", hp.Money(gewinn))
  end
  if wartet > 0 then text = text .. (" · %d werden geprüft"):format(wartet) end
  return text, wartet == 0 and "Zurzeit liegt nichts unter dem Händlerpreis." or "", fuss
end

-- Name in der Farbe des Links, ohne dessen eckige Klammern
local function FarbName(e)
  local farbe = e.link and e.link:match("^(|c.-)|H")
  return farbe and (farbe .. (e.name or "?") .. "|r") or (e.name or "?")
end

local function ZeileFuellen(zeile, e, bester)
  ns.NameNachladen(e)
  zeile.eintrag = e
  zeile.bild:SetTexture(e.bild)
  local z = zeile.zellen
  z[1]:SetText(FarbName(e))
  local anteil = 0
  if blatt == 1 then
    if e.geprueft then
      z[2]:SetText(e.menge)
      z[3]:SetText(hp.Money(e.kosten))
      z[4]:SetText(Gruen("+") .. hp.Money(e.gewinn))
      anteil = e.gewinn / bester
    else
      z[2]:SetText(Grau("?"))
      -- Noch nicht nachgeschlagen: bekannt ist nur der billigste Preis, nicht die Menge dazu.
      z[3]:SetText(Grau("ab ") .. hp.Money(e.ahPreis))
      z[4]:SetText(Grau("je Stück bis +") .. hp.Money(e.wert - e.ahPreis))
    end
    local k = KNOPF[e.status] or KNOPF.offen
    zeile.knopf.label:SetText(k[1])
    hp.ui.SetButtonEnabled(zeile.knopf, k[2] and ns.ahOffen)
    zeile.knopf:Show()
  else
    z[2]:SetText(hp.Money(e.haendler))
    z[3]:SetText(hp.Money(e.ah))
    z[4]:SetText(Gruen("+") .. hp.Money(e.marge))
    z[5]:SetText(e.menge)
    z[6]:SetText((e.vorrat and e.vorrat >= 0 and "|cffff8040begrenzt|r " or "") .. (e.wer or ""))
    anteil = e.marge / bester
    zeile.knopf:Hide()
  end
  -- Balken im Hintergrund: Gewinn im Verhältnis zum besten Eintrag
  zeile.balken:SetWidth(math.max(1, (zeile:GetWidth() or 0) * math.max(0, math.min(1, anteil))))
  zeile:Show()
end

local function Zeichnen()
  ListeBauen()
  -- So viele Zeilen, wie in die aktuelle Fensterhöhe passen.
  local sichtbar = math.max(1, math.floor(((fenster:GetHeight() or 0) - OBEN - UNTEN) / ZEILENHOEHE))
  local weite = math.max(0, #liste - sichtbar)
  versatz = math.max(0, math.min(versatz, weite))
  local bester = 1
  for _, e in ipairs(liste) do
    local wert = blatt == 1 and (e.geprueft and e.gewinn or 0) or e.marge
    if wert > bester then bester = wert end
  end
  for i = 1, math.max(sichtbar, #zeilen) do
    local e = i <= sichtbar and liste[i + versatz]
    if e then ZeileFuellen(Zeile(i), e, bester) elseif zeilen[i] then zeilen[i]:Hide() end
  end
  regler:SetMinMaxValues(0, weite)
  regler:SetValue(versatz)
  regler:SetShown(weite > 0)

  local oben, leer, fuss = Texte()
  zusammenText:SetText(oben)
  leerText:SetText(#liste == 0 and leer or "")
  fussText:SetText(fuss)
  bedienung.Update()
  for _, h in ipairs(haken) do h:SetChecked(ns.opt[h.schluessel]) end
end

-- Richtet die Zellen einer Zeile (oder des Kopfs) nach den Spalten der gewählten Liste aus.
local function SpaltenFuer(ziel)
  local spalten = SPALTEN[blatt]
  local fest = 26 + 6
  for i = 2, #spalten do fest = fest + spalten[i][2] + 4 end
  local x = 26
  for i = 1, 6 do
    local zelle, spalte = ziel.zellen[i], spalten[i]
    if spalte then
      local breite = i == 1 and math.max(120, (fenster:GetWidth() or 660) - 36 - fest) or spalte[2]
      zelle:ClearAllPoints()
      zelle:SetPoint("LEFT", ziel, "LEFT", x, 0)
      zelle:SetWidth(breite)
      zelle:SetJustifyH(spalte[3])
      zelle:Show()
      if ziel == kopf then zelle:SetText(spalte[1]) end
      x = x + breite + 4
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
    zellen[i] = hp.ui.Text(eltern, schrift)
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
    GameTooltip:AddDoubleLine("Händler zahlt je Stück", hp.Money(e.wert), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Auktionshaus ab", hp.Money(e.ahPreis), 1, 1, 1, 1, 1, 1)
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
  local ui = hp.ui
  zeile = CreateFrame("Button", nil, fenster)
  zeile:SetHeight(ZEILENHOEHE)
  zeile:SetPoint("TOPLEFT", fenster, "TOPLEFT", 12, -OBEN - (i - 1) * ZEILENHOEHE)
  zeile:SetPoint("TOPRIGHT", fenster, "TOPRIGHT", -24, -OBEN - (i - 1) * ZEILENHOEHE)
  if i % 2 == 0 then ui.Fill(zeile, "BACKGROUND", 1, 1, 1, 0.035) end

  zeile.balken = zeile:CreateTexture(nil, "BORDER")
  zeile.balken:SetPoint("TOPLEFT", zeile, "TOPLEFT", 0, -1)
  zeile.balken:SetPoint("BOTTOMLEFT", zeile, "BOTTOMLEFT", 0, 1)
  zeile.balken:SetColorTexture(0.2, 0.9, 0.3, 0.10)

  zeile.bild = zeile:CreateTexture(nil, "ARTWORK")
  zeile.bild:SetSize(18, 18)
  zeile.bild:SetPoint("LEFT", zeile, "LEFT", 3, 0)
  zeile.bild:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  zeile.zellen = Zellen(zeile, "GameFontHighlightSmall")
  zeile.zellen[1]:SetFontObject("GameFontHighlight")
  zeile.zellen[4]:SetFontObject("GameFontHighlight")

  local leuchten = zeile:CreateTexture(nil, "HIGHLIGHT")
  leuchten:SetAllPoints()
  leuchten:SetColorTexture(1, 0.82, 0, 0.10)

  zeile.knopf = ui.FlatButton(zeile, 90, "", "CENTER")
  zeile.knopf:SetHeight(18)
  zeile.knopf:SetPoint("RIGHT", zeile, "RIGHT", -2, 0)
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

local function Haken(text, schluessel, x)
  local h = hp.ui.Check(fenster, text, x, function(an) ns.opt[schluessel] = an end)
  h.schluessel = schluessel
  haken[#haken + 1] = h
end

-- Baut die Listen als Rahmen im Händlerprofit-Fenster, unter dessen Titel und Reitern.
-- Die Maße entsprechen dem Reiter »Herstellen«: Einstellungen, Zusammenfassung, Kopf, Liste, Fuß.
function ns.FensterBauen(eltern)
  if fenster then return end
  local ui = hp.ui
  local f = CreateFrame("Frame", "HaendlerprofitPreisanker", eltern)
  fenster = f
  f:SetPoint("TOPLEFT", eltern, "TOPLEFT", 0, -26)
  f:SetPoint("BOTTOMRIGHT", eltern, "BOTTOMRIGHT", 0, 0)
  f:Hide()

  -- Einstellungen
  Haken("Mit dem Auktionshaus öffnen", "mitAuktionshaus", 10)
  Haken("Handelsware ohne zweiten Klick kaufen", "autoBestaetigen", 204)

  -- Zusammenfassung mit Scan-Knopf und Preisquelle
  local zusammen = CreateFrame("Frame", nil, f)
  zusammen:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
  zusammen:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -64)
  zusammen:SetHeight(26)
  ui.Fill(zusammen, "BACKGROUND", 1, 1, 1, 0.04)
  bedienung = ui.SourceControls(zusammen, true)
  f.scanKnopf = bedienung.scan
  zusammenText = ui.Text(zusammen, "GameFontHighlight")
  zusammenText:SetPoint("LEFT", zusammen, "LEFT", 8, 0)
  zusammenText:SetPoint("RIGHT", bedienung.text, "LEFT", -8, 0)

  -- Spaltenköpfe
  kopf = CreateFrame("Frame", nil, f)
  kopf:SetHeight(20)
  kopf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -96)
  kopf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -96)
  kopf.zellen = Zellen(kopf, "GameFontNormalSmall")
  local linie = f:CreateTexture(nil, "ARTWORK")
  linie:SetColorTexture(0.35, 0.30, 0.15, 1)
  linie:SetHeight(1)
  linie:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -117)
  linie:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -117)

  -- Schmaler Rollbalken
  regler = CreateFrame("Slider", nil, f)
  regler:SetOrientation("VERTICAL")
  regler:SetWidth(8)
  regler:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -OBEN)
  regler:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, UNTEN)
  ui.Fill(regler, "BACKGROUND", 1, 1, 1, 0.05)
  local griff = regler:CreateTexture(nil, "ARTWORK")
  griff:SetColorTexture(0.6, 0.5, 0.2, 0.9)
  griff:SetSize(8, 40)
  regler:SetThumbTexture(griff)
  regler:SetMinMaxValues(0, 0)
  regler:SetValueStep(1)
  regler:SetValue(0)
  regler:SetScript("OnValueChanged", function(_, wert)
    local neu = math.floor((wert or 0) + 0.5)
    if neu ~= versatz then
      versatz = neu
      ns.Neu()
    end
  end)

  leerText = ui.Text(f, "GameFontDisable", "CENTER")
  leerText:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -190)
  leerText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -60, -190)
  if leerText.SetWordWrap then leerText:SetWordWrap(true) end

  -- Fußzeile
  fussText = ui.Text(f, "GameFontDisableSmall")
  fussText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 11)
  fussText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 11)

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
  "/pa scan - Auktionshaus lesen oder Auctionator-Preise auswerten (muss offen sein)",
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
