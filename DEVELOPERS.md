# Developer Documentation

This document covers integrating with MultipleHouseTeleports from other addons.

## Global Reference

The addon is exposed globally as:

```lua
local MHT = _G.MultipleHouseTeleports
```

Check for availability before using:

```lua
if MultipleHouseTeleports then
    -- Safe to use the API
end
```

---

## Architecture Overview

### File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Addon setup, database, event system, slash commands |
| `Teleports.lua` | Location management, secure teleport buttons |
| `UI.lua` | Options panel, LibDataBroker integration |

### Secure Teleportation

Housing teleportation requires a `SecureActionButtonTemplate` with the `"teleporthome"` action type. These buttons cannot be created or modified during combat.

Each saved location gets a named secure button (`MHT_TeleportButton1`, `MHT_TeleportButton2`, etc.) that can be clicked via macro.

### SavedVariables

Data is stored in `MultipleHouseTeleportsDB`:

```lua
MultipleHouseTeleportsDB = {
    teleports = { ... },  -- Array of location objects
    minimap = {
        hide = true,      -- Minimap icon visibility
    },
    options = {
        confirmDelete = true,
    },
}
```

---

## Public API Reference

### Location Management

#### `MHT:GetLocations()`
Returns the array of saved locations.

```lua
local locations = MultipleHouseTeleports:GetLocations()
for i, loc in ipairs(locations) do
    print(i, loc.name)
end
```

#### `MHT:GetLocationCount()`
Returns the number of saved locations.

```lua
local count = MultipleHouseTeleports:GetLocationCount()
```

#### `MHT:AddCurrentLocation(name)`
Saves the current housing plot. Player must be inside a plot.

- `name` (string, optional): Display name. Auto-generated if nil.
- Returns: `true` on success, `false` on failure (prints error message).

```lua
local success = MultipleHouseTeleports:AddCurrentLocation("My Friend's House")
```

#### `MHT:RemoveLocation(index)`
Deletes a saved location and its associated macro (if any).

- `index` (number): 1-based index into the locations array.
- Returns: `true` on success, `false` on failure.

```lua
MultipleHouseTeleports:RemoveLocation(3)
```

#### `MHT:RenameLocation(index, newName)`
Renames a saved location and updates its macro (if any).

- `index` (number): 1-based index.
- `newName` (string): New display name.
- Returns: `true` on success, `false` on failure.

```lua
MultipleHouseTeleports:RenameLocation(1, "Guild Hall")
```

### Teleportation

#### `MHT:CanAddLocation()`
Checks if the player can save their current location.

- Returns: `success` (boolean), `reason` (string if false).

```lua
local canAdd, reason = MultipleHouseTeleports:CanAddLocation()
if not canAdd then
    print("Cannot add:", reason)
end
```

#### `MHT:GetTeleportMacro(index)`
Gets the macro command to teleport to a location.

- `index` (number): 1-based index.
- Returns: Macro string (e.g., `"/click MHT_TeleportButton1"`) or `nil`.

```lua
local macro = MultipleHouseTeleports:GetTeleportMacro(1)
-- Returns: "/click MHT_TeleportButton1"
```

### Secure Buttons

These functions return `SecureActionButtonTemplate` frames for UI integration.

#### `MHT:GetSecureTeleportButton(index)`
Gets or creates the secure button for a location.

- `index` (number): 1-based index.
- Returns: Button frame.

The button is named `MHT_TeleportButton{index}` and can be clicked via `/click`.

#### `MHT:GetDefaultHomeButton()`
Gets the secure button for teleporting to the player's own home.

- Returns: Button frame (named `MHT_DefaultHomeButton`).

### Reordering

#### `MHT:MoveLocationUp(index)` / `MHT:MoveLocationDown(index)`
Reorders locations in the list.

- Returns: `true` if moved, `false` if at boundary.

---

## Location Data Structure

Each location object contains:

```lua
{
    name = "Location Name",           -- Display name
    neighborhoodGUID = "string",      -- Neighborhood identifier
    houseGUID = "string",             -- House identifier
    plotID = number,                  -- Plot identifier
    neighborhoodName = "string",      -- Human-readable neighborhood name (may be nil)
    neighborhoodType = "Public",      -- "Public", "Guild", or "Charter" (may be nil)
    ownerName = "string",             -- Plot owner's name (may be nil)
    plotName = "string",              -- Plot's custom name (may be nil)
    addedAt = timestamp,              -- Unix timestamp when saved
}
```

The `neighborhoodGUID`, `houseGUID`, and `plotID` fields are required for teleportation. Other fields are metadata for display purposes.

---

## Integration Examples

### Reading Locations from Another Addon

```lua
local function ListMHTLocations()
    if not MultipleHouseTeleports then
        print("MHT not loaded")
        return
    end

    local locations = MultipleHouseTeleports:GetLocations()
    for i, loc in ipairs(locations) do
        local typeStr = loc.neighborhoodType or "Unknown"
        print(string.format("%d. [%s] %s", i, typeStr, loc.name))
    end
end
```

### Creating a Teleport Button Using /click

```lua
-- In a macro or secure button
/click MHT_TeleportButton1
```

Or programmatically (must call outside combat):

```lua
local function CreateTeleportMacro(index)
    if not MultipleHouseTeleports then return end

    local locations = MultipleHouseTeleports:GetLocations()
    local loc = locations[index]
    if not loc then return end

    local macroText = MultipleHouseTeleports:GetTeleportMacro(index)
    if macroText then
        CreateMacro("Teleport: " .. loc.name, "INV_MISC_QUESTIONMARK", macroText, nil)
    end
end
```

### Embedding a Teleport Button in Your UI

```lua
local function CreateEmbeddedTeleportButton(parent, locationIndex)
    if not MultipleHouseTeleports then return end

    -- Get the secure button
    local secureBtn = MultipleHouseTeleports:GetSecureTeleportButton(locationIndex)
    if not secureBtn then return end

    -- Ensure button is configured for this location
    local locations = MultipleHouseTeleports:GetLocations()
    local loc = locations[locationIndex]
    if loc then
        secureBtn:SetTeleportAction(loc.neighborhoodGUID, loc.houseGUID, loc.plotID)
    end

    -- Position in your UI (cannot be done in combat)
    if not InCombatLockdown() then
        secureBtn:SetParent(parent)
        secureBtn:ClearAllPoints()
        secureBtn:SetPoint("CENTER", parent, "CENTER")
        secureBtn:SetSize(100, 30)
        secureBtn:Show()
    end

    return secureBtn
end
```

### Adding a Location Programmatically

```lua
-- Player must be standing on a housing plot
local function SaveCurrentPlot(customName)
    if not MultipleHouseTeleports then return false end

    local canAdd, reason = MultipleHouseTeleports:CanAddLocation()
    if not canAdd then
        print("Cannot save location:", reason)
        return false
    end

    return MultipleHouseTeleports:AddCurrentLocation(customName)
end
```

---

## Stability Guarantees

### Stable Public API

These functions are considered stable and will maintain backwards compatibility:

- `GetLocations()`
- `GetLocationCount()`
- `AddCurrentLocation(name)`
- `RemoveLocation(index)`
- `RenameLocation(index, name)`
- `CanAddLocation()`
- `GetTeleportMacro(index)`
- `GetSecureTeleportButton(index)`
- `GetDefaultHomeButton()`

### Internal Details (May Change)

- Button frame names (`MHT_TeleportButton*`) may change
- Location object fields beyond the core teleport data (`neighborhoodGUID`, `houseGUID`, `plotID`, `name`)
- Database structure keys
- Internal event handling

### Version Checking

Check the addon version if you depend on specific features:

```lua
local version = MultipleHouseTeleports and MultipleHouseTeleports.version
if version then
    print("MHT version:", version)
end
```

---

## Events

MHT does not currently expose custom events. If you need to react to location changes, poll `GetLocations()` or request this feature.

---

## Support

For questions or feature requests, open an issue on the repository.
