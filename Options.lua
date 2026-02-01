local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- Options Panel (Modern Blizzard UI)
-------------------------------------------------------------------------------

local optionsFrame
local locationsScrollBox
local optionsCategory

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

local function CreateSectionHeader(parent, text, anchor, offsetY)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", 0, offsetY or -16)
    header:SetText(text)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    line:SetColorTexture(0.6, 0.6, 0.6, 0.4)

    return header
end

local function CreateCheckbox(parent, label, tooltip, anchor, offsetY, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -8)
    check.text = check.text or check.Text
    check.text:SetText(" " .. label)
    check.text:SetFontObject("GameFontHighlight")
    check:SetChecked(getValue())
    check:SetScript("OnClick", function(self)
        setValue(self:GetChecked())
    end)

    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return check
end

-------------------------------------------------------------------------------
-- Location Row
-------------------------------------------------------------------------------

local function CreateLocationRow(parent, index, location, totalCount)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(36)
    row:SetPoint("LEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)

    -- Background (alternating)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(1, 1, 1, 0.03)
    else
        bg:SetColorTexture(0, 0, 0, 0.03)
    end

    -- Hover highlight
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)

    -- Index number
    local indexText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    indexText:SetPoint("LEFT", 8, 0)
    indexText:SetWidth(24)
    indexText:SetText(index .. ".")
    indexText:SetTextColor(0.6, 0.6, 0.6)

    -- Location name with neighborhood info (type and name)
    local displayName = location.name
    local neighborhoodInfo = ""
    if location.neighborhoodType and location.neighborhoodType ~= "" then
        neighborhoodInfo = location.neighborhoodType
    end
    if location.neighborhoodName and location.neighborhoodName ~= "" then
        if neighborhoodInfo ~= "" then
            neighborhoodInfo = neighborhoodInfo .. " - " .. location.neighborhoodName
        else
            neighborhoodInfo = location.neighborhoodName
        end
    end
    if neighborhoodInfo ~= "" then
        displayName = displayName .. " |cFF888888(" .. neighborhoodInfo .. ")|r"
    end

    local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    nameText:SetPoint("LEFT", indexText, "RIGHT", 8, 0)
    nameText:SetPoint("RIGHT", row, "CENTER", 40, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(displayName)
    nameText:SetWordWrap(false)

    -- Button container (right side)
    local buttonContainer = CreateFrame("Frame", nil, row)
    buttonContainer:SetPoint("RIGHT", -8, 0)
    buttonContainer:SetSize(260, 28)

    -- Delete button (rightmost)
    local deleteBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    deleteBtn:SetSize(60, 24)
    deleteBtn:SetPoint("RIGHT", 0, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:GetFontString():SetTextColor(1, 0.3, 0.3)
    deleteBtn:SetScript("OnClick", function()
        if addon.db.options.confirmDelete then
            addon:ShowDeleteConfirmDialog(index)
        else
            addon:RemoveLocation(index)
            addon:RefreshOptionsLocations()
        end
    end)

    -- Rename button
    local renameBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    renameBtn:SetSize(60, 24)
    renameBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnClick", function()
        addon:ShowRenameDialog(index)
    end)

    -- Create Macro button - creates a macro for this teleport location
    local macroName = "MHT " .. index .. ": " .. location.name
    local macroBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    macroBtn:SetSize(85, 24)
    macroBtn:SetPoint("RIGHT", renameBtn, "LEFT", -4, 0)
    macroBtn:SetText("Create Macro")

    -- Check if macro already exists and disable button if so
    local existingMacro = GetMacroIndexByName(macroName)
    if existingMacro and existingMacro > 0 then
        macroBtn:Disable()
        macroBtn:SetText("Macro Exists")
    end

    macroBtn:SetScript("OnClick", function()
        -- Set up the secure button (hidden, for macro use)
        local secureBtn = addon:GetSecureTeleportButton(index)
        if location.neighborhoodGUID and location.houseGUID and location.plotID then
            secureBtn:SetTeleportAction(location.neighborhoodGUID, location.houseGUID, location.plotID)
        end

        -- Create the macro
        local macroBody = "/click " .. secureBtn:GetName()

        -- Use numbered icons (texture IDs for 1-9) or home icon for 10+
        local macroIcon
        if index >= 1 and index <= 9 then
            macroIcon = 6033345 + index  -- 6033346 (_1) to 6033354 (_9)
        else
            macroIcon = 7252953  -- ui_homestone_64
        end

        -- Check macro limits
        local numGlobal, numPerChar = GetNumMacros()
        if numGlobal < MAX_ACCOUNT_MACROS then
            -- Create new global macro
            local newIndex = CreateMacro(macroName, macroIcon, macroBody, false)
            if newIndex then
                addon:Print("Created macro: |cFFFFCC00" .. macroName .. "|r")
                addon:Print("Drag it from the Macro panel (|cFFFFCC00/macro|r) to your action bar.")
                macroBtn:Disable()
                macroBtn:SetText("Macro Exists")
                -- Update macro slots counter
                if optionsFrame and optionsFrame.UpdateMacroSlotsText then
                    optionsFrame.UpdateMacroSlotsText()
                end
            else
                addon:Print("|cFFFF4444Failed to create macro.|r")
            end
        else
            addon:Print("|cFFFF4444Macro limit reached!|r You have " .. numGlobal .. "/" .. MAX_ACCOUNT_MACROS .. " account macros.")
            addon:Print("Delete an unused macro or manually create: |cFFFFCC00" .. macroBody .. "|r")
        end
    end)
    macroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Create Teleport Macro", 1, 1, 1)
        GameTooltip:AddLine("Creates macro |cFFFFCC00" .. macroName .. "|r to teleport to " .. location.name .. ".", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("After creating, drag the macro from", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("the Macro panel to your action bar.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    macroBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

-------------------------------------------------------------------------------
-- Refresh Locations List
-------------------------------------------------------------------------------

function addon:RefreshOptionsLocations()
    if not locationsScrollBox then return end

    -- Clear existing children (frames)
    for _, child in pairs({locationsScrollBox.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Clear existing regions (font strings, textures)
    for _, region in pairs({locationsScrollBox.content:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end

    local locations = self:GetLocations()

    if #locations == 0 then
        -- Empty state
        local emptyText = locationsScrollBox.content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        emptyText:SetPoint("TOPLEFT", 8, -16)
        emptyText:SetPoint("RIGHT", -8, 0)
        emptyText:SetJustifyH("LEFT")
        emptyText:SetText("No saved locations.\n\nGo to a housing plot and click 'Add Current Location' below,\nor use |cFFFFCC00/mht add [name]|r")
        locationsScrollBox.content:SetHeight(80)
    else
        local yOffset = 0
        for i, loc in ipairs(locations) do
            local row = CreateLocationRow(locationsScrollBox.content, i, loc, #locations)
            row:SetPoint("TOPLEFT", 0, yOffset)
            yOffset = yOffset - 36
        end
        locationsScrollBox.content:SetHeight(math.max(80, #locations * 36))
    end

    -- Update macro slots counter
    if optionsFrame and optionsFrame.UpdateMacroSlotsText then
        optionsFrame.UpdateMacroSlotsText()
    end
end

-------------------------------------------------------------------------------
-- Create Options Frame
-------------------------------------------------------------------------------

local function CreateOptionsFrame()
    local frame = CreateFrame("Frame", "MHT_OptionsFrame", UIParent)
    frame:Hide()

    -- Main scroll frame for entire panel
    local mainScroll = CreateFrame("ScrollFrame", "MHT_OptionsScrollFrame", frame, "UIPanelScrollFrameTemplate")
    mainScroll:SetPoint("TOPLEFT", 0, 0)
    mainScroll:SetPoint("BOTTOMRIGHT", -24, 0)

    local panel = CreateFrame("Frame", nil, mainScroll)
    panel:SetWidth(550)
    panel:SetHeight(800)
    mainScroll:SetScrollChild(panel)

    -- Update panel width when scroll frame resizes
    mainScroll:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        if width and width > 0 then
            panel:SetWidth(width)
        end
    end)

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Multiple House Teleports")

    -- Version
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("|cFF888888v" .. (addon.version or "1.0.0") .. "|r")

    -- Description
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Save multiple housing plot locations and teleport between them.")

    -- Credit
    local credit = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    credit:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -4)
    credit:SetText("Original discovery by TheIceBadger")

    ---------------------------------------------------------------------------
    -- General Settings Section
    ---------------------------------------------------------------------------
    local generalHeader = CreateSectionHeader(panel, "General Settings", credit, -16)

    local confirmDeleteCheck = CreateCheckbox(
        panel,
        "Confirm Before Deleting",
        "Show a confirmation dialog before deleting a saved location.",
        generalHeader, -8,
        function() return addon.db.options.confirmDelete end,
        function(value) addon.db.options.confirmDelete = value end
    )

    local hideMinimapCheck = CreateCheckbox(
        panel,
        "Show Minimap Icon",
        "Show the minimap button for quick access to options.",
        confirmDeleteCheck, -4,
        function() return not addon.db.minimap.hide end,
        function(value)
            addon.db.minimap.hide = not value
            addon:ToggleMinimapIcon()
        end
    )

    -- Stale ID info text
    local staleInfoText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    staleInfoText:SetPoint("TOPLEFT", hideMinimapCheck, "BOTTOMLEFT", 0, -16)
    staleInfoText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    staleInfoText:SetJustifyH("LEFT")
    staleInfoText:SetSpacing(4)
    staleInfoText:SetText(
        "Housing IDs can become outdated when plots change. There are two ways to fix this:\n" ..
        "  1. Visit the neighborhood and plot — the ID updates automatically on arrival.\n" ..
        "  2. Press the teleport macro repeatedly — the addon cycles through possible IDs (up to 9 attempts).\n\n" ..
        "|cFFFF9900Note:|r Some teleport failures are not caused by outdated IDs. See \"Common reasons\" below."
    )

    ---------------------------------------------------------------------------
    -- Saved Locations Section
    ---------------------------------------------------------------------------
    local locationsHeader = CreateSectionHeader(panel, "Saved Locations", staleInfoText, -16)

    -- Scroll frame for locations
    local scrollContainer = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    scrollContainer:SetPoint("TOPLEFT", locationsHeader, "BOTTOMLEFT", 0, -12)
    scrollContainer:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    scrollContainer:SetHeight(180)
    scrollContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollContainer:SetBackdropColor(0, 0, 0, 0.2)
    scrollContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", nil, scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollContent)

    scrollFrame.content = scrollContent
    locationsScrollBox = scrollFrame

    -- Update content width when frame resizes
    scrollContainer:SetScript("OnSizeChanged", function(self)
        scrollContent:SetWidth(self:GetWidth() - 30)
    end)

    -- Description text about macros
    local macroDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    macroDesc:SetPoint("TOPLEFT", scrollContainer, "BOTTOMLEFT", 0, -8)
    macroDesc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    macroDesc:SetJustifyH("LEFT")
    macroDesc:SetText("Each location creates a macro. Drag macros from |cFFFFCC00/macro|r to your action bar.")

    -- Macro slots text
    local macroSlotsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    macroSlotsText:SetPoint("TOPLEFT", macroDesc, "BOTTOMLEFT", 0, -4)
    macroSlotsText:SetJustifyH("LEFT")

    local function UpdateMacroSlotsText()
        local numGlobal = GetNumMacros()
        local available = MAX_ACCOUNT_MACROS - numGlobal
        local color = available > 5 and "|cFF00FF00" or (available > 0 and "|cFFFFFF00" or "|cFFFF4444")
        macroSlotsText:SetText("Macro slots: " .. color .. numGlobal .. "/" .. MAX_ACCOUNT_MACROS .. "|r (" .. available .. " available)")
    end

    -- Add Location button (left side)
    local addLocationBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addLocationBtn:SetSize(160, 28)
    addLocationBtn:SetPoint("TOPLEFT", macroSlotsText, "BOTTOMLEFT", 0, -8)
    addLocationBtn:SetText("Add Current Location")
    addLocationBtn:SetScript("OnClick", function()
        addon:ShowAddLocationDialog()
    end)
    addLocationBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add Current Location", 1, 1, 1)
        GameTooltip:AddLine("Save your current plot location. You must be inside a housing plot.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    addLocationBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Open Macro Window button (next to Add Location)
    local openMacroBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openMacroBtn:SetSize(140, 28)
    openMacroBtn:SetPoint("LEFT", addLocationBtn, "RIGHT", 8, 0)
    openMacroBtn:SetText("Open Macro Window")
    openMacroBtn:SetScript("OnClick", function()
        -- Close Settings first — WoW only allows one major panel at a time
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end

        if not MacroFrame then
            MacroFrame_LoadUI()
        end
        if MacroFrame then
            ShowUIPanel(MacroFrame)
        end
    end)

    -- Create Default Home Macro button (right side)
    local homeMacroName = "MHT 0: My Home"
    local defaultMacroBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    defaultMacroBtn:SetSize(170, 28)
    defaultMacroBtn:SetPoint("TOP", addLocationBtn, "TOP", 0, 0)
    defaultMacroBtn:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    defaultMacroBtn:SetText("Create Home Macro")
    defaultMacroBtn.macroName = homeMacroName

    -- Function to update button state based on macro existence
    local function UpdateHomeMacroButtonState()
        local existingMacro = GetMacroIndexByName(homeMacroName)
        if existingMacro and existingMacro > 0 then
            defaultMacroBtn:Disable()
            defaultMacroBtn:SetText("Home Macro Exists")
        else
            defaultMacroBtn:Enable()
            defaultMacroBtn:SetText("Create Home Macro")
        end
    end

    defaultMacroBtn:SetScript("OnClick", function(self)
        self:SetText("Loading...")
        self:Disable()

        addon:RequestPlayerHouseInfo(function(houseInfo)
            if not houseInfo then
                addon:Print("|cFFFF4444Could not get your home info. Do you own a house?|r")
                UpdateHomeMacroButtonState()
                return
            end

            -- Get the secure button
            local btn = addon:GetDefaultHomeButton()

            -- Create the macro
            local macroBody = "/click " .. btn:GetName()
            local macroIcon = 7252953  -- ui_homestone_64

            local numGlobal, numPerChar = GetNumMacros()
            if numGlobal < MAX_ACCOUNT_MACROS then
                local newIndex = CreateMacro(homeMacroName, macroIcon, macroBody, false)
                if newIndex then
                    addon:Print("Created macro: |cFFFFCC00" .. homeMacroName .. "|r")
                    addon:Print("Drag it from the Macro panel (|cFFFFCC00/macro|r) to your action bar.")
                    self:SetText("Home Macro Exists")
                    UpdateMacroSlotsText()
                else
                    addon:Print("|cFFFF4444Failed to create macro.|r")
                    UpdateHomeMacroButtonState()
                end
            else
                addon:Print("|cFFFF4444Macro limit reached!|r")
                addon:Print("Manually create: |cFFFFCC00" .. macroBody .. "|r")
                UpdateHomeMacroButtonState()
            end
        end)
    end)
    defaultMacroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Create Home Macro", 1, 1, 1)
        GameTooltip:AddLine("Creates macro |cFFFFCC00" .. homeMacroName .. "|r to teleport to your own home.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    defaultMacroBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Store references for updating on show
    frame.defaultMacroBtn = defaultMacroBtn
    frame.UpdateHomeMacroButtonState = UpdateHomeMacroButtonState
    frame.UpdateMacroSlotsText = UpdateMacroSlotsText

    -- Update button state based on whether we can add a location
    local function UpdateAddButtonState()
        local canAdd = addon:CanAddLocation()
        addLocationBtn:SetEnabled(canAdd)
        if canAdd then
            addLocationBtn:GetFontString():SetTextColor(1, 0.82, 0)
        else
            addLocationBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end

    frame:SetScript("OnShow", function(self)
        -- Update panel width to match scroll frame
        local width = mainScroll:GetWidth()
        if width and width > 0 then
            panel:SetWidth(width)
        end
        addon:RefreshOptionsLocations()
        UpdateAddButtonState()
        UpdateMacroSlotsText()
        -- Update home macro button state
        if self.UpdateHomeMacroButtonState then
            self.UpdateHomeMacroButtonState()
        end
    end)

    ---------------------------------------------------------------------------
    -- Troubleshooting Section
    ---------------------------------------------------------------------------
    local troubleshootHeader = CreateSectionHeader(panel, "Troubleshooting", addLocationBtn, -20)

    local troubleshootText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    troubleshootText:SetPoint("TOPLEFT", troubleshootHeader, "BOTTOMLEFT", 0, -8)
    troubleshootText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    troubleshootText:SetJustifyH("LEFT")
    troubleshootText:SetSpacing(4)
    troubleshootText:SetText(
        "|cFFFF6666Common reasons for \"Permission denied\":|r\n" ..
        "- Teleporting to a plot in a public neighborhood (not allowed)\n" ..
        "- Plot owner has access set to \"No one\" or restricted\n" ..
        "- You are not on the owner's friends/guild list (if required)\n" ..
        "- The plot no longer exists or owner moved"
    )

    ---------------------------------------------------------------------------
    -- Commands Section
    ---------------------------------------------------------------------------
    local commandsHeader = CreateSectionHeader(panel, "Commands", troubleshootText, -20)

    local commandsText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commandsText:SetPoint("TOPLEFT", commandsHeader, "BOTTOMLEFT", 0, -8)
    commandsText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    commandsText:SetJustifyH("LEFT")
    commandsText:SetSpacing(4)
    commandsText:SetText(
        "|cFFFFCC00/mht|r - Show commands\n" ..
        "|cFFFFCC00/mht add [name]|r - Add current location\n" ..
        "|cFFFFCC00/mht list|r - List saved locations\n" ..
        "|cFFFFCC00/mht teleport <#>|r - Teleport to location\n" ..
        "|cFFFFCC00/mht delete <#>|r - Delete a location\n" ..
        "|cFFFFCC00/mht options|r - Open this panel"
    )

    return frame
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function addon:InitOptions()
    optionsFrame = CreateOptionsFrame()

    -- Register with modern Settings API
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "Multiple House Teleports")
        Settings.RegisterAddOnCategory(category)
        optionsCategory = category
    end
end

function addon:OpenOptions()
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
    elseif optionsFrame then
        -- Fallback: show frame directly (shouldn't normally happen)
        optionsFrame:Show()
    end
end
