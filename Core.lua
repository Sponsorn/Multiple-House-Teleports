local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- Addon Setup
-------------------------------------------------------------------------------

addon.name = ADDON_NAME
addon.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0.0"

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- Event handlers table
local eventHandlers = {}

-------------------------------------------------------------------------------
-- Database Defaults
-------------------------------------------------------------------------------

local DB_DEFAULTS = {
    teleports = {},
    minimap = {
        hide = true,                -- Hidden by default
    },
    options = {
        confirmDelete = true,       -- Confirm before deleting a location
    },
}

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

function addon:Print(msg)
    print("|cFF88AAFF[MHT]|r " .. tostring(msg))
end

local function safeCall(fn, ...)
    local success, err = pcall(fn, ...)
    if not success then
        addon:Print("Error: " .. tostring(err))
    end
    return success
end
addon.safeCall = safeCall

-------------------------------------------------------------------------------
-- Database Initialization
-------------------------------------------------------------------------------

local function InitDatabase()
    if not MultipleHouseTeleportsDB then
        MultipleHouseTeleportsDB = {}
    end

    -- Apply defaults
    for key, value in pairs(DB_DEFAULTS) do
        if MultipleHouseTeleportsDB[key] == nil then
            if type(value) == "table" then
                MultipleHouseTeleportsDB[key] = CopyTable(value)
            else
                MultipleHouseTeleportsDB[key] = value
            end
        end
    end

    addon.db = MultipleHouseTeleportsDB
end

-------------------------------------------------------------------------------
-- Event System
-------------------------------------------------------------------------------

function addon:RegisterEvent(event, handler)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], handler)
end

function addon:UnregisterEvent(event, handler)
    if eventHandlers[event] then
        for i, h in ipairs(eventHandlers[event]) do
            if h == handler then
                table.remove(eventHandlers[event], i)
                break
            end
        end
        if #eventHandlers[event] == 0 then
            eventHandlers[event] = nil
            eventFrame:UnregisterEvent(event)
        end
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            InitDatabase()
            addon:OnInitialize()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        addon:OnLogin()
        self:UnregisterEvent("PLAYER_LOGIN")
    else
        -- Dispatch to registered handlers
        local handlers = eventHandlers[event]
        if handlers then
            for _, handler in ipairs(handlers) do
                safeCall(handler, addon, event, ...)
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

function addon:OnInitialize()
    -- Initialize teleports system
    if self.InitTeleports then
        self:InitTeleports()
    end

    -- Initialize UI
    if self.InitUI then
        self:InitUI()
    end

    -- Initialize options
    if self.InitOptions then
        self:InitOptions()
    end
end

function addon:OnLogin()
    -- Register housing events
    self:RegisterEvent("HOUSE_PLOT_ENTERED", self.OnPlotEntered)
    self:RegisterEvent("CURRENT_HOUSE_INFO_RECIEVED", self.OnHouseInfoReceived)

    -- Set up default home button so the home macro works after reload
    self:RequestPlayerHouseInfo()
end

-------------------------------------------------------------------------------
-- Housing Event Handlers
-------------------------------------------------------------------------------

function addon:OnPlotEntered()
    -- Player entered a plot - we can now offer to save this location
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end
end

function addon:OnHouseInfoReceived()
    -- House info is now available
    if self.UpdateMenuState then
        self:UpdateMenuState()
    end
end

-------------------------------------------------------------------------------
-- Slash Commands
-------------------------------------------------------------------------------

SLASH_MULTIPLEHOUSETELEPORTS1 = "/mht"
SLASH_MULTIPLEHOUSETELEPORTS2 = "/multihousetele"

SlashCmdList["MULTIPLEHOUSETELEPORTS"] = function(msg)
    local args = {}
    for word in string.gmatch(msg, "%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" or cmd == "help" then
        Print("Commands:")
        Print("  /mht add [name] - Add current location")
        Print("  /mht list - List saved locations")
        Print("  /mht delete <number> - Delete a location")
        Print("  /mht teleport <number> - Teleport to a location")
        Print("  /mht options - Open options panel")

    elseif cmd == "add" then
        -- Get name from remaining args
        table.remove(args, 1)
        local name = table.concat(args, " ")
        if name == "" then
            name = nil  -- Will use default naming
        end
        addon:AddCurrentLocation(name)

    elseif cmd == "list" then
        addon:ListLocations()

    elseif cmd == "delete" or cmd == "remove" then
        local index = tonumber(args[2])
        if index then
            addon:RemoveLocation(index)
        else
            Print("Usage: /mht delete <number>")
        end

    elseif cmd == "teleport" or cmd == "tp" or cmd == "go" then
        local index = tonumber(args[2])
        if index then
            addon:TeleportTo(index)
        else
            Print("Usage: /mht teleport <number>")
        end

    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        if addon.OpenOptions then
            addon:OpenOptions()
        end

    else
        Print("Unknown command. Use /mht help for a list of commands.")
    end
end

-------------------------------------------------------------------------------
-- Global Reference (for other addons)
-------------------------------------------------------------------------------

_G.MultipleHouseTeleports = addon
