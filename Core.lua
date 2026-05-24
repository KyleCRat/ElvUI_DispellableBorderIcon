local ADDON_NAME, NS = ...

local E = unpack(ElvUI)
local UF = E:GetModule("UnitFrames")

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_CurveUtil = C_CurveUtil
local CreateColor = CreateColor
local Enum = Enum
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local UnitClass = UnitClass
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local print = print
local strtrim = strtrim
local tostring = tostring
local type = type
local wipe = wipe

local GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex
local GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

local ADDON_TITLE = "ElvUI Dispellable Border Icon"
local ADDON_MEDIA = "Interface\\AddOns\\ElvUI_DispellableBorderIcon\\Media\\"
local DISPEL_DEBUFF_TEXTURE = ADDON_MEDIA .. "Debuffs\\"
local DISPEL_GRADIENT_TEXTURE = ADDON_MEDIA .. "gradient"

local DISPEL_TYPES = {
    { name = "Magic", idx = 1, nextIdx = 2, color = { r = 0.20, g = 0.60, b = 1.00 } },
    { name = "Curse", idx = 2, nextIdx = 3, color = { r = 0.60, g = 0.00, b = 1.00 } },
    { name = "Disease", idx = 3, nextIdx = 4, color = { r = 0.60, g = 0.40, b = 0.00 } },
    { name = "Poison", idx = 4, nextIdx = 5, color = { r = 0.00, g = 0.60, b = 0.00 } },
    { name = "Bleed", idx = 11, nextIdx = 12, color = { r = 1.00, g = 0.20, b = 0.60 } },
}

local DISPEL_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

NS.defaults = {
    enabled = true,
    testMode = false,
    highlightType = "gradient-half",
    iconStyle = "blizzard",
    orientation = "right-to-left",
    iconSize = 12,
    point = "BOTTOMRIGHT",
    relativePoint = "BOTTOMRIGHT",
    xOffset = 0,
    yOffset = 4,
    frameLevel = 15,
    dispelModes = {
        Magic = "player",
        Curse = "player",
        Disease = "player",
        Poison = "player",
        Bleed = "player",
    },
}

local eventFrame = CreateFrame("Frame")
local updateQueued = false
local initialized = false
local pluginRegistered = false
local playerClass

local function Print(message)
    print(("|cff1784d1%s|r %s"):format(ADDON_TITLE, tostring(message)))
end

NS.Print = Print

local function CopyDefaults(defaults, db)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then
                db[key] = {}
            end
            CopyDefaults(value, db[key])
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

local function IsValueNonSecret(value)
    if E and E.NotSecretValue then
        return E:NotSecretValue(value)
    end

    if issecretvalue then
        return not issecretvalue(value)
    end

    return true
end

local function GetDispelMode(dispelType)
    return NS.db.dispelModes[dispelType]
end

local function IsDispelTypeEnabled(dispelType)
    return GetDispelMode(dispelType) ~= "disabled"
end

local function IsSecretDispelTypeEnabled(dispelType, includePlayerModes)
    return IsDispelTypeEnabled(dispelType)
        and (includePlayerModes or GetDispelMode(dispelType) == "always")
end

local function HasVisibleSecretDispelType(includePlayerModes)
    for _, dispelType in ipairs(DISPEL_ORDER) do
        if IsSecretDispelTypeEnabled(dispelType, includePlayerModes) then
            return true
        end
    end

    return false
end

local function GetPlayerFrame()
    return _G.ElvUF_Player or UF.player
end

local function GetDisplay(frame)
    if not frame then return end

    local display = frame.ElvDBI_Dispels
    if display then
        return display
    end

    local parent = frame.RaisedElementParent or frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:Hide()
    holder:SetFrameLevel((frame:GetFrameLevel() or 1) + NS.db.frameLevel)
    holder:EnableMouse(false)

    local highlightParent = frame.Health or frame
    local highlight = highlightParent:CreateTexture(nil, "ARTWORK", nil, 0)
    highlight:Hide()
    highlight:SetBlendMode("BLEND")

    display = {
        frame = frame,
        holder = holder,
        highlight = highlight,
        icons = {},
    }

    for i = 1, 5 do
        local icon = holder:CreateTexture(nil, "ARTWORK", nil, 6 - i)
        icon:Hide()
        display.icons[i] = icon
    end

    frame.ElvDBI_Dispels = display
    return display
end

local function GetTypeColor(dispelType)
    local color = E.db and E.db.unitframe and E.db.unitframe.colors
        and E.db.unitframe.colors.debuffHighlight
        and E.db.unitframe.colors.debuffHighlight[dispelType]

    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end

    for _, info in ipairs(DISPEL_TYPES) do
        if info.name == dispelType then
            return info.color.r, info.color.g, info.color.b
        end
    end

    return 1, 1, 1
end

local function HideDisplay(display)
    if not display then return end

    display.holder:Hide()
    display.highlight:Hide()

    for i = 1, 5 do
        local icon = display.icons[i]
        icon:Hide()
        icon:SetAlpha(1)
        icon:SetVertexColor(1, 1, 1, 1)
    end
end

local function SetIcon(display, index, dispelType)
    local icon = display.icons[index]
    if not icon then return end

    local db = NS.db
    icon:SetAlpha(1)

    if db.iconStyle == "rhombus" then
        icon:SetTexture(DISPEL_DEBUFF_TEXTURE .. "Rhombus")
        icon:SetVertexColor(GetTypeColor(dispelType))
    else
        icon:SetTexture(DISPEL_DEBUFF_TEXTURE .. dispelType)
        icon:SetVertexColor(1, 1, 1, 1)
    end

    icon:Show()
    return icon
end

local function LayoutIcons(display, iconsShown, stacked)
    local db = NS.db
    local size = db.iconSize or NS.defaults.iconSize
    local point, x, y, orientation

    if db.orientation == "left-to-right" then
        point, x, y, orientation = "TOPLEFT", size / 2, 0, "horizontal"
    elseif db.orientation == "right-to-left" then
        point, x, y, orientation = "TOPRIGHT", -(size / 2), 0, "horizontal"
    elseif db.orientation == "top-to-bottom" then
        point, x, y, orientation = "TOPLEFT", 0, -(size / 2), "vertical"
    else
        point, x, y, orientation = "BOTTOMLEFT", 0, size / 2, "vertical"
    end

    for i = 1, 5 do
        local icon = display.icons[i]
        icon:ClearAllPoints()
        icon:SetSize(size, size)

        if i == 1 then
            icon:SetPoint(point)
        elseif stacked then
            icon:SetAllPoints(display.icons[1])
        else
            icon:SetPoint(point, display.icons[i - 1], point, x, y)
        end
    end

    if iconsShown and iconsShown > 0 then
        if stacked then
            display.holder:SetSize(size, size)
        elseif orientation == "horizontal" then
            display.holder:SetSize(size + ((iconsShown - 1) * (size / 2)), size)
        else
            display.holder:SetSize(size, size + ((iconsShown - 1) * (size / 2)))
        end
    end
end

local function ConfigureDisplay(display)
    if not display then return end

    local db = NS.db
    local frame = display.frame
    display.holder:ClearAllPoints()
    display.holder:SetPoint(db.point, frame, db.relativePoint, db.xOffset, db.yOffset)
    display.holder:SetFrameLevel((frame:GetFrameLevel() or 1) + (db.frameLevel or 15))

    LayoutIcons(display, 1)
end

local function ShowHighlight(display, dispelType, r, g, b, alpha, useProvidedAlpha)
    local db = NS.db
    local highlightType = db.highlightType
    if highlightType == "none" then
        display.highlight:Hide()
        return
    end

    local frame = display.frame
    local health = frame.Health or frame
    local statusTexture = health.GetStatusBarTexture and health:GetStatusBarTexture()
    local highlight = display.highlight

    if dispelType then
        r, g, b = GetTypeColor(dispelType)
    end
    if not useProvidedAlpha then
        alpha = highlightType == "entire" and 0.5 or 1
    end

    highlight:ClearAllPoints()
    highlight:SetBlendMode(highlightType == "current+" and "ADD" or "BLEND")

    if highlightType == "entire" then
        highlight:SetTexture(E.media.blankTex)
        highlight:SetAllPoints(health)
        highlight:SetVertexColor(r, g, b, alpha)
    elseif highlightType == "current" or highlightType == "current+" then
        highlight:SetTexture(E.media.blankTex)
        highlight:SetAllPoints(statusTexture or health)
        highlight:SetVertexColor(r, g, b, alpha)
    elseif highlightType == "gradient" then
        highlight:SetTexture(DISPEL_GRADIENT_TEXTURE)
        highlight:SetAllPoints(health)
        highlight:SetVertexColor(r, g, b, alpha)
    elseif highlightType == "gradient-half" then
        highlight:SetTexture(DISPEL_GRADIENT_TEXTURE)
        highlight:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT")
        highlight:SetPoint("TOPRIGHT", health, "RIGHT")
        highlight:SetVertexColor(r, g, b, alpha)
    end

    highlight:Show()
end

local function BuildHighlightCurveColor(dispelType, selected)
    if not selected then
        return CreateColor(0, 0, 0, 0)
    end

    local r, g, b = GetTypeColor(dispelType)
    local alpha = NS.db.highlightType == "entire" and 0.5 or 1
    return CreateColor(r, g, b, alpha)
end

local function BuildIconCurveColor(dispelType)
    local r, g, b = GetTypeColor(dispelType)
    return CreateColor(r, g, b, 1)
end

local function BuildSecretHighlightCurve(includePlayerModes)
    local stepType = Enum.LuaCurveType.Step
    local transparent = CreateColor(0, 0, 0, 0)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(stepType)
    curve:AddPoint(0, transparent)

    for _, info in ipairs(DISPEL_TYPES) do
        curve:AddPoint(info.idx, BuildHighlightCurveColor(info.name, IsSecretDispelTypeEnabled(info.name, includePlayerModes)))
    end

    curve:AddPoint(5, transparent)
    curve:AddPoint(9, transparent)
    curve:AddPoint(12, transparent)

    return curve
end

function NS:BuildDispelCurves()
    self.curvesReady = false
    self.highlightCurve = nil
    self.alwaysHighlightCurve = nil
    self.bracketCurves = nil

    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and GetAuraDispelTypeColor and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then
        return
    end

    local stepType = Enum.LuaCurveType.Step
    local transparent = CreateColor(0, 0, 0, 0)

    local bracketCurves = {}
    for _, info in ipairs(DISPEL_TYPES) do
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(stepType)
        curve:AddPoint(0, transparent)
        curve:AddPoint(info.idx, BuildIconCurveColor(info.name))
        curve:AddPoint(info.nextIdx, transparent)
        bracketCurves[info.name] = curve
    end

    self.highlightCurve = BuildSecretHighlightCurve(true)
    self.alwaysHighlightCurve = BuildSecretHighlightCurve(false)
    self.bracketCurves = bracketCurves
    self.curvesReady = true
end

local function CanDispelType(dispelType)
    local lib = E.Libs and E.Libs.Dispel
    if lib and lib.IsDispellableByMe then
        return lib:IsDispellableByMe(dispelType)
    end

    return false
end

local function IsPlayerDispellableAura(unit, auraInstanceID, debuffType)
    if IsAuraFilteredOutByInstanceID and auraInstanceID then
        local filtered = IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if IsValueNonSecret(filtered) then
            if filtered == false then
                return true
            end

            if playerClass == "SHAMAN" and debuffType == "Poison" then
                return CanDispelType("Poison")
            end

            return false
        end
    end

    if debuffType then
        return CanDispelType(debuffType)
    end

    return false
end

local function ShouldShowDispelType(unit, auraInstanceID, debuffType)
    if not (debuffType and IsDispelTypeEnabled(debuffType)) then
        return false
    end

    if GetDispelMode(debuffType) == "always" then
        return true
    end

    return IsPlayerDispellableAura(unit, auraInstanceID, debuffType)
end

local function ScanPlayerDispels(found)
    wipe(found)

    local secretAuraID, secretUnit
    local secretPlayerDispellable

    for index = 1, 60 do
        local ok, aura = pcall(GetAuraDataByIndex, "player", index, "HARMFUL")
        if not ok or not aura then
            break
        end

        local auraInstanceID = aura.auraInstanceID
        if IsValueNonSecret(auraInstanceID) then
            local rawDispelName = aura.dispelName
            local debuffType
            local secretDispellable = false

            if IsValueNonSecret(rawDispelName) then
                debuffType = rawDispelName
            else
                secretDispellable = true
            end

            if ShouldShowDispelType("player", auraInstanceID, debuffType) then
                found[debuffType] = true
            elseif secretDispellable and NS.curvesReady then
                local playerDispellable = IsPlayerDispellableAura("player", auraInstanceID)
                if HasVisibleSecretDispelType(playerDispellable) then
                    secretAuraID = auraInstanceID
                    secretUnit = "player"
                    secretPlayerDispellable = playerDispellable
                end
            end
        end
    end

    return secretUnit, secretAuraID, secretPlayerDispellable
end

local foundDispels = {}

local function BuildTestDispels(found)
    wipe(found)

    local added = false
    for _, dispelType in ipairs(DISPEL_ORDER) do
        if IsDispelTypeEnabled(dispelType) then
            found[dispelType] = true
            added = true
        end
    end

    if not added then
        found.Magic = true
    end
end

local function RenderNormalDispels(display, found)
    local db = NS.db
    local iconsShown = 0
    local highlighted = false

    display.highlight:Hide()

    for _, dispelType in ipairs(DISPEL_ORDER) do
        if found[dispelType] then
            if not highlighted then
                ShowHighlight(display, dispelType)
                highlighted = true
            end

            if db.iconStyle ~= "none" then
                iconsShown = iconsShown + 1
                SetIcon(display, iconsShown, dispelType)
            end
        end
    end

    for i = iconsShown + 1, 5 do
        display.icons[i]:Hide()
    end

    if iconsShown > 0 then
        LayoutIcons(display, iconsShown)
        display.holder:Show()
    else
        display.holder:Hide()
    end

    return highlighted or iconsShown > 0
end

local function RenderSecretDispel(display, unit, auraInstanceID, playerDispellable)
    local db = NS.db
    if not (NS.curvesReady and unit and auraInstanceID) then
        return false
    end

    local includePlayerModes = playerDispellable == true
    local highlightCurve = includePlayerModes and NS.highlightCurve or NS.alwaysHighlightCurve
    local rendered = false
    local highlightColor = GetAuraDispelTypeColor(unit, auraInstanceID, highlightCurve)
    display.highlight:Hide()

    if highlightColor and db.highlightType ~= "none" then
        local r, g, b, alpha = highlightColor:GetRGBA()
        if alpha and alpha > 0 then
            ShowHighlight(display, nil, r, g, b, alpha, true)
            rendered = true
        end
    end

    if db.iconStyle ~= "none" then
        local iconsShown = 0
        local hasVisibleIcon = false
        for _, info in ipairs(DISPEL_TYPES) do
            if IsSecretDispelTypeEnabled(info.name, includePlayerModes) then
                iconsShown = iconsShown + 1
                local icon = SetIcon(display, iconsShown, info.name)
                local iconColor = GetAuraDispelTypeColor(unit, auraInstanceID, NS.bracketCurves[info.name])
                if icon and iconColor then
                    local _, _, _, alpha = iconColor:GetRGBA()
                    icon:SetAlpha(alpha)
                    if alpha and alpha > 0 then
                        hasVisibleIcon = true
                    end
                elseif icon then
                    icon:SetAlpha(0)
                end
            end
        end

        for i = iconsShown + 1, 5 do
            display.icons[i]:Hide()
        end

        if iconsShown > 0 and hasVisibleIcon then
            LayoutIcons(display, iconsShown, true)
            display.holder:Show()
            rendered = true
        else
            display.holder:Hide()
        end
    else
        display.holder:Hide()
    end

    return rendered
end

function NS:Update()
    if not initialized then return end

    local frame = GetPlayerFrame()
    local display = GetDisplay(frame)
    if not display then return end

    ConfigureDisplay(display)

    if not self.db.enabled or not frame:IsShown() then
        HideDisplay(display)
        return
    end

    if self.db.testMode then
        BuildTestDispels(foundDispels)
        if not RenderNormalDispels(display, foundDispels) then
            HideDisplay(display)
        end
        return
    end

    local secretUnit, secretAuraID, secretPlayerDispellable = ScanPlayerDispels(foundDispels)
    local rendered = RenderNormalDispels(display, foundDispels)

    if not rendered then
        rendered = RenderSecretDispel(display, secretUnit, secretAuraID, secretPlayerDispellable)
    end

    if not rendered then
        HideDisplay(display)
    end
end

function NS:QueueUpdate()
    if updateQueued then return end

    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        NS:Update()
    end)
end

function NS:ApplySettings()
    local frame = GetPlayerFrame()
    if frame then
        ConfigureDisplay(GetDisplay(frame))
    end

    self:BuildDispelCurves()
    self:QueueUpdate()
end

local function RegisterElvUIHooks()
    if NS.hooked then return end

    hooksecurefunc(UF, "Update_PlayerFrame", function(_, frame)
        ConfigureDisplay(GetDisplay(frame))
        NS:QueueUpdate()
    end)

    NS.hooked = true
end

local function RegisterOptionsSafely()
    if not NS.RegisterOptions then
        return false
    end

    local ok, registered = pcall(NS.RegisterOptions)
    if not ok then
        Print("Options registration failed: " .. tostring(registered))
        return false
    end

    return registered ~= false
end

local function EnsureElvUIPluginOptions()
    if not (E.Options and E.Options.args and E.Libs and E.Libs.EP) then
        return false
    end

    if not E.Options.args.plugins and E.Libs.EP.GetPluginOptions then
        local ok = pcall(E.Libs.EP.GetPluginOptions, E.Libs.EP)
        if not ok then
            return false
        end
    end

    return E.Options.args.plugins
        and E.Options.args.plugins.args
        and E.Options.args.plugins.args.plugins
end

local function RegisterElvUIPlugin()
    if pluginRegistered or not (E.Libs and E.Libs.EP and NS.RegisterOptions) then
        return
    end

    if IsAddOnLoaded("ElvUI_Options") and not EnsureElvUIPluginOptions() then
        RegisterOptionsSafely()
        return
    end

    local ok, err = pcall(E.Libs.EP.RegisterPlugin, E.Libs.EP, ADDON_NAME, RegisterOptionsSafely)
    if not ok then
        Print("ElvUI plugin registration failed: " .. tostring(err))
        RegisterOptionsSafely()
        return
    end

    pluginRegistered = true
end

local function OpenOptions()
    RegisterOptionsSafely()

    if E and E.ToggleOptions then
        E:ToggleOptions("unitframe,individualUnits,player,dispellableBorderIcon")
    end
end

_G.ElvUIDispellableBorderIcon_OnAddonCompartmentClick = OpenOptions

local function RegisterSlashCommands()
    SLASH_ELVUIDISPELLABLEBORDERICON1 = "/edbi"
    SLASH_ELVUIDISPELLABLEBORDERICON2 = "/elvuidispel"
    SlashCmdList.ELVUIDISPELLABLEBORDERICON = function(message)
        message = strtrim(message or "")
        if message == "debug" then
            NS.debug = not NS.debug
            Print("Debug " .. (NS.debug and "enabled." or "disabled."))
        else
            OpenOptions()
        end
    end
end

local function OnAddonLoaded(self, loadedAddon)
    if loadedAddon == "ElvUI_Options" then
        RegisterElvUIPlugin()
        RegisterOptionsSafely()

        if initialized then
            self:UnregisterEvent("ADDON_LOADED")
        end

        return
    end

    if loadedAddon ~= ADDON_NAME then return end

    ElvUI_DispellableBorderIconDB = ElvUI_DispellableBorderIconDB or {}
    CopyDefaults(NS.defaults, ElvUI_DispellableBorderIconDB)
    NS.db = ElvUI_DispellableBorderIconDB

    local _, classFile = UnitClass("player")
    playerClass = classFile

    NS.version = GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"
    NS:BuildDispelCurves()
    RegisterElvUIHooks()
    RegisterSlashCommands()
    RegisterElvUIPlugin()

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("PLAYER_TALENT_UPDATE")
    self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    self:RegisterEvent("CHARACTER_POINTS_CHANGED")
    self:RegisterUnitEvent("UNIT_PET", "player")

    initialized = true

    if IsAddOnLoaded("ElvUI_Options") then
        RegisterOptionsSafely()
        self:UnregisterEvent("ADDON_LOADED")
    end

    NS:QueueUpdate()
end

local EVENT_HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_ENTERING_WORLD = function()
        local _, classFile = UnitClass("player")
        playerClass = classFile or playerClass
        NS:QueueUpdate()
    end,
    UNIT_AURA = function(_, unit)
        if unit == "player" then
            NS:QueueUpdate()
        end
    end,
    SPELLS_CHANGED = function()
        NS:QueueUpdate()
    end,
    PLAYER_TALENT_UPDATE = function()
        NS:QueueUpdate()
    end,
    LEARNED_SPELL_IN_SKILL_LINE = function()
        NS:QueueUpdate()
    end,
    CHARACTER_POINTS_CHANGED = function()
        NS:QueueUpdate()
    end,
    UNIT_PET = function(_, unit)
        if unit == "player" then
            NS:QueueUpdate()
        end
    end,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then
        handler(self, ...)
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
