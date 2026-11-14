-- Preisanker: Fenster mit zwei Listen und die Befehle /preisanker und /pa.

local ADDON, ns = ...

local ZEILEN = 14
local ZEILENHOEHE = 22
local BREITE = 660

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

local fenster, zeilen, kopf, statusText, fussText, reiter
local liste = {}
local blatt, versatz = 1, 0

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
  versatz = math.max(0, math.min(versatz, #liste - ZEILEN))
  for i = 1, ZEILEN do
    local e = liste[i + versatz]
    if e then ZeileFuellen(zeilen[i], e) else zeilen[i]:Hide() end
  end
  statusText:SetText(StatusZeile())
  local b = ns.db.bilanz
  local fuss = ("Bilanz: ausgegeben %s, beim Händler erlöst %s"):format(ns.Geld(b.ausgegeben), ns.Geld(b.erloest))
  local offen = ns.OffeneTeile()
  if offen > 0 then fuss = fuss .. (" · noch zu verkaufen: %d Teile"):format(offen) end
  if #liste > ZEILEN then
    fuss = fuss .. (" · Zeile %d-%d von %d (Mausrad)"):format(versatz + 1, math.min(versatz + ZEILEN, #liste), #liste)
  end
  fussText:SetText(fuss)
  reiter[1]:SetEnabled(blatt ~= 1)
  reiter[2]:SetEnabled(blatt ~= 2)
  fenster.scanKnopf:SetEnabled(ns.ahOffen and not ns.scan and not ns.kauf and true or false)
end

local function SpaltenSetzen()
  local spalten = SPALTEN[blatt]
  for _, ziel in ipairs({ kopf, unpack(zeilen) }) do
    local x = 28
    for i = 1, 6 do
      local zelle, spalte = ziel.zellen[i], spalten[i]
      if spalte then
        zelle:ClearAllPoints()
        zelle:SetPoint("LEFT", ziel, "LEFT", x, 0)
        zelle:SetWidth(spalte[2])
        zelle:SetJustifyH(spalte[3])
        zelle:Show()
        if ziel == kopf then zelle:SetText(spalte[1]) end
        x = x + spalte[2] + 6
      else
        zelle:Hide()
      end
    end
  end
end

local function BlattWaehlen(nummer)
  blatt, versatz = nummer, 0
  SpaltenSetzen()
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

function ns.FensterBauen()
  if fenster then return end
  local f = CreateFrame("Frame", "PreisankerFenster", UIParent)
  fenster = f
  f:SetSize(BREITE, 96 + ZEILEN * ZEILENHOEHE + 30)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "PreisankerFenster") -- schließt mit Esc

  local grund = f:CreateTexture(nil, "BACKGROUND")
  grund:SetAllPoints()
  grund:SetColorTexture(0.06, 0.06, 0.08, 0.94)
  local leiste = f:CreateTexture(nil, "BORDER")
  leiste:SetPoint("TOPLEFT")
  leiste:SetPoint("TOPRIGHT")
  leiste:SetHeight(26)
  leiste:SetColorTexture(0.16, 0.13, 0.05, 1)

  local titel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titel:SetPoint("TOPLEFT", 10, -7)
  titel:SetText("Preisanker")

  local zu = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  zu:SetPoint("TOPRIGHT", 2, 2)

  reiter = {}
  for i, text in ipairs({ "Unter Händlerpreis", "Händlerware" }) do
    local r = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    r:SetSize(150, 22)
    r:SetPoint("TOPLEFT", 8 + (i - 1) * 154, -32)
    r:SetText(text)
    r:SetScript("OnClick", function() BlattWaehlen(i) end)
    reiter[i] = r
  end

  f.scanKnopf = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.scanKnopf:SetSize(110, 22)
  f.scanKnopf:SetPoint("TOPRIGHT", -8, -32)
  f.scanKnopf:SetText("Scannen")
  f.scanKnopf:SetScript("OnClick", function() ns.ScanStarten() end)

  statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", 10, -60)
  statusText:SetPoint("TOPRIGHT", -10, -60)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(false)

  kopf = CreateFrame("Frame", nil, f)
  kopf:SetPoint("TOPLEFT", 4, -76)
  kopf:SetPoint("TOPRIGHT", -4, -76)
  kopf:SetHeight(18)
  kopf.zellen = Zellen(kopf, "GameFontNormalSmall")

  zeilen = {}
  for i = 1, ZEILEN do
    local zeile = CreateFrame("Button", nil, f)
    zeile:SetPoint("TOPLEFT", 4, -96 - (i - 1) * ZEILENHOEHE)
    zeile:SetPoint("TOPRIGHT", -4, -96 - (i - 1) * ZEILENHOEHE)
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
  end

  fussText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fussText:SetPoint("BOTTOMLEFT", 10, 9)
  fussText:SetPoint("BOTTOMRIGHT", -10, 9)
  fussText:SetJustifyH("LEFT")
  fussText:SetWordWrap(false)

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, richtung)
    versatz = versatz - richtung * 3
    ns.Neu()
  end)
  f:SetScript("OnShow", ns.Neu)
  f:SetScript("OnUpdate", function()
    if ns.schmutzig then
      ns.schmutzig = false
      Zeichnen()
    end
  end)

  SpaltenSetzen()
end

function ns.FensterZeigen(an)
  if not fenster then return end
  if an == nil then an = not fenster:IsShown() end
  fenster:SetShown(an)
end

-- Beim ersten Öffnen neben das Auktionshaus setzen; danach bleibt es, wo der Spieler es hinzieht.
local angedockt
function ns.AuktionshausAuf()
  if not (fenster and ns.opt.mitAuktionshaus) then return end
  if not angedockt and AuctionHouseFrame then
    angedockt = true
    fenster:ClearAllPoints()
    fenster:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
  end
  fenster:Show()
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
