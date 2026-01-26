local ADDON_NAME, addon = ...

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

    return {
        neighborhoodGUID = houseInfo.neighborhoodGUID,
        houseGUID = houseInfo.houseGUID,
        plotID = houseInfo.plotID,
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

function addon:TeleportTo(index)
    local location = self.db.teleports[index]
    if not location then
        self:Print("Invalid location index: " .. tostring(index))
        return false
    end

    if not C_Housing or not C_Housing.TeleportHome then
        self:Print("Housing API not available")
        return false
    end

    -- Execute the teleport
    local success = pcall(function()
        C_Housing.TeleportHome(
            location.neighborhoodGUID,
            location.houseGUID,
            location.plotID
        )
    end)

    if success then
        self:Print("Teleporting to: " .. location.name)
    else
        self:Print("Failed to teleport to: " .. location.name)
    end

    return success
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
