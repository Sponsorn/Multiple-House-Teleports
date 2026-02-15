local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- UI Components
-------------------------------------------------------------------------------

local dropdownMenu
local minimapIcon

-------------------------------------------------------------------------------
-- Dropdown Menu
-------------------------------------------------------------------------------

local function CreateDropdownMenu()
    local menu = CreateFrame("Frame", "MultipleHouseTeleportsMenu", UIParent, "UIDropDownMenuTemplate")
    return menu
end

local function InitializeDropdownMenu(self, level, menuList)
    level = level or 1

    if level == 1 then
        -- Header
        local title = UIDropDownMenu_CreateInfo()
        title.text = "House Teleports"
        title.isTitle = true
        title.notCheckable = true
        UIDropDownMenu_AddButton(title, level)

        -- List all saved locations
        local locations = addon:GetLocations()
        if #locations == 0 then
            local empty = UIDropDownMenu_CreateInfo()
            empty.text = "No saved locations"
            empty.disabled = true
            empty.notCheckable = true
            UIDropDownMenu_AddButton(empty, level)
        else
            for i, loc in ipairs(locations) do
                local info = UIDropDownMenu_CreateInfo()
                -- Show neighborhood name if available
                if loc.neighborhoodName and loc.neighborhoodName ~= "" then
                    info.text = loc.name .. " |cFF888888(" .. loc.neighborhoodName .. ")|r"
                else
                    info.text = loc.name
                end
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = { type = "location", index = i, location = loc }
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- Separator
        local sep = UIDropDownMenu_CreateInfo()
        sep.text = ""
        sep.isTitle = true
        sep.notCheckable = true
        sep.disabled = true
        UIDropDownMenu_AddButton(sep, level)

        -- Add Current Location (only if at a plot)
        local canAdd = addon:CanAddLocation()
        local addInfo = UIDropDownMenu_CreateInfo()
        addInfo.text = canAdd and "|cFF00FF00+ Add Current Location|r" or "|cFF888888+ Add Current Location|r"
        addInfo.notCheckable = true
        addInfo.disabled = not canAdd
        addInfo.func = function()
            addon:ShowAddLocationDialog()
        end
        UIDropDownMenu_AddButton(addInfo, level)

        -- Options
        local optInfo = UIDropDownMenu_CreateInfo()
        optInfo.text = "Options"
        optInfo.notCheckable = true
        optInfo.func = function()
            addon:OpenOptions()
        end
        UIDropDownMenu_AddButton(optInfo, level)

    elseif level == 2 and menuList then
        -- Submenu for location actions
        if menuList.type == "location" then
            local index = menuList.index

            -- Teleport (show macro info)
            local teleportInfo = UIDropDownMenu_CreateInfo()
            teleportInfo.text = "Get Teleport Macro"
            teleportInfo.notCheckable = true
            teleportInfo.func = function()
                -- Set up the secure button
                local btn = addon:GetSecureTeleportButton(index)
                local loc = addon.db.teleports[index]
                if loc and loc.neighborhoodGUID and loc.houseGUID and loc.plotID then
                    btn:SetTeleportAction(loc.neighborhoodGUID, loc.houseGUID, loc.plotID)
                end
                -- Show macro info
                addon:Print("Macro for '" .. (loc and loc.name or "location") .. "':")
                addon:Print("|cFFFFCC00/click " .. btn:GetName() .. "|r")
                addon:Print("Or use the Teleport button in Options (|cFFFFCC00/mht options|r)")
            end
            UIDropDownMenu_AddButton(teleportInfo, level)

            -- Rename
            local renameInfo = UIDropDownMenu_CreateInfo()
            renameInfo.text = "Rename"
            renameInfo.notCheckable = true
            renameInfo.func = function()
                addon:ShowRenameDialog(index)
            end
            UIDropDownMenu_AddButton(renameInfo, level)

            -- Delete
            local deleteInfo = UIDropDownMenu_CreateInfo()
            deleteInfo.text = "|cFFFF4444Delete|r"
            deleteInfo.notCheckable = true
            deleteInfo.func = function()
                if addon.db.options.confirmDelete then
                    addon:ShowDeleteConfirmDialog(index)
                else
                    addon:RemoveLocation(index)
                end
            end
            UIDropDownMenu_AddButton(deleteInfo, level)
        end
    end
end

local function ShowDropdownMenu(anchorFrame)
    if not dropdownMenu then
        dropdownMenu = CreateDropdownMenu()
    end

    UIDropDownMenu_Initialize(dropdownMenu, InitializeDropdownMenu, "MENU")

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    ToggleDropDownMenu(1, nil, dropdownMenu, "UIParent", x / scale, y / scale)
end
addon.ShowDropdownMenu = ShowDropdownMenu

-------------------------------------------------------------------------------
-- Dialogs
-------------------------------------------------------------------------------

-- Add Location Dialog
StaticPopupDialogs["MHT_ADD_LOCATION"] = {
    text = "Enter a name for this location:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self)
        local name = self.EditBox:GetText()
        addon:AddCurrentLocation(name)
        if addon.RefreshOptionsLocations then
            addon:RefreshOptionsLocations()
        end
    end,
    OnShow = function(self)
        -- Try to pre-fill with plot info
        local info = addon:GetCurrentLocationInfo()
        if info then
            local defaultName = info.plotName or info.ownerName or ""
            self.EditBox:SetText(defaultName)
            self.EditBox:HighlightText()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        addon:AddCurrentLocation(name)
        if addon.RefreshOptionsLocations then
            addon:RefreshOptionsLocations()
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function addon:ShowAddLocationDialog()
    StaticPopup_Show("MHT_ADD_LOCATION")
end

-- Rename Location Dialog
StaticPopupDialogs["MHT_RENAME_LOCATION"] = {
    text = "Enter a new name:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self)
        local data = self.data
        local name = self.EditBox:GetText()
        addon:RenameLocation(data.index, name)
        if addon.RefreshOptionsLocations then
            addon:RefreshOptionsLocations()
        end
    end,
    OnShow = function(self)
        local data = self.data
        self.EditBox:SetText(data and data.currentName or "")
        self.EditBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local data = parent.data
        local name = self:GetText()
        addon:RenameLocation(data.index, name)
        if addon.RefreshOptionsLocations then
            addon:RefreshOptionsLocations()
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function addon:ShowRenameDialog(index)
    local location = addon.db.teleports[index]
    if not location then return end

    local data = { index = index, currentName = location.name }
    StaticPopup_Show("MHT_RENAME_LOCATION", nil, nil, data)
end

-- Delete Confirmation Dialog
StaticPopupDialogs["MHT_DELETE_CONFIRM"] = {
    text = "Delete location '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        local data = self.data
        addon:RemoveLocation(data.index)
        if addon.RefreshOptionsLocations then
            addon:RefreshOptionsLocations()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function addon:ShowDeleteConfirmDialog(index)
    local location = addon.db.teleports[index]
    if not location then return end

    local data = { index = index }
    StaticPopup_Show("MHT_DELETE_CONFIRM", location.name, nil, data)
end

-------------------------------------------------------------------------------
-- Minimap Icon (LibDBIcon)
-------------------------------------------------------------------------------

local function CreateMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)

    if not LDB or not LDBIcon then
        addon:Print("Warning: LibDataBroker or LibDBIcon not found")
        return
    end

    local dataObject = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = "Interface\\Icons\\Spell_Shadow_Teleport",
        label = "House Teleports",
        OnClick = function(self, button)
            if button == "LeftButton" then
                addon:OpenOptions()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Multiple House Teleports")
            tooltip:AddLine("|cFFFFFFFFLeft-click:|r Open options", 1, 1, 1)

            local count = addon:GetLocationCount()
            if count > 0 then
                tooltip:AddLine(" ")
                tooltip:AddLine("|cFF88AAFF" .. count .. " saved location(s)|r", 1, 1, 1)
            end
        end,
    })

    LDBIcon:Register(ADDON_NAME, dataObject, addon.db.minimap)
    minimapIcon = LDBIcon
end

-------------------------------------------------------------------------------
-- UI State Updates
-------------------------------------------------------------------------------

function addon:UpdateMenuState()
    -- Refresh dropdown if it's open
    if dropdownMenu and DropDownList1:IsShown() then
        CloseDropDownMenus()
    end
end

function addon:ToggleMinimapIcon()
    if not minimapIcon then return end

    if addon.db.minimap.hide then
        minimapIcon:Hide(ADDON_NAME)
    else
        minimapIcon:Show(ADDON_NAME)
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function addon:InitUI()
    CreateMinimapIcon()
end
