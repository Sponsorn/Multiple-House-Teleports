local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- Secure Teleport Button Pool
-------------------------------------------------------------------------------

local secureTeleportButtons = {}
local TeleportButtonMixin = {}

function TeleportButtonMixin:SetTeleportAction(neighborhoodGUID, houseGUID, plotID)
    self.neighborhoodGUID = neighborhoodGUID
    self.houseGUID = houseGUID
    self.plotID = plotID

    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.pendingSetup = true
    else
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self.pendingSetup = false
        self:SetAttribute("useOnKeyDown", false)
        self:RegisterForClicks("AnyDown", "AnyUp")
        if neighborhoodGUID and houseGUID and plotID then
            self:SetAttribute("type", "teleporthome")
            self:SetAttribute("house-neighborhood-guid", neighborhoodGUID)
            self:SetAttribute("house-guid", houseGUID)
            self:SetAttribute("house-plot-id", plotID)
        else
            self:SetAttribute("type", nil)
        end
    end
end

function TeleportButtonMixin:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" and self.pendingSetup then
        self:SetTeleportAction(self.neighborhoodGUID, self.houseGUID, self.plotID)
    end
end

local function CreateSecureTeleportButton(index)
    local btn = CreateFrame("Button", "MHT_TeleportButton" .. index, UIParent, "SecureActionButtonTemplate")
    Mixin(btn, TeleportButtonMixin)
    btn:SetSize(70, 24)
    btn:Hide()
    btn:SetScript("OnEvent", btn.OnEvent)
    btn.locationIndex = index

    -- PostClick to show feedback
    btn:SetScript("PostClick", function(self)
        local location = addon.db and addon.db.teleports and addon.db.teleports[self.locationIndex]
        if location then
            addon:Print("Teleporting to: " .. location.name)
        end
    end)

    -- Make it look like a button
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")
    btn:SetText("Teleport")

    -- Add visual styling to match UIPanelButtonTemplate
    local ntex = btn:CreateTexture()
    ntex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    ntex:SetTexCoord(0, 0.625, 0, 0.6875)
    ntex:SetAllPoints()
    btn:SetNormalTexture(ntex)

    local htex = btn:CreateTexture()
    htex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    htex:SetTexCoord(0, 0.625, 0, 0.6875)
    htex:SetAllPoints()
    btn:SetHighlightTexture(htex)

    local ptex = btn:CreateTexture()
    ptex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    ptex:SetTexCoord(0, 0.625, 0, 0.6875)
    ptex:SetAllPoints()
    btn:SetPushedTexture(ptex)

    return btn
end

function addon:GetSecureTeleportButton(index)
    if not secureTeleportButtons[index] then
        secureTeleportButtons[index] = CreateSecureTeleportButton(index)
    end
    return secureTeleportButtons[index]
end

-------------------------------------------------------------------------------
-- Default Home Button (index 0)
-------------------------------------------------------------------------------

local defaultHomeButton
local defaultHomeInfo

local function CreateDefaultHomeButton()
    local btn = CreateFrame("Button", "MHT_DefaultHomeButton", UIParent, "SecureActionButtonTemplate")
    Mixin(btn, TeleportButtonMixin)
    btn:SetSize(1, 1)
    btn:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -1, -1)
    btn:Hide()
    btn:SetScript("OnEvent", btn.OnEvent)

    btn:SetScript("PostClick", function(self)
        addon:Print("Teleporting to your home...")
    end)

    return btn
end

function addon:GetDefaultHomeButton()
    if not defaultHomeButton then
        defaultHomeButton = CreateDefaultHomeButton()
    end
    return defaultHomeButton
end

function addon:SetupDefaultHomeButton(houseInfo)
    local btn = self:GetDefaultHomeButton()
    if houseInfo and houseInfo.neighborhoodGUID and houseInfo.houseGUID and houseInfo.plotID then
        defaultHomeInfo = houseInfo
        btn:SetTeleportAction(houseInfo.neighborhoodGUID, houseInfo.houseGUID, houseInfo.plotID)
        return true
    end
    return false
end

function addon:RequestPlayerHouseInfo(callback)
    -- Request the player's owned houses from the server
    if not C_Housing or not C_Housing.GetPlayerOwnedHouses then
        if callback then callback(nil) end
        return
    end

    -- Register for the response event
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    frame:SetScript("OnEvent", function(self, event, houseInfoList)
        self:UnregisterEvent("PLAYER_HOUSE_LIST_UPDATED")
        self:SetScript("OnEvent", nil)

        if houseInfoList and #houseInfoList > 0 then
            -- Use the first house (primary home)
            local houseInfo = houseInfoList[1]
            addon:SetupDefaultHomeButton(houseInfo)
            if callback then callback(houseInfo) end
        else
            if callback then callback(nil) end
        end
    end)

    -- Request the house list
    C_Housing.GetPlayerOwnedHouses()
end

function addon:GetDefaultHomeInfo()
    return defaultHomeInfo
end

function addon:SetupSecureTeleportButton(index, location, parentButton)
    local btn = self:GetSecureTeleportButton(index)

    if location and location.neighborhoodGUID and location.houseGUID and location.plotID then
        btn:SetTeleportAction(location.neighborhoodGUID, location.houseGUID, location.plotID)

        if parentButton then
            btn:SetParent(parentButton:GetParent())
            btn:ClearAllPoints()
            btn:SetAllPoints(parentButton)
            btn:SetFrameLevel(parentButton:GetFrameLevel() + 10)
            btn:Show()
            -- Hide the original button's text since secure button shows its own
            parentButton:SetAlpha(0)
        end
    else
        btn:Hide()
        if parentButton then
            parentButton:SetAlpha(1)
        end
    end

    return btn
end

function addon:HideAllSecureTeleportButtons()
    for _, btn in pairs(secureTeleportButtons) do
        btn:Hide()
    end
end

-------------------------------------------------------------------------------
-- Teleport Data Management
-------------------------------------------------------------------------------

function addon:InitTeleports()
    -- Ensure teleports table exists
    if not self.db.teleports then
        self.db.teleports = {}
    end
end

-------------------------------------------------------------------------------
-- Location Detection
-------------------------------------------------------------------------------

function addon:CanAddLocation()
    -- Check if player is at a valid plot where we can capture location
    if not C_Housing then
        return false, "Housing API not available"
    end

    if not C_Housing.IsInsidePlot or not C_Housing.IsInsidePlot() then
        return false, "You must be inside a plot to add a location"
    end

    return true
end

function addon:GetCurrentLocationInfo()
    -- Get the current house/plot info
    if not C_Housing or not C_Housing.GetCurrentHouseInfo then
        return nil
    end

    local houseInfo = C_Housing.GetCurrentHouseInfo()
    if not houseInfo then
        return nil
    end

    -- Try to get neighborhood name
    local neighborhoodName = nil
    if houseInfo.neighborhoodGUID and C_HousingNeighborhood and C_HousingNeighborhood.GetNeighborhoodName then
        neighborhoodName = C_HousingNeighborhood.GetNeighborhoodName(houseInfo.neighborhoodGUID)
    end

    return {
        neighborhoodGUID = houseInfo.neighborhoodGUID,
        houseGUID = houseInfo.houseGUID,
        plotID = houseInfo.plotID,
        neighborhoodName = neighborhoodName,
        -- Try to get a reasonable default name
        ownerName = houseInfo.ownerName,
        plotName = houseInfo.plotName,
    }
end

-------------------------------------------------------------------------------
-- Location Management
-------------------------------------------------------------------------------

function addon:AddCurrentLocation(name)
    local canAdd, reason = self:CanAddLocation()
    if not canAdd then
        self:Print(reason)
        return false
    end

    local info = self:GetCurrentLocationInfo()
    if not info then
        self:Print("Could not get current location info")
        return false
    end

    -- Generate default name if not provided
    if not name or name == "" then
        if info.plotName and info.plotName ~= "" then
            name = info.plotName
        elseif info.ownerName and info.ownerName ~= "" then
            name = info.ownerName .. "'s Plot"
        else
            name = "Location " .. (#self.db.teleports + 1)
        end
    end

    -- Check for duplicates
    for i, loc in ipairs(self.db.teleports) do
        if loc.neighborhoodGUID == info.neighborhoodGUID and
           loc.houseGUID == info.houseGUID and
           loc.plotID == info.plotID then
            self:Print("This location is already saved as: " .. loc.name)
            return false
        end
    end

    -- Add the new location
    local newLocation = {
        name = name,
        neighborhoodGUID = info.neighborhoodGUID,
        houseGUID = info.houseGUID,
        plotID = info.plotID,
        neighborhoodName = info.neighborhoodName,
        addedAt = time(),
    }

    table.insert(self.db.teleports, newLocation)
    self:Print("Added location: " .. name)

    -- Update UI
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end

function addon:RemoveLocation(index)
    if not self.db.teleports[index] then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    local location = self.db.teleports[index]
    local name = location.name

    -- Delete associated macro if it exists (uses new naming format)
    local macroName = "MHT " .. index .. ":"
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex and macroIndex > 0 then
        DeleteMacro(macroIndex)
        self:Print("Deleted macro: " .. macroName)
    end

    table.remove(self.db.teleports, index)
    self:Print("Removed location: " .. name)

    -- Update UI
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end

function addon:RenameLocation(index, newName)
    if not self.db.teleports[index] then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    if not newName or newName == "" then
        self:Print("Invalid name")
        return false
    end

    local oldName = self.db.teleports[index].name
    self.db.teleports[index].name = newName
    self:Print("Renamed '" .. oldName .. "' to '" .. newName .. "'")

    -- Update UI
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end

function addon:GetLocations()
    return self.db.teleports or {}
end

function addon:GetLocationCount()
    return #(self.db.teleports or {})
end

function addon:ListLocations()
    local locations = self:GetLocations()
    if #locations == 0 then
        self:Print("No saved locations. Go to a plot and use /mht add to save it.")
        return
    end

    self:Print("Saved locations:")
    for i, loc in ipairs(locations) do
        self:Print("  " .. i .. ". " .. loc.name)
    end
end

-------------------------------------------------------------------------------
-- Teleportation
-------------------------------------------------------------------------------

-- Get the macro text to teleport to a location
function addon:GetTeleportMacro(index)
    local btn = self:GetSecureTeleportButton(index)
    if btn then
        return "/click " .. btn:GetName()
    end
    return nil
end

-- Called from dropdown - can't use secure button, so show message
function addon:TeleportTo(index)
    local location = self.db.teleports[index]
    if not location then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    -- Set up the secure button for this location
    local btn = self:GetSecureTeleportButton(index)
    if location.neighborhoodGUID and location.houseGUID and location.plotID then
        btn:SetTeleportAction(location.neighborhoodGUID, location.houseGUID, location.plotID)
    end

    -- Show message about how to teleport
    self:Print("To teleport to '" .. location.name .. "', use the Teleport button in Options,")
    self:Print("or create a macro: |cFFFFCC00/click " .. btn:GetName() .. "|r")

    return false
end

-- Direct teleport via secure button click (called from PostClick if needed)
function addon:OnTeleportClicked(index)
    local location = self.db.teleports[index]
    if location then
        self:Print("Teleporting to: " .. location.name)
    end
end

-------------------------------------------------------------------------------
-- Reordering
-------------------------------------------------------------------------------

function addon:MoveLocationUp(index)
    if index <= 1 or index > #self.db.teleports then
        return false
    end

    local temp = self.db.teleports[index]
    self.db.teleports[index] = self.db.teleports[index - 1]
    self.db.teleports[index - 1] = temp

    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end

function addon:MoveLocationDown(index)
    if index < 1 or index >= #self.db.teleports then
        return false
    end

    local temp = self.db.teleports[index]
    self.db.teleports[index] = self.db.teleports[index + 1]
    self.db.teleports[index + 1] = temp

    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end
