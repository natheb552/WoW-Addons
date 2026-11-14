-- Händlerprofit: Fenster mit drei Reitern (öffnen mit /hp).
--   Herstellen:         Rezepte mit Händlergewinn (dieser Teil).
--   Unter Händlerpreis, Händlerware: die Listen von Preisanker (Preisanker\Fenster.lua).
local ADDON, ns = ...
local anker = ns.anker

local MIN_WIDTH, MIN_HEIGHT = 660, 300
local ROW_HEIGHT, MAX_ROWS = 24, 200
-- Die Namensspalte nimmt den Platz, der übrig bleibt
local COLS = { skill = 110, cost = 90, sell = 90, profit = 95 }
local COL_ORDER = { "name", "skill", "cost", "sell", "profit" }
local GOLD = { 1, 0.82, 0 }

local TABS = { "Herstellen", "Unter Händlerpreis", "Händlerware" }

local window, craft, content, scroll, slider, header, emptyText, summaryText, scanText, statusText
local sourceButton, scanButton
local UpdateScanControls -- weiter unten
local rows, checks, tabs = {}, {}, {}
local tab = 1
local filterButton, filterMenu, filterEntries = nil, nil, {}

-- ---------------------------------------------------------------- Bausteine

local function Fill(frame, layer, r, g, b, a)
  local t = frame:CreateTexture(nil, layer)
  t:SetAllPoints()
  t:SetColorTexture(r, g, b, a)
  return t
end

-- Dünner Rahmen aus vier Linien
local function Border(frame, r, g, b, a)
  local function line(p1, p2, w, h)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, a)
    t:SetPoint(p1, frame, p1, 0, 0)
    t:SetPoint(p2, frame, p2, 0, 0)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  line("TOPLEFT", "TOPRIGHT", nil, 1)
  line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  line("TOPLEFT", "BOTTOMLEFT", 1, nil)
  line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

-- Flacher Knopf im Stil des Fensters, mit Beschriftung in .label
local function FlatButton(parent, width, label, justify)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 22)
  Fill(b, "BACKGROUND", 0.16, 0.16, 0.18, 1)
  Border(b, 0.4, 0.4, 0.45, 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  b.label = Text(b, "GameFontHighlightSmall", justify)
  b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b.label:SetText(label or "")
  return b
end

-- Verteilt die fünf Spaltentexte auf die verfügbare Breite
local function LayoutColumns(t, parent, width)
  local fixed = 26 + COLS.skill + COLS.cost + COLS.sell + COLS.profit + 4 * 4 + 6
  local nameWidth = math.max(120, width - fixed)
  local x = 26
  for _, key in ipairs(COL_ORDER) do
    local w = key == "name" and nameWidth or COLS[key]
    t[key]:ClearAllPoints()
    t[key]:SetPoint("LEFT", parent, "LEFT", x, 0)
    t[key]:SetWidth(w)
    x = x + w + 4
  end
end

-- Legt die fünf Spaltentexte einer Zeile an
local function Columns(parent, font, width)
  local t = {}
  for _, key in ipairs(COL_ORDER) do
    t[key] = Text(parent, font, (key == "name" or key == "skill") and "LEFT" or "RIGHT")
  end
  LayoutColumns(t, parent, width)
  return t
end

local function QualityColor(quality)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- ---------------------------------------------------------------- Tooltip

local function ShowRowTooltip(self)
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. d.itemID)
  if not ok then GameTooltip:SetText(d.name) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Materialien", GOLD[1], GOLD[2], GOLD[3])
  for _, p in ipairs(d.parts) do
    local name = ns.ItemData(p.itemID) or ("Item " .. p.itemID)
    local right = "kein Preis"
    if p.price then
      right = ns.Money(p.price * p.count) .. " |cff999999(" .. p.source
        .. (p.count > 1 and (", je " .. ns.Money(p.price)) or "") .. "|cff999999)|r"
    end
    GameTooltip:AddDoubleLine(p.count .. "x " .. name, right, 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Materialkosten", ns.Money(d.cost), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Händler zahlt" .. (d.count > 1 and (" (" .. d.count .. " Stück)") or ""),
    ns.Money(d.sell * d.count), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Gewinn", ns.Money(d.profit), 0.2, 1, 0.2, 0.2, 1, 0.2)
  if d.stale then
    GameTooltip:AddLine("Nutzt einen AH-Preis von vor " .. d.age .. " Tagen (nicht im letzten Scan)", 1, 0.5, 0.2)
  end
  if d.cooldown then
    local cd = d.cooldown >= 60 and (math.floor(d.cooldown / 60 + 0.5) .. " Std.") or (d.cooldown .. " Min.")
    GameTooltip:AddLine("Rezept hat " .. cd .. " Abklingzeit", 1, 0.5, 0.2)
  end
  if not d.known then
    GameTooltip:AddLine("Rezept nicht als gelernt erkannt", 1, 0.3, 0.3)
  end
  GameTooltip:AddLine("H = Händler, AH = Auktionshaus, selbst = selbst hergestellt", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

-- ---------------------------------------------------------------- Zeilen

local function GetRow(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, content)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

  if i % 2 == 0 then Fill(row, "BACKGROUND", 1, 1, 1, 0.035) end

  -- Balken im Hintergrund: Gewinn im Verhältnis zum besten Rezept
  row.bar = row:CreateTexture(nil, "BORDER")
  row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
  row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
  row.bar:SetColorTexture(0.2, 0.9, 0.3, 0.10)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.text = Columns(row, "GameFontHighlightSmall", content:GetWidth())
  row.text.name:SetFontObject("GameFontHighlight")
  row.text.profit:SetFontObject("GameFontHighlight")

  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.10)

  row:SetScript("OnEnter", ShowRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    if self.data and self.data.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
      ChatEdit_InsertLink(self.data.link)
    end
  end)
  rows[i] = row
  return row
end

-- ---------------------------------------------------------------- Bedienelemente

local function MakeCheck(parent, label, key, x)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -34)
  local text = Text(cb, "GameFontHighlightSmall")
  text:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  text:SetText(label)
  cb:SetScript("OnClick", function(self)
    ns.db[key] = self:GetChecked() and true or false
    ns.Refresh()
  end)
  cb.key = key
  return cb
end

local function BuildFilter(parent)
  filterButton = FlatButton(parent, 180)
  filterButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -34)
  filterButton.label:SetPoint("RIGHT", filterButton, "RIGHT", -20, 0)
  local arrow = filterButton:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", filterButton, "RIGHT", -5, 0)
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  if arrow.SetRotation then arrow:SetRotation(-math.pi / 2) end

  local ids = {}
  for id in pairs(ns.PROFESSIONS) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return ns.PROFESSIONS[a] < ns.PROFESSIONS[b] end)
  table.insert(ids, 1, false) -- false = alle Berufe

  filterMenu = CreateFrame("Frame", nil, parent)
  filterMenu:SetSize(180, #ids * 20 + 8)
  filterMenu:SetPoint("TOPLEFT", filterButton, "BOTTOMLEFT", 0, -2)
  filterMenu:SetFrameStrata("DIALOG")
  filterMenu:EnableMouse(true)
  Fill(filterMenu, "BACKGROUND", 0.08, 0.08, 0.10, 0.98)
  Border(filterMenu, 0.4, 0.4, 0.45, 1)

  for i, id in ipairs(ids) do
    local entry = CreateFrame("Button", nil, filterMenu)
    entry:SetSize(172, 20)
    entry:SetPoint("TOPLEFT", filterMenu, "TOPLEFT", 4, -4 - (i - 1) * 20)
    entry.id = id or nil
    entry.label = Text(entry, "GameFontHighlightSmall")
    entry.label:SetPoint("LEFT", entry, "LEFT", 8, 0)
    entry.label:SetText(id and ns.PROFESSIONS[id] or "Alle Berufe")
    local ehl = entry:CreateTexture(nil, "HIGHLIGHT")
    ehl:SetAllPoints()
    ehl:SetColorTexture(1, 0.82, 0, 0.18)
    entry:SetScript("OnClick", function()
      ns.db.skillFilter = id or nil
      filterMenu:Hide()
      ns.Refresh()
    end)
    filterEntries[i] = entry
  end
  filterMenu:Hide()

  filterButton:SetScript("OnClick", function()
    if filterMenu:IsShown() then filterMenu:Hide() else filterMenu:Show() end
  end)
end

-- ---------------------------------------------------------------- Fenster

-- Passt den Rollbalken an Listenlänge und Fensterhöhe an
local function UpdateScroll()
  local range = math.max(0, content:GetHeight() - scroll:GetHeight())
  slider:SetMinMaxValues(0, range)
  local value = math.min(slider:GetValue() or 0, range)
  slider:SetValue(value)
  scroll:SetVerticalScroll(value)
  if range > 0 then slider:Show() else slider:Hide() end
end

-- Nach einer Größenänderung: Spalten, Balken und Rollbalken neu ausrichten
local function Relayout()
  local width = scroll:GetWidth()
  if not width or width <= 0 then return end
  content:SetWidth(width)
  LayoutColumns(header.text, header, width)
  for _, row in ipairs(rows) do
    LayoutColumns(row.text, row, width)
    row.bar:SetWidth(math.max(1, width * (row.ratio or 0)))
  end
  UpdateScroll()
end

local function Build()
  window = CreateFrame("Frame", "HaendlerprofitFrame", UIParent)
  window:SetSize(math.max(MIN_WIDTH, ns.db.width or MIN_WIDTH), math.max(MIN_HEIGHT, ns.db.height or 500))
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetFrameStrata("HIGH")
  window:SetClampedToScreen(true)
  if UISpecialFrames then tinsert(UISpecialFrames, "HaendlerprofitFrame") end
  window:SetResizable(true)
  if window.SetResizeBounds then
    window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
  elseif window.SetMinResize then
    window:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
  end
  Fill(window, "BACKGROUND", 0.06, 0.06, 0.07, 0.96)
  Border(window, 0.35, 0.30, 0.15, 1)

  -- Titelleiste
  local titleBar = CreateFrame("Frame", nil, window)
  titleBar:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(26)
  Fill(titleBar, "BACKGROUND", 0.13, 0.11, 0.06, 1)
  local title = Text(titleBar, "GameFontNormal")
  title:SetPoint("LEFT", titleBar, "LEFT", 11, 0)
  title:SetText("Händlerprofit")
  local subtitle = Text(titleBar, "GameFontDisableSmall")
  subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
  subtitle:SetText("Gewinn mit festen Händlerpreisen")
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() window:Hide() end)

  -- Reiter
  for i, label in ipairs(TABS) do
    local b = FlatButton(window, 150, label, "CENTER")
    b:SetPoint("TOPLEFT", window, "TOPLEFT", 12 + (i - 1) * 154, -31)
    b:SetScript("OnClick", function() ns.SelectTab(i) end)
    tabs[i] = b
  end

  -- Inhalt des Reiters »Herstellen«; die beiden anderen baut Preisanker
  craft = CreateFrame("Frame", nil, window)
  craft:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -26)
  craft:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
  anker.FensterBauen(window)

  -- Filterzeile
  BuildFilter(craft)
  checks[1] = MakeCheck(craft, "Nur gelernte", "onlyKnown", 204)
  checks[2] = MakeCheck(craft, "Zwischenprodukte selbst herstellen", "craftIntermediates", 312)
  checks[3] = MakeCheck(craft, "Chat-Meldung", "announce", 540)

  -- Zusammenfassung
  local summary = CreateFrame("Frame", nil, craft)
  summary:SetPoint("TOPLEFT", craft, "TOPLEFT", 12, -64)
  summary:SetPoint("TOPRIGHT", craft, "TOPRIGHT", -12, -64)
  summary:SetHeight(26)
  Fill(summary, "BACKGROUND", 1, 1, 1, 0.04)
  -- Rechts: Preisquelle umschalten, daneben (nur beim eigenen Scan) der Scan-Knopf
  sourceButton = FlatButton(summary, 132, "", "CENTER")
  sourceButton:SetPoint("RIGHT", summary, "RIGHT", -2, 0)
  sourceButton:SetScript("OnClick", function()
    ns.db.priceSource = ns.PriceSource() == "scan" and "auctionator" or "scan"
    ns.Refresh()
  end)
  sourceButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Woher die Auktionspreise kommen")
    GameTooltip:AddLine("Auctionator: Preise aus dessen Scans.", 1, 1, 1, true)
    GameTooltip:AddLine("Eigener Scan: »Scannen« liest das offene Auktionshaus (etwa eine halbe Minute).", 1, 1, 1, true)
    GameTooltip:AddLine("Klick wechselt die Quelle.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  sourceButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  scanButton = FlatButton(summary, 66, "Scannen", "CENTER")
  scanButton:SetPoint("RIGHT", sourceButton, "LEFT", -4, 0)
  scanButton:SetScript("OnClick", function() anker.ScanStarten() end)
  scanText = Text(summary, "GameFontHighlightSmall", "RIGHT")
  summaryText = Text(summary, "GameFontHighlight")
  summaryText:SetPoint("LEFT", summary, "LEFT", 8, 0)
  summaryText:SetPoint("RIGHT", scanText, "LEFT", -8, 0)

  -- Spaltenköpfe
  header = CreateFrame("Frame", nil, craft)
  header:SetHeight(20)
  header:SetPoint("TOPLEFT", craft, "TOPLEFT", 12, -96)
  header:SetPoint("TOPRIGHT", craft, "TOPRIGHT", -24, -96)
  local h = Columns(header, "GameFontNormalSmall", MIN_WIDTH - 36)
  header.text = h
  h.name:SetText("Gegenstand")
  h.skill:SetText("Beruf")
  h.cost:SetText("Material")
  h.sell:SetText("Händler zahlt")
  h.profit:SetText("Gewinn")
  local rule = craft:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.35, 0.30, 0.15, 1)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", craft, "TOPLEFT", 12, -117)
  rule:SetPoint("TOPRIGHT", craft, "TOPRIGHT", -12, -117)

  -- Liste
  scroll = CreateFrame("ScrollFrame", nil, craft)
  scroll:SetPoint("TOPLEFT", craft, "TOPLEFT", 12, -120)
  scroll:SetPoint("BOTTOMRIGHT", craft, "BOTTOMRIGHT", -24, 34)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(MIN_WIDTH - 36, ROW_HEIGHT)
  scroll:SetScrollChild(content)

  -- Schmaler Rollbalken
  slider = CreateFrame("Slider", nil, craft)
  slider:SetOrientation("VERTICAL")
  slider:SetWidth(8)
  slider:SetPoint("TOPRIGHT", craft, "TOPRIGHT", -10, -120)
  slider:SetPoint("BOTTOMRIGHT", craft, "BOTTOMRIGHT", -10, 34)
  Fill(slider, "BACKGROUND", 1, 1, 1, 0.05)
  local thumb = slider:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(0.6, 0.5, 0.2, 0.9)
  thumb:SetSize(8, 40)
  slider:SetThumbTexture(thumb)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  slider:SetValue(0)
  slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    local _, max = slider:GetMinMaxValues()
    slider:SetValue(math.max(0, math.min(max or 0, (slider:GetValue() or 0) - delta * ROW_HEIGHT * 3)))
  end)
  scroll:SetScript("OnSizeChanged", Relayout)

  -- Griff zum Ändern der Fenstergröße
  local grip = CreateFrame("Button", nil, window)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    window:StopMovingOrSizing()
    ns.db.width, ns.db.height = window:GetSize()
    Relayout()
  end)

  emptyText = Text(craft, "GameFontDisable", "CENTER")
  emptyText:SetPoint("TOPLEFT", craft, "TOPLEFT", 60, -190)
  emptyText:SetPoint("TOPRIGHT", craft, "TOPRIGHT", -60, -190)
  if emptyText.SetWordWrap then emptyText:SetWordWrap(true) end

  -- Fußzeile
  statusText = Text(craft, "GameFontDisableSmall")
  statusText:SetPoint("BOTTOMLEFT", craft, "BOTTOMLEFT", 14, 11)
  statusText:SetPoint("BOTTOMRIGHT", craft, "BOTTOMRIGHT", -26, 11)

  -- Scan-Knopf und Scan-Anzeige folgen dem Auktionshaus, auch ohne neue Preise
  local wait = 0
  craft:SetScript("OnUpdate", function(_, elapsed)
    wait = wait + (elapsed or 0)
    if wait >= 0.3 then
      wait = 0
      UpdateScanControls()
    end
  end)

  window:SetScript("OnShow", function() ns.SelectTab(tab) end)
  window:SetScript("OnHide", function() filterMenu:Hide() end)
  window:Hide()
end

function ns.IsShown()
  return window and window:IsShown() or false
end

local function ScanStatus()
  local own = ns.PriceSource() == "scan"
  if own and anker.scan then
    return ("|cffffd100Scan läuft: %d Gegenstände|r"):format(anker.zahl.zeilen)
  end
  local last = ns.LastScanTime()
  if not last then
    return own and "|cffff9933Noch kein eigener Scan|r" or "|cffff9933Noch kein AH-Scan gefunden|r"
  end
  local minutes = math.floor((time() - last) / 60)
  local ago
  if minutes < 1 then
    return "|cff33ff33AH-Scan gerade eben|r"
  elseif minutes < 60 then
    ago = minutes .. " Min."
  elseif minutes < 2880 then
    ago = math.floor(minutes / 60) .. " Std."
  else
    ago = math.floor(minutes / 1440) .. " Tagen"
  end
  return (minutes < 120 and "|cff33ff33" or "|cffff9933") .. "AH-Scan vor " .. ago .. "|r"
end

-- Preisquelle, Scan-Knopf und Scan-Anzeige in der Zusammenfassung
function UpdateScanControls()
  local own = ns.PriceSource() == "scan"
  sourceButton.label:SetText("Preise: " .. (own and "eigener Scan" or "Auctionator"))
  scanButton:SetShown(own)
  local ready = own and anker.ahOffen and not anker.scan and not anker.kauf
  scanButton:SetEnabled(ready and true or false)
  if ready then scanButton.label:SetTextColor(1, 1, 1) else scanButton.label:SetTextColor(0.5, 0.5, 0.5) end
  scanText:ClearAllPoints()
  scanText:SetPoint("RIGHT", own and scanButton or sourceButton, "LEFT", -8, 0)
  scanText:SetText(ScanStatus())
end

function ns.Refresh()
  if not window or not window:IsShown() or tab ~= 1 then return end
  for _, cb in ipairs(checks) do cb:SetChecked(ns.db[cb.key]) end
  local skill = ns.db.skillFilter
  filterButton.label:SetText("Beruf: " .. (skill and ns.PROFESSIONS[skill] or "Alle"))
  for _, entry in ipairs(filterEntries) do
    if entry.id == skill then
      entry.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
      entry.label:SetTextColor(1, 1, 1)
    end
  end

  local list, stats = ns.Compute()
  local shown = math.min(#list, MAX_ROWS)
  local best = list[1] and list[1].profit or 1
  for i = 1, shown do
    local d, row = list[i], GetRow(i)
    row.data = d
    row.icon:SetTexture(d.icon)
    row.ratio = d.profit / best
    row.text.name:SetText((d.count > 1 and (d.count .. "x ") or "") .. d.name
      .. (d.cooldown and " |cff999999(Abklingzeit)|r" or ""))
    row.text.name:SetTextColor(QualityColor(d.quality))
    row.text.skill:SetText(ns.PROFESSIONS[d.skill] or "")
    if d.known then row.text.skill:SetTextColor(0.75, 0.75, 0.75) else row.text.skill:SetTextColor(0.45, 0.45, 0.45) end
    row.text.cost:SetText(ns.Money(d.cost))
    row.text.sell:SetText(ns.Money(d.sell * d.count))
    row.text.profit:SetText((d.stale and "|cffff9933+|r" or "|cff33ff33+|r") .. ns.Money(d.profit))
    row:Show()
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(shown, 1) * ROW_HEIGHT)
  Relayout()

  UpdateScanControls()

  local empty, footer = "", ""
  local own = ns.PriceSource() == "scan"
  if not own and not ns.AuctionatorAPI() then
    summaryText:SetText("|cffff5555Auctionator ist nicht geladen|r")
    empty = "Ohne Auctionator gibt es dort keine Preise.\nStelle oben rechts auf »eigener Scan« um."
  elseif own and not ns.LastScanTime() and #list == 0 then
    summaryText:SetText("Noch keine Preise")
    empty = "Öffne das Auktionshaus und drücke oben rechts »Scannen«."
  elseif stats.considered == 0 then
    summaryText:SetText("Keine Rezepte erkannt")
    if skill and ns.db.onlyKnown then
      empty = "Keine gelernten Rezepte für " .. ns.PROFESSIONS[skill] .. " erkannt.\nÖffne einmal das Berufsfenster dieses Berufs."
    else
      empty = "Noch keine gelernten Rezepte erkannt.\nÖffne einmal dein Berufsfenster oder nimm den Haken bei \"Nur gelernte\" heraus."
    end
  else
    if #list == 0 then
      summaryText:SetText("Kein Rezept mit Gewinn")
      empty = "Mit den aktuellen Preisen lohnt sich hier nichts."
    else
      summaryText:SetText(("|cff33ff33%d|r Rezept%s mit Gewinn, bestes: |cff33ff33+|r%s"):format(
        #list, #list == 1 and "" or "e", ns.Money(list[1].profit)))
    end
    footer = ("%d Rezepte geprüft"):format(stats.considered)
    if stats.noPrice > 0 then footer = footer .. (" · %d ohne vollständige Materialpreise"):format(stats.noPrice) end
    if stats.loading > 0 then footer = footer .. (" · %d werden noch geladen"):format(stats.loading) end
    if stats.stale > 0 then footer = footer .. (" · |cffff9933%d mit älteren Preisen (orange)|r"):format(stats.stale) end
  end
  emptyText:SetText(empty)
  statusText:SetText(footer)
end

-- Wählt den Reiter: 1 Herstellen, 2 Unter Händlerpreis, 3 Händlerware
function ns.SelectTab(i)
  tab = i
  if not window then return end
  for n, b in ipairs(tabs) do
    if n == i then b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else b.label:SetTextColor(0.8, 0.8, 0.8) end
  end
  craft:SetShown(i == 1)
  anker.BlattZeigen(i > 1 and i - 1 or nil)
  if i == 1 then ns.Refresh() else filterMenu:Hide() end
end

-- Öffnet das Fenster, auf Wunsch gleich mit einem bestimmten Reiter
function ns.Open(i)
  if not window then Build() end
  tab = i or tab
  if window:IsShown() then ns.SelectTab(tab) else window:Show() end
end

function ns.Close()
  if window then window:Hide() end
end

-- Setzt das Fenster rechts neben einen anderen Rahmen (das Auktionshaus)
function ns.Dock(frame)
  if not window then return end
  window:ClearAllPoints()
  window:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
end

function ns.Toggle()
  if ns.IsShown() then ns.Close() else ns.Open() end
end
