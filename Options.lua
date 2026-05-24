local ADDON_NAME, NS = ...

local E = unpack(ElvUI)
local UF = E:GetModule("UnitFrames")

local DISPEL_TYPE_VALUES = {
    Magic = "Magic",
    Curse = "Curse",
    Disease = "Disease",
    Poison = "Poison",
    Bleed = "Bleed",
}

local POINT_VALUES = {
    TOPLEFT = "TOPLEFT",
    TOP = "TOP",
    TOPRIGHT = "TOPRIGHT",
    LEFT = "LEFT",
    CENTER = "CENTER",
    RIGHT = "RIGHT",
    BOTTOMLEFT = "BOTTOMLEFT",
    BOTTOM = "BOTTOM",
    BOTTOMRIGHT = "BOTTOMRIGHT",
}

local HIGHLIGHT_VALUES = {
    none = "None",
    entire = "Entire",
    current = "Current",
    ["current+"] = "Current +",
    gradient = "Gradient",
    ["gradient-half"] = "Gradient Half",
}

local ICON_STYLE_VALUES = {
    none = "None",
    blizzard = "Blizzard",
    rhombus = "Rhombus",
}

local ORIENTATION_VALUES = {
    ["left-to-right"] = "Left to Right",
    ["right-to-left"] = "Right to Left",
    ["top-to-bottom"] = "Top to Bottom",
    ["bottom-to-top"] = "Bottom to Top",
}

local function Apply()
    NS:ApplySettings()
    if UF and UF.Update_PlayerFrame and _G.ElvUF_Player then
        UF:Update_PlayerFrame(_G.ElvUF_Player, E.db.unitframe.units.player)
    end
end

local function Get(info)
    return NS.db[info[#info]]
end

local function Set(info, value)
    NS.db[info[#info]] = value
    Apply()
end

local function GetFilter(_, key)
    return NS.db.filters[key]
end

local function SetFilter(_, key, value)
    NS.db.filters[key] = value
    Apply()
end

function NS.RegisterOptions()
    if not (E.Options and E.Options.args and E.Options.args.unitframe) then
        return false
    end

    local playerOptions = E.Options.args.unitframe.args
        and E.Options.args.unitframe.args.individualUnits
        and E.Options.args.unitframe.args.individualUnits.args
        and E.Options.args.unitframe.args.individualUnits.args.player
        and E.Options.args.unitframe.args.individualUnits.args.player.args

    if not playerOptions then
        return false
    end

    playerOptions.dispellableBorderIcon = {
        order = 75,
        type = "group",
        name = "Dispellable Border Icon",
        get = Get,
        set = Set,
        args = {
            enabled = {
                order = 1,
                type = "toggle",
                name = "Enable",
                width = "full",
            },
            testMode = {
                order = 2,
                type = "toggle",
                name = "Test Mode",
                desc = "Show a preview indicator on the player frame without requiring a debuff.",
                width = "full",
            },
            dispellableByMe = {
                order = 3,
                type = "toggle",
                name = "Only Dispellable by Me",
                desc = "Use Blizzard's player-dispellable aura filter before showing the indicator.",
                width = "full",
            },
            filters = {
                order = 10,
                type = "multiselect",
                name = "Dispel Types",
                values = DISPEL_TYPE_VALUES,
                get = GetFilter,
                set = SetFilter,
            },
            appearance = {
                order = 20,
                type = "group",
                name = "Appearance",
                inline = true,
                args = {
                    highlightType = {
                        order = 1,
                        type = "select",
                        name = "Highlight Type",
                        values = HIGHLIGHT_VALUES,
                    },
                    iconStyle = {
                        order = 2,
                        type = "select",
                        name = "Icon Style",
                        values = ICON_STYLE_VALUES,
                    },
                    orientation = {
                        order = 3,
                        type = "select",
                        name = "Icon Orientation",
                        values = ORIENTATION_VALUES,
                        disabled = function()
                            return NS.db.iconStyle == "none"
                        end,
                    },
                    iconSize = {
                        order = 4,
                        type = "range",
                        name = "Icon Size",
                        min = 6,
                        max = 40,
                        step = 1,
                        disabled = function()
                            return NS.db.iconStyle == "none"
                        end,
                    },
                },
            },
            position = {
                order = 30,
                type = "group",
                name = "Position",
                inline = true,
                args = {
                    point = {
                        order = 1,
                        type = "select",
                        name = "Point",
                        values = POINT_VALUES,
                    },
                    relativePoint = {
                        order = 2,
                        type = "select",
                        name = "Relative Point",
                        values = POINT_VALUES,
                    },
                    xOffset = {
                        order = 3,
                        type = "range",
                        name = "X-Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                    },
                    yOffset = {
                        order = 4,
                        type = "range",
                        name = "Y-Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                    },
                    frameLevel = {
                        order = 5,
                        type = "range",
                        name = "Frame Level",
                        min = 1,
                        max = 50,
                        step = 1,
                    },
                },
            },
        },
    }

    NS.optionsRegistered = true
    return true
end
