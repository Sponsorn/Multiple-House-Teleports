local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- Neighborhood Info Cache
-------------------------------------------------------------------------------

local cachedNeighborhoodInfo = nil

local neighborhoodInfoFrame = CreateFrame("Frame")
neighborhoodInfoFrame:RegisterEvent("NEIGHBORHOOD_INFO_UPDATED")
neighborhoodInfoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
neighborhoodInfoFrame:RegisterEvent("CURRENT_HOUSE_INFO_RECIEVED")
neighborhoodInfoFrame:RegisterEvent("CURRENT_HOUSE_INFO_UPDATED")
neighborhoodInfoFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "NEIGHBORHOOD_INFO_UPDATED" then
        cachedNeighborhoodInfo = ...
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Request neighborhood info when entering world (if in a neighborhood)
        if C_HousingNeighborhood and C_HousingNeighborhood.RequestNeighborhoodInfo then
            pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
        end
    elseif event == "CURRENT_HOUSE_INFO_RECIEVED" or event == "CURRENT_HOUSE_INFO_UPDATED" then
        -- Refresh saved GUIDs when entering any house (covers other players' houses)
        if C_Housing and C_Housing.GetCurrentHouseInfo then
            local info = C_Housing.GetCurrentHouseInfo()
            if info and info.neighborhoodGUID and info.houseGUID and info.plotID then
                addon:RefreshSavedGUIDs({ info })
            end
        end
    end
end)

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
        -- Clear previous action first to force engine re-initialization
        -- (setting type=teleporthome when it's already teleporthome is a no-op
        -- and the engine won't re-read the guid/plot attributes)
        self:SetAttribute("type", nil)
        self:SetAttribute("house-neighborhood-guid", nil)
        self:SetAttribute("house-guid", nil)
        self:SetAttribute("house-plot-id", nil)
        if neighborhoodGUID and houseGUID and plotID then
            self:SetAttribute("type", "teleporthome")
            self:SetAttribute("house-neighborhood-guid", neighborhoodGUID)
            self:SetAttribute("house-guid", houseGUID)
            self:SetAttribute("house-plot-id", plotID)
        end
    end
end

function TeleportButtonMixin:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" and self.pendingSetup then
        self:SetTeleportAction(self.neighborhoodGUID, self.houseGUID, self.plotID)
    end
end

-------------------------------------------------------------------------------
-- Teleport Cooldown Check (My Home only)
-------------------------------------------------------------------------------

function addon:CheckTeleportCooldown()
    if not C_Housing or not C_Housing.GetVisitCooldownInfo then
        return false
    end

    local cooldownInfo = C_Housing.GetVisitCooldownInfo()
    if cooldownInfo and cooldownInfo.isEnabled then
        local remaining = (cooldownInfo.startTime + cooldownInfo.duration) - GetTime()
        if remaining > 1 then
            local timeString = SecondsToTime(remaining, false, true)
            UIErrorsFrame:TryDisplayMessage(0, ITEM_COOLDOWN_TIME:format("|cFFFFFFFF" .. timeString .. "|r"), 0.53, 0.67, 1.0)
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Default Home State (declared early so OnTeleportError can access them)
-------------------------------------------------------------------------------

local defaultHomeButton
local defaultHomeInfo

-------------------------------------------------------------------------------
-- Stale GUID Auto-Retry
-------------------------------------------------------------------------------

local lastTeleportAttempt = nil  -- { index = N, time = GetTime(), isDefault = bool }
local lastTeleportIndex = nil    -- tracks which location for counter reset (survives error handler nil)
local lastTeleportTime = 0       -- GetTime() of last click, for stale counter reset
local teleportAttemptCount = 0   -- number of consecutive clicks (resets on location switch or timeout)
local RETRY_WINDOW = 1.5  -- seconds to wait for error after click
local COUNTER_RESET_TIMEOUT = 30 -- seconds before counter resets for same location

-- Error strings that indicate a stale houseGUID (resolved at runtime)
local STALE_GUID_ERRORS = {}
local function BuildStaleErrorSet()
    local keys = {
        "ERR_HOUSING_RESULT_PERMISSION_DENIED",
        "ERR_HOUSING_RESULT_HOUSE_NOT_FOUND",
        "ERR_HOUSING_RESULT_INVALID_HOUSE",
    }
    for _, key in ipairs(keys) do
        local text = _G[key]
        if text then
            STALE_GUID_ERRORS[text] = true
        end
    end
end

local function IncrementHouseGUID(guid)
    if not guid then return nil end
    local prefix, num = guid:match("^(.+-)(%d+)$")
    if prefix and num then
        local next = (tonumber(num) % 9) + 1  -- wrap: 1→2→...→9→1
        return prefix .. next, next
    end
    addon:Print("Warning: GUID format not recognized for cycling: " .. tostring(guid))
    return nil
end

local function OnTeleportError(locationIndex, isDefault)
    if isDefault then
        -- Increment default home button GUID
        if defaultHomeInfo and defaultHomeInfo.houseGUID and defaultHomeButton then
            local newGUID = IncrementHouseGUID(defaultHomeInfo.houseGUID)
            if newGUID then
                defaultHomeInfo.houseGUID = newGUID
                defaultHomeButton:SetTeleportAction(defaultHomeInfo.neighborhoodGUID, newGUID, defaultHomeInfo.plotID)
                addon:Print("Home GUID updated, try again (attempt " .. teleportAttemptCount .. "/9)")
            end
        end
        return
    end

    local location = addon.db and addon.db.teleports and addon.db.teleports[locationIndex]
    if not location or not location.houseGUID then return end

    local newGUID = IncrementHouseGUID(location.houseGUID)
    if not newGUID then return end

    location.houseGUID = newGUID

    -- Update the secure button
    local btn = secureTeleportButtons[locationIndex]
    if btn then
        btn:SetTeleportAction(location.neighborhoodGUID, newGUID, location.plotID)
    end

    addon:Print("Teleport failed for '" .. location.name .. "', try the macro again (attempt " .. teleportAttemptCount .. "/9)")
end

local staleGUIDFrame = CreateFrame("Frame")
staleGUIDFrame:RegisterEvent("UI_ERROR_MESSAGE")
staleGUIDFrame:RegisterEvent("PLAYER_LOGIN")
staleGUIDFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        BuildStaleErrorSet()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end

    -- UI_ERROR_MESSAGE: arg1 = errorType, arg2 = message
    if event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        if not lastTeleportAttempt then return end
        if (GetTime() - lastTeleportAttempt.time) > RETRY_WINDOW then
            lastTeleportAttempt = nil
            return
        end
        if message and STALE_GUID_ERRORS[message] then
            OnTeleportError(lastTeleportAttempt.index, lastTeleportAttempt.isDefault)
            lastTeleportAttempt = nil
        end
    end
end)

-------------------------------------------------------------------------------
-- Secure Teleport Button Creation
-------------------------------------------------------------------------------

local function CreateSecureTeleportButton(index)
    local btn = CreateFrame("Button", "MHT_TeleportButton" .. index, UIParent, "SecureActionButtonTemplate")
    Mixin(btn, TeleportButtonMixin)
    btn:SetSize(70, 24)
    btn:Hide()
    btn:SetScript("OnEvent", btn.OnEvent)
    btn.locationIndex = index

    -- PostClick to show feedback and track attempt for stale GUID retry
    btn:SetScript("PostClick", function(self, button, down)
        if down then return end  -- Only count on mouse up (action fires on up)
        if lastTeleportIndex ~= self.locationIndex or (GetTime() - lastTeleportTime) > COUNTER_RESET_TIMEOUT then
            teleportAttemptCount = 0
        end
        lastTeleportIndex = self.locationIndex
        lastTeleportTime = GetTime()
        teleportAttemptCount = teleportAttemptCount + 1
        local attemptInfo = { index = self.locationIndex, time = GetTime(), isDefault = false }
        lastTeleportAttempt = attemptInfo
        local location = addon.db and addon.db.teleports and addon.db.teleports[self.locationIndex]
        if location then
            if teleportAttemptCount > 1 then
                addon:Print("Teleporting to: " .. location.name .. " (attempt " .. teleportAttemptCount .. "/9)")
                C_Timer.After(RETRY_WINDOW + 0.5, function()
                    if lastTeleportAttempt == attemptInfo then
                        lastTeleportAttempt = nil
                        teleportAttemptCount = 0
                        addon:Print("Found ID for: " .. location.name .. ", teleport should now work during this session.")
                    end
                end)
            else
                addon:Print("Teleporting to: " .. location.name)
            end
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

local function CreateDefaultHomeButton()
    local btn = CreateFrame("Button", "MHT_DefaultHomeButton", UIParent, "SecureActionButtonTemplate")
    Mixin(btn, TeleportButtonMixin)
    btn:SetSize(1, 1)
    btn:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -1, -1)
    btn:Hide()
    btn:SetScript("OnEvent", btn.OnEvent)

    btn:SetScript("PostClick", function(self, button, down)
        if down then return end  -- Only count on mouse up (action fires on up)
        if lastTeleportIndex ~= 0 or (GetTime() - lastTeleportTime) > COUNTER_RESET_TIMEOUT then
            teleportAttemptCount = 0
        end
        lastTeleportIndex = 0
        lastTeleportTime = GetTime()
        teleportAttemptCount = teleportAttemptCount + 1
        local attemptInfo = { index = 0, time = GetTime(), isDefault = true }
        lastTeleportAttempt = attemptInfo
        if addon:CheckTeleportCooldown() then return end
        if teleportAttemptCount > 1 then
            addon:Print("Teleporting home... (attempt " .. teleportAttemptCount .. "/9)")
            C_Timer.After(RETRY_WINDOW + 0.5, function()
                if lastTeleportAttempt == attemptInfo then
                    lastTeleportAttempt = nil
                    teleportAttemptCount = 0
                    addon:Print("Found it!")
                end
            end)
        else
            addon:Print("Teleporting home...")
        end
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

local houseInfoFrame = CreateFrame("Frame")
local houseInfoCallback = nil

houseInfoFrame:SetScript("OnEvent", function(self, event, houseInfoList)
    self:UnregisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    local cb = houseInfoCallback
    houseInfoCallback = nil

    if houseInfoList and #houseInfoList > 0 then
        local houseInfo = houseInfoList[1]
        addon:SetupDefaultHomeButton(houseInfo)
        addon:RefreshSavedGUIDs(houseInfoList)
        if cb then cb(houseInfo) end
    else
        if cb then cb(nil) end
    end
end)

function addon:RequestPlayerHouseInfo(callback)
    -- Request the player's owned houses from the server
    if not C_Housing or not C_Housing.GetPlayerOwnedHouses then
        if callback then callback(nil) end
        return
    end

    houseInfoCallback = callback
    houseInfoFrame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
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

    -- Recreate secure buttons for all saved locations so macros work after reload
    for i, location in ipairs(self.db.teleports) do
        if location.neighborhoodGUID and location.houseGUID and location.plotID then
            local btn = self:GetSecureTeleportButton(i)
            btn:SetTeleportAction(location.neighborhoodGUID, location.houseGUID, location.plotID)
        end
    end
end

function addon:RefreshSavedGUIDs(houseInfoList)
    if not houseInfoList or not self.db or not self.db.teleports then return end

    -- Build lookup: "neighborhoodGUID:plotID" → fresh houseGUID
    local lookup = {}
    for _, info in ipairs(houseInfoList) do
        if info.neighborhoodGUID and info.houseGUID and info.plotID then
            lookup[info.neighborhoodGUID .. ":" .. info.plotID] = info.houseGUID
        end
    end

    -- Update any saved teleports with stale GUIDs
    for i, location in ipairs(self.db.teleports) do
        if location.neighborhoodGUID and location.plotID then
            local key = location.neighborhoodGUID .. ":" .. location.plotID
            local freshGUID = lookup[key]
            if freshGUID and freshGUID ~= location.houseGUID then
                location.houseGUID = freshGUID
                -- Refresh the corresponding secure button
                local btn = secureTeleportButtons[i]
                if btn then
                    btn:SetTeleportAction(location.neighborhoodGUID, freshGUID, location.plotID)
                end
            end
        end
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

    -- Try to get neighborhood name and type
    local neighborhoodName = nil
    local neighborhoodType = nil

    -- Type strings lookup
    local typeStrings = Enum and Enum.NeighborhoodOwnerType and {
        [Enum.NeighborhoodOwnerType.None] = HOUSING_NEIGHBORHOODTYPE_PUBLIC or "Public",
        [Enum.NeighborhoodOwnerType.Guild] = HOUSING_NEIGHBORHOODTYPE_GUILD or "Guild",
        [Enum.NeighborhoodOwnerType.Charter] = HOUSING_NEIGHBORHOODTYPE_CHARTER or "Charter",
    } or {}

    if houseInfo.neighborhoodGUID and C_HousingNeighborhood then
        if C_HousingNeighborhood.GetNeighborhoodName then
            neighborhoodName = C_HousingNeighborhood.GetNeighborhoodName(houseInfo.neighborhoodGUID)
        end

        -- Try cached neighborhood info first (from NEIGHBORHOOD_INFO_UPDATED event)
        if cachedNeighborhoodInfo and cachedNeighborhoodInfo.neighborhoodOwnerType then
            neighborhoodType = typeStrings[cachedNeighborhoodInfo.neighborhoodOwnerType]
        end

        -- Fallback: try cornerstone info (if at cornerstone)
        if not neighborhoodType and C_HousingNeighborhood.GetCornerstoneNeighborhoodInfo then
            local ok, info = pcall(C_HousingNeighborhood.GetCornerstoneNeighborhoodInfo)
            if ok and info and info.neighborhoodOwnerType then
                neighborhoodType = typeStrings[info.neighborhoodOwnerType]
            end
        end

        -- Request fresh neighborhood info for next time
        if C_HousingNeighborhood.RequestNeighborhoodInfo then
            pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
        end
    end

    return {
        neighborhoodGUID = houseInfo.neighborhoodGUID,
        houseGUID = houseInfo.houseGUID,
        plotID = houseInfo.plotID,
        neighborhoodName = neighborhoodName,
        neighborhoodType = neighborhoodType,
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

    -- Check for duplicates (plotID is stable within a neighborhood; houseGUID can change)
    for i, loc in ipairs(self.db.teleports) do
        if loc.neighborhoodGUID == info.neighborhoodGUID and
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
        neighborhoodType = info.neighborhoodType,
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
    if InCombatLockdown() then
        self:Print("Cannot delete locations during combat.")
        return false
    end

    if not self.db.teleports[index] then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    local location = self.db.teleports[index]
    local name = location.name

    -- Delete associated macro if it exists (uses naming format: MHT #: name)
    local macroName = "MHT " .. index .. ": " .. name
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex and macroIndex > 0 then
        DeleteMacro(macroIndex)
        self:Print("Deleted macro: " .. macroName)
    end

    table.remove(self.db.teleports, index)

    -- Renumber macros and rebuild secure buttons for all shifted locations
    for i = index, #self.db.teleports do
        local loc = self.db.teleports[i]

        -- Rename macro from old index (i+1) to new index (i)
        local oldMacroName = "MHT " .. (i + 1) .. ": " .. loc.name
        local mi = GetMacroIndexByName(oldMacroName)
        if mi and mi > 0 then
            local newMacroName = "MHT " .. i .. ": " .. loc.name
            local newBody = "/click MHT_TeleportButton" .. i
            local newIcon
            if i >= 1 and i <= 9 then
                newIcon = 6033345 + i
            else
                newIcon = 7252953
            end
            EditMacro(mi, newMacroName, newIcon, newBody)
        end

        -- Rebuild secure button to match new index
        local btn = self:GetSecureTeleportButton(i)
        if loc.neighborhoodGUID and loc.houseGUID and loc.plotID then
            btn:SetTeleportAction(loc.neighborhoodGUID, loc.houseGUID, loc.plotID)
        end
    end

    -- Clear the button that's now beyond the list
    local extraBtn = secureTeleportButtons[#self.db.teleports + 1]
    if extraBtn then
        extraBtn:SetTeleportAction(nil, nil, nil)
    end

    self:Print("Removed location: " .. name)

    -- Update UI
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end

    return true
end

function addon:RenameLocation(index, newName)
    if InCombatLockdown() then
        self:Print("Cannot rename locations during combat.")
        return false
    end

    if not self.db.teleports[index] then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    if not newName or newName == "" then
        self:Print("Invalid name")
        return false
    end

    local oldName = self.db.teleports[index].name

    -- Update macro name if it exists
    local oldMacroName = "MHT " .. index .. ": " .. oldName
    local newMacroName = "MHT " .. index .. ": " .. newName
    local macroIndex = GetMacroIndexByName(oldMacroName)
    if macroIndex and macroIndex > 0 then
        -- Get existing macro info to preserve icon and body
        local _, icon, body = GetMacroInfo(macroIndex)
        if body then
            EditMacro(macroIndex, newMacroName, icon, body)
            self:Print("Updated macro: " .. newMacroName)
        end
    end

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

