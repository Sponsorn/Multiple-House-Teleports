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

    -- Location name with neighborhood info
    local displayName = location.name
    if location.neighborhoodName and location.neighborhoodName ~= "" then
        displayName = displayName .. " |cFF888888(" .. location.neighborhoodName .. ")|r"
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

    -- Move Down button
    local downBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    downBtn:SetSize(28, 24)
    downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
    downBtn:SetText("↓")
    local canMoveDown = index < totalCount
    downBtn:SetEnabled(canMoveDown)
    downBtn:SetScript("OnClick", function()
        addon:MoveLocationDown(index)
        addon:RefreshOptionsLocations()
    end)
    if not canMoveDown then
        downBtn:GetFontString():SetTextColor(0.4, 0.4, 0.4)
    end

    -- Move Up button
    local upBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    upBtn:SetSize(28, 24)
    upBtn:SetPoint("RIGHT", downBtn, "LEFT", -2, 0)
    upBtn:SetText("▲")
    local canMoveUp = index > 1
    upBtn:SetEnabled(canMoveUp)
    upBtn:SetScript("OnClick", function()
        addon:MoveLocationUp(index)
        addon:RefreshOptionsLocations()
    end)
    if not canMoveUp then
        upBtn:GetFontString():SetTextColor(0.4, 0.4, 0.4)
    end

    -- Rename button
    local renameBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    renameBtn:SetSize(60, 24)
    renameBtn:SetPoint("RIGHT", upBtn, "LEFT", -8, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnClick", function()
        addon:ShowRenameDialog(index)
    end)

    -- Create Macro button - creates a macro for this teleport location
    local macroBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    macroBtn:SetSize(85, 24)
    macroBtn:SetPoint("RIGHT", renameBtn, "LEFT", -4, 0)
    macroBtn:SetText("Create Macro")
    macroBtn:SetScript("OnClick", function()
        -- Set up the secure button (hidden, for macro use)
        local secureBtn = addon:GetSecureTeleportButton(index)
        if location.neighborhoodGUID and location.houseGUID and location.plotID then
            secureBtn:SetTeleportAction(location.neighborhoodGUID, location.houseGUID, location.plotID)
        end

        -- Create the macro
        local macroName = "MHT: " .. location.name
        local macroBody = "/click " .. secureBtn:GetName()

        -- Use numbered icons (texture IDs for 1-9) or home icon for 10+
        local macroIcon
        if index >= 1 and index <= 9 then
            macroIcon = 6033345 + index  -- 6033346 (_1) to 6033354 (_9)
        else
            macroIcon = 7252953  -- ui_homestone_64
        end

        -- Check if macro already exists
        local existingIndex = GetMacroIndexByName(macroName)
        if existingIndex and existingIndex > 0 then
            -- Update existing macro
            EditMacro(existingIndex, macroName, macroIcon, macroBody)
            addon:Print("Updated macro: |cFFFFCC00" .. macroName .. "|r")
        else
            -- Check macro limits
            local numGlobal, numPerChar = GetNumMacros()
            if numGlobal < MAX_ACCOUNT_MACROS then
                -- Create new global macro
                local newIndex = CreateMacro(macroName, macroIcon, macroBody, false)
                if newIndex then
                    addon:Print("Created macro: |cFFFFCC00" .. macroName .. "|r")
                    addon:Print("Drag it from the Macro panel (|cFFFFCC00/macro|r) to your action bar.")
                else
                    addon:Print("|cFFFF4444Failed to create macro.|r")
                end
            else
                addon:Print("|cFFFF4444Macro limit reached!|r You have " .. numGlobal .. "/" .. MAX_ACCOUNT_MACROS .. " account macros.")
                addon:Print("Delete an unused macro or manually create: |cFFFFCC00" .. macroBody .. "|r")
            end
        end
    end)
    macroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Create Teleport Macro", 1, 1, 1)
        GameTooltip:AddLine("Creates a macro to teleport to " .. location.name .. ".", 0.8, 0.8, 0.8, true)
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

    -- Clear existing children
    for _, child in pairs({locationsScrollBox.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
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
end

-------------------------------------------------------------------------------
-- Create Options Frame
-------------------------------------------------------------------------------

local function CreateOptionsFrame()
    local frame = CreateFrame("Frame", "MHT_OptionsFrame", UIParent)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Multiple House Teleports")

    -- Version
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("|cFF888888v" .. (addon.version or "1.0.0") .. "|r")

    -- Description
    local desc = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Save multiple housing plot locations and teleport between them.")

    ---------------------------------------------------------------------------
    -- General Settings Section
    ---------------------------------------------------------------------------
    local generalHeader = CreateSectionHeader(frame, "General Settings", desc, -20)

    local showAddCheck = CreateCheckbox(
        frame,
        "Show 'Add Location' in Menu",
        "Show the 'Add Current Location' option in the dropdown menu when you're at a plot.",
        generalHeader, -8,
        function() return addon.db.options.showAddButton end,
        function(value) addon.db.options.showAddButton = value end
    )

    local confirmDeleteCheck = CreateCheckbox(
        frame,
        "Confirm Before Deleting",
        "Show a confirmation dialog before deleting a saved location.",
        showAddCheck, -4,
        function() return addon.db.options.confirmDelete end,
        function(value) addon.db.options.confirmDelete = value end
    )

    ---------------------------------------------------------------------------
    -- Minimap Section
    ---------------------------------------------------------------------------
    local minimapHeader = CreateSectionHeader(frame, "Minimap", confirmDeleteCheck, -20)

    local hideMinimapCheck = CreateCheckbox(
        frame,
        "Hide Minimap Icon",
        "Hide the minimap button. You can still use /mht commands.",
        minimapHeader, -8,
        function() return addon.db.minimap.hide end,
        function(value)
            addon.db.minimap.hide = value
            addon:ToggleMinimapIcon()
        end
    )

    ---------------------------------------------------------------------------
    -- Saved Locations Section
    ---------------------------------------------------------------------------
    local locationsHeader = CreateSectionHeader(frame, "Saved Locations", hideMinimapCheck, -20)

    -- Scroll frame for locations
    local scrollContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    scrollContainer:SetPoint("TOPLEFT", locationsHeader, "BOTTOMLEFT", 0, -12)
    scrollContainer:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
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

    -- Create Default Home Macro button
    local defaultMacroBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    defaultMacroBtn:SetSize(170, 28)
    defaultMacroBtn:SetPoint("TOPLEFT", scrollContainer, "BOTTOMLEFT", 0, -12)
    defaultMacroBtn:SetText("Create Home Macro")
    defaultMacroBtn:SetScript("OnClick", function(self)
        self:SetText("Loading...")
        self:Disable()

        addon:RequestPlayerHouseInfo(function(houseInfo)
            self:SetText("Create Home Macro")
            self:Enable()

            if not houseInfo then
                addon:Print("|cFFFF4444Could not get your home info. Do you own a house?|r")
                return
            end

            -- Get the secure button
            local btn = addon:GetDefaultHomeButton()

            -- Create the macro
            local macroName = "MHT: My Home"
            local macroBody = "/click " .. btn:GetName()
            local macroIcon = 7252953  -- ui_homestone_64

            -- Check if macro already exists
            local existingIndex = GetMacroIndexByName(macroName)
            if existingIndex and existingIndex > 0 then
                EditMacro(existingIndex, macroName, macroIcon, macroBody)
                addon:Print("Updated macro: |cFFFFCC00" .. macroName .. "|r")
            else
                local numGlobal, numPerChar = GetNumMacros()
                if numGlobal < MAX_ACCOUNT_MACROS then
                    local newIndex = CreateMacro(macroName, macroIcon, macroBody, false)
                    if newIndex then
                        addon:Print("Created macro: |cFFFFCC00" .. macroName .. "|r")
                        addon:Print("Drag it from the Macro panel (|cFFFFCC00/macro|r) to your action bar.")
                    else
                        addon:Print("|cFFFF4444Failed to create macro.|r")
                    end
                else
                    addon:Print("|cFFFF4444Macro limit reached!|r")
                    addon:Print("Manually create: |cFFFFCC00" .. macroBody .. "|r")
                end
            end
        end)
    end)
    defaultMacroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Create Home Macro", 1, 1, 1)
        GameTooltip:AddLine("Creates a macro to teleport to your own home.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    defaultMacroBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Add Location button
    local addLocationBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addLocationBtn:SetSize(160, 28)
    addLocationBtn:SetPoint("LEFT", defaultMacroBtn, "RIGHT", 8, 0)
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

    frame:SetScript("OnShow", function()
        addon:RefreshOptionsLocations()
        UpdateAddButtonState()
    end)

    ---------------------------------------------------------------------------
    -- Commands Section
    ---------------------------------------------------------------------------
    local commandsHeader = CreateSectionHeader(frame, "Commands", defaultMacroBtn, -20)

    local commandsText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commandsText:SetPoint("TOPLEFT", commandsHeader, "BOTTOMLEFT", 0, -8)
    commandsText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
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
