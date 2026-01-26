local ADDON_NAME, addon = ...

-------------------------------------------------------------------------------
-- Options Panel (AceConfig)
-------------------------------------------------------------------------------

local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)

local function GetOptions()
    local options = {
        type = "group",
        name = "Multiple House Teleports",
        args = {
            generalHeader = {
                order = 1,
                type = "header",
                name = "General Settings",
            },
            showAddButton = {
                order = 2,
                type = "toggle",
                name = "Show 'Add Location' in Menu",
                desc = "Show the 'Add Current Location' option in the dropdown menu when you're at a plot.",
                width = "full",
                get = function() return addon.db.options.showAddButton end,
                set = function(_, value) addon.db.options.showAddButton = value end,
            },
            confirmDelete = {
                order = 3,
                type = "toggle",
                name = "Confirm Before Deleting",
                desc = "Show a confirmation dialog before deleting a saved location.",
                width = "full",
                get = function() return addon.db.options.confirmDelete end,
                set = function(_, value) addon.db.options.confirmDelete = value end,
            },
            minimapHeader = {
                order = 10,
                type = "header",
                name = "Minimap",
            },
            hideMinimapIcon = {
                order = 11,
                type = "toggle",
                name = "Hide Minimap Icon",
                desc = "Hide the minimap button. You can still use /mht commands.",
                width = "full",
                get = function() return addon.db.minimap.hide end,
                set = function(_, value)
                    addon.db.minimap.hide = value
                    addon:ToggleMinimapIcon()
                end,
            },
            locationsHeader = {
                order = 20,
                type = "header",
                name = "Saved Locations",
            },
            locationsList = {
                order = 21,
                type = "description",
                name = function()
                    local locations = addon:GetLocations()
                    if #locations == 0 then
                        return "|cFF888888No saved locations.|r\n\nGo to a housing plot and click 'Add Current Location' in the menu, or use |cFFFFFF00/mht add [name]|r"
                    end

                    local lines = {}
                    for i, loc in ipairs(locations) do
                        table.insert(lines, string.format("|cFFFFFFFF%d.|r %s", i, loc.name))
                    end
                    return table.concat(lines, "\n")
                end,
                fontSize = "medium",
                width = "full",
            },
            locationActions = {
                order = 22,
                type = "group",
                name = "",
                inline = true,
                args = {},
            },
        },
    }

    -- Build location action buttons dynamically
    local locations = addon:GetLocations()
    for i, loc in ipairs(locations) do
        options.args.locationActions.args["loc" .. i] = {
            order = i,
            type = "group",
            name = loc.name,
            inline = true,
            args = {
                teleport = {
                    order = 1,
                    type = "execute",
                    name = "Teleport",
                    width = 0.6,
                    func = function()
                        addon:TeleportTo(i)
                    end,
                },
                rename = {
                    order = 2,
                    type = "execute",
                    name = "Rename",
                    width = 0.6,
                    func = function()
                        addon:ShowRenameDialog(i)
                    end,
                },
                moveUp = {
                    order = 3,
                    type = "execute",
                    name = "↑",
                    width = 0.3,
                    disabled = i == 1,
                    func = function()
                        addon:MoveLocationUp(i)
                        -- Refresh options panel
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
                moveDown = {
                    order = 4,
                    type = "execute",
                    name = "↓",
                    width = 0.3,
                    disabled = i == #locations,
                    func = function()
                        addon:MoveLocationDown(i)
                        -- Refresh options panel
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
                delete = {
                    order = 5,
                    type = "execute",
                    name = "Delete",
                    width = 0.6,
                    confirm = addon.db.options.confirmDelete,
                    confirmText = "Delete '" .. loc.name .. "'?",
                    func = function()
                        addon:RemoveLocation(i)
                        -- Refresh options panel
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
            },
        }
    end

    -- Add location button at the end
    options.args.addLocation = {
        order = 30,
        type = "execute",
        name = "Add Current Location",
        desc = "Save your current plot location. You must be inside a housing plot.",
        disabled = function()
            return not addon:CanAddLocation()
        end,
        func = function()
            addon:ShowAddLocationDialog()
        end,
    }

    options.args.commandsHeader = {
        order = 100,
        type = "header",
        name = "Commands",
    }
    options.args.commandsHelp = {
        order = 101,
        type = "description",
        name = [[
|cFFFFFF00/mht|r - Show commands
|cFFFFFF00/mht add [name]|r - Add current location
|cFFFFFF00/mht list|r - List saved locations
|cFFFFFF00/mht teleport <#>|r - Teleport to location
|cFFFFFF00/mht delete <#>|r - Delete a location
|cFFFFFF00/mht options|r - Open this panel
]],
        fontSize = "medium",
        width = "full",
    }

    return options
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function addon:InitOptions()
    if not AceConfig or not AceConfigDialog then
        self:Print("Warning: AceConfig libraries not found")
        return
    end

    AceConfig:RegisterOptionsTable(ADDON_NAME, GetOptions)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Multiple House Teleports")
end

function addon:OpenOptions()
    if AceConfigDialog then
        -- Refresh options before opening
        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
        AceConfigDialog:Open(ADDON_NAME)
    else
        -- Fallback to Blizzard options
        Settings.OpenToCategory("Multiple House Teleports")
    end
end
