-- Händlerprofit: Fenster mit der Liste (öffnen mit /hp)
local ADDON, ns = ...

local MIN_WIDTH, MIN_HEIGHT = 660, 300
local ROW_HEIGHT, MAX_ROWS = 24, 200
-- Die Namensspalte nimmt den Platz, der übrig bleibt
local COLS = { skill = 110, cost = 90, sell = 90, profit = 95 }
local COL_ORDER = { "name", "skill", "cost", "sell", "profit" }
local GOLD = { 1, 0.82, 0 }

local window, content, scroll, slider, header, emptyText, summaryText, scanText, statusText
local rows, checks = {}, {}
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
  filterButton = CreateFrame("Button", nil, parent)
  filterButton:SetSize(180, 22)
  filterButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -34)
  Fill(filterButton, "BACKGROUND", 0.16, 0.16, 0.18, 1)
  Border(filterButton, 0.4, 0.4, 0.45, 1)
  local hl = filterButton:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  filterButton.label = Text(filterButton, "GameFontHighlightSmall")
  filterButton.label:SetPoint("LEFT", filterButton, "LEFT", 8, 0)
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
  subtitle:SetText("herstellen und beim Händler verkaufen")
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() window:Hide() end)

  -- Filterzeile
  BuildFilter(window)
  checks[1] = MakeCheck(window, "Nur gelernte", "onlyKnown", 204)
  checks[2] = MakeCheck(window, "Zwischenprodukte selbst herstellen", "craftIntermediates", 312)
  checks[3] = MakeCheck(window, "Chat-Meldung", "announce", 540)

  -- Zusammenfassung
  local summary = CreateFrame("Frame", nil, window)
  summary:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -64)
  summary:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, -64)
  summary:SetHeight(26)
  Fill(summary, "BACKGROUND", 1, 1, 1, 0.04)
  summaryText = Text(summary, "GameFontHighlight")
  summaryText:SetPoint("LEFT", summary, "LEFT", 8, 0)
  scanText = Text(summary, "GameFontHighlightSmall", "RIGHT")
  scanText:SetPoint("RIGHT", summary, "RIGHT", -8, 0)

  -- Spaltenköpfe
  header = CreateFrame("Frame", nil, window)
  header:SetHeight(20)
  header:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -96)
  header:SetPoint("TOPRIGHT", window, "TOPRIGHT", -24, -96)
  local h = Columns(header, "GameFontNormalSmall", MIN_WIDTH - 36)
  header.text = h
  h.name:SetText("Gegenstand")
  h.skill:SetText("Beruf")
  h.cost:SetText("Material")
  h.sell:SetText("Händler zahlt")
  h.profit:SetText("Gewinn")
  local rule = window:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.35, 0.30, 0.15, 1)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -117)
  rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, -117)

  -- Liste
  scroll = CreateFrame("ScrollFrame", nil, window)
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -120)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -24, 34)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(MIN_WIDTH - 36, ROW_HEIGHT)
  scroll:SetScrollChild(content)

  -- Schmaler Rollbalken
  slider = CreateFrame("Slider", nil, window)
  slider:SetOrientation("VERTICAL")
  slider:SetWidth(8)
  slider:SetPoint("TOPRIGHT", window, "TOPRIGHT", -10, -120)
  slider:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -10, 34)
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

  emptyText = Text(window, "GameFontDisable", "CENTER")
  emptyText:SetPoint("TOPLEFT", window, "TOPLEFT", 60, -190)
  emptyText:SetPoint("TOPRIGHT", window, "TOPRIGHT", -60, -190)
  if emptyText.SetWordWrap then emptyText:SetWordWrap(true) end

  -- Fußzeile
  statusText = Text(window, "GameFontDisableSmall")
  statusText:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 11)
  statusText:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -26, 11)

  window:SetScript("OnShow", function() ns.Refresh() end)
  window:SetScript("OnHide", function() filterMenu:Hide() end)
  window:Hide()
end

function ns.IsShown()
  return window and window:IsShown()
end

local function ScanStatus()
  local last = ns.LastScanTime()
  if not last then return "|cffff9933Noch kein AH-Scan gefunden|r" end
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

function ns.Refresh()
  if not window or not window:IsShown() then return end
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

  scanText:SetText(ScanStatus())

  local empty, footer = "", ""
  if not ns.AuctionatorAPI() then
    summaryText:SetText("|cffff5555Auctionator ist nicht geladen|r")
    empty = "Ohne Auctionator gibt es keine Preise."
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

function ns.Toggle()
  if not window then Build() end
  if window:IsShown() then window:Hide() else window:Show() end
end
