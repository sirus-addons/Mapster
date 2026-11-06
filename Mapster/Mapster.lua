--[[
Copyright (c) 2009, Hendrik "Nevcairiel" Leppkes < h.leppkes@gmail.com >
All rights reserved.
]]

local Mapster = LibStub("AceAddon-3.0"):NewAddon("Mapster", "AceEvent-3.0", "AceHook-3.0")

local LibWindow = LibStub("LibWindow-1.1")
local L = LibStub("AceLocale-3.0"):GetLocale("Mapster")

local defaults = {
	profile = {
		strata = "HIGH",
		hideMapButton = false,
		arrowScale = 0.88,
		questObjectives = 2,
		modules = {
			['*'] = true,
		},
		x = 0,
		y = 0,
		points = "CENTER",
		scale = 0.75,
		poiScale = 0.8,
		ejScale = 0.8,
		alpha = 1,
		hideBorder = false,
		disableMouse = false,
		miniMap = false,
		mini = {
			x = 0,
			y = 0,
			point = "CENTER",
			scale = 1,
			alpha = 0.9,
			hideBorder = true,
			disableMouse = true,
		}
	}
}

-- Variables that are changed on "mini" mode
local miniList = { x = true, y = true, point = true, scale = true, alpha = true, hideBorder = true, disableMouse = true }

local db_
local db = setmetatable({}, {
	__index = function(t, k)
		if Mapster.miniMap and miniList[k] then
			return db_.mini[k]
		else
			return db_[k]
		end
	end,
	__newindex = function(t, k, v)
		if Mapster.miniMap and miniList[k] then
			db_.mini[k] = v
		else
			db_[k] = v
		end
	end
})

local format = string.format

local wmfOnShow, wmfStartMoving, wmfStopMoving, dropdownScaleFix
local questObjDropDownInit, questObjDropDownUpdate
local wmfOnHide

function Mapster:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("MapsterDB", defaults, true)
	db_ = self.db.profile

	self.db.RegisterCallback(self, "OnProfileChanged", "Refresh")
	self.db.RegisterCallback(self, "OnProfileCopied", "Refresh")
	self.db.RegisterCallback(self, "OnProfileReset", "Refresh")

	self.elementsToHide = {}

	self:SetupOptions()
end

local realZone
function Mapster:OnEnable()
	local advanced, mini = GetCVarBool("advancedWorldMap"), GetCVarBool("miniWorldMap")
	SetCVar("miniWorldMap", nil)
	SetCVar("advancedWorldMap", nil)
	InterfaceOptionsObjectivesPanelAdvancedWorldMap:Disable()
	InterfaceOptionsObjectivesPanelAdvancedWorldMapText:SetTextColor(0.5,0.5,0.5)
	-- restore map to its vanilla state
	if mini then
		WorldMap_ToggleSizeUp()
	end
	if advanced then
		WorldMapFrame_ToggleAdvanced()
	end

	self:SetupMapButton()

	LibWindow.RegisterConfig(WorldMapFrame, db)

	local vis = WorldMapFrame:IsVisible()
	if vis then
		HideUIPanel(WorldMapFrame)
	end

	UIPanelWindows["WorldMapFrame"] = nil
	WorldMapFrame:SetAttribute("UIPanelLayout-enabled", false)
	WorldMapFrame:SetAttribute("UIPanelLayout-defined", true)
	WorldMapFrame:HookScript("OnShow", wmfOnShow)
	WorldMapFrame:HookScript("OnHide", wmfOnHide)
	BlackoutWorld:Hide()
	WorldMapTitleButton:Hide()

	WorldMapFrame:SetScript("OnKeyDown", nil)

	WorldMapFrame:SetMovable(true)
	WorldMapFrame:RegisterForDrag("LeftButton")
	WorldMapFrame:SetScript("OnDragStart", wmfStartMoving)
	WorldMapFrame:SetScript("OnDragStop", wmfStopMoving)

	WorldMapFrame:SetParent(UIParent)
	WorldMapFrame:SetToplevel(true)
	WorldMapFrame:SetWidth(1024)
	WorldMapFrame:SetHeight(768)
	WorldMapFrame:SetClampedToScreen(false)

	WorldMapContinentDropDownButton:HookScript("OnClick", dropdownScaleFix)
	WorldMapZoneDropDownButton:HookScript("OnClick", dropdownScaleFix)
	WorldMapZoneMinimapDropDownButton:HookScript("OnClick", dropdownScaleFix)

	WorldMapFrameSizeDownButton:SetScript("OnClick", function() Mapster:ToggleMapSize() end)
	WorldMapFrameSizeUpButton:SetScript("OnClick", function() Mapster:ToggleMapSize() end)
	
	-- Hide Quest Objectives CheckBox and replace it with a DropDown
	WorldMapQuestShowObjectives:Hide()
	WorldMapQuestShowObjectives:SetChecked(db.questObjectives ~= 0)
	WorldMapQuestShowObjectives_Toggle()
	local questObj = CreateFrame("Frame", "MapsterQuestObjectivesDropDown", WorldMapFrame, "UIDropDownMenuTemplate")
	questObj:SetPoint("BOTTOMRIGHT", "WorldMapPositioningGuide", "BOTTOMRIGHT", -5, -2)
	
	local text = questObj:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetText(L["Quest Objectives"])
	text:SetPoint("RIGHT", questObj, "LEFT", 5, 3)
	-- Init DropDown
	UIDropDownMenu_Initialize(questObj, questObjDropDownInit)
	UIDropDownMenu_SetWidth(questObj, 150)
	questObjDropDownUpdate()

	hooksecurefunc(WorldMapTooltip, "Show", function(self)
		self:SetFrameStrata("TOOLTIP")
	end)

	tinsert(UISpecialFrames, "WorldMapFrame")

	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")

	if db.miniMap then
		self:SizeDown()
	end
	self.miniMap = db.miniMap

	self:SetPosition()
	self:SetAlpha()
	self:SetArrow()
	self:UpdateBorderVisibility()
	self:UpdateMouseInteractivity()

	self:SecureHook("WorldMapFrame_DisplayQuestPOI")
	self:SecureHook("WorldMapFrame_DisplayQuests")
	self:SecureHook("WorldMapFrame_SetPOIMaxBounds")
	self:SecureHook("WorldMapLevelDropDown_Update", "UpdateMapElements")
	WorldMapFrame_SetPOIMaxBounds()
	self:SecureHook("EncounterJournal_AddMapButtons")
	self:RawHook("WorldMapFrame_ToggleWindowSize", "ToggleMapSize", true)

	if vis then
		ShowUIPanel(WorldMapFrame)
	end
end

local blobWasVisible, blobNewScale
local blobHideFunc = function() blobWasVisible = nil end
local blobShowFunc = function() blobWasVisible = true end
local blobScaleFunc = function(self, scale) blobNewScale = scale end

function Mapster:PLAYER_REGEN_DISABLED()
	blobWasVisible = WorldMapBlobFrame:IsShown()
	blobNewScale = nil
	WorldMapBlobFrame:SetParent(nil)
	WorldMapBlobFrame:ClearAllPoints()
	-- dummy position, off screen, so calculations don't go boom
	WorldMapBlobFrame:SetPoint("TOP", UIParent, "BOTTOM")
	WorldMapBlobFrame:Hide()
	WorldMapBlobFrame.Hide = blobHideFunc
	WorldMapBlobFrame.Show = blobShowFunc
	WorldMapBlobFrame.SetScale = blobScaleFunc
end

local updateFrame = CreateFrame("Frame")
local function restoreBlobs()
	WorldMapBlobFrame_CalculateHitTranslations()
	if WORLDMAP_SETTINGS.selectedQuest and not WORLDMAP_SETTINGS.selectedQuest.completed then
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuest.questId, true)
	end
	updateFrame:SetScript("OnUpdate", nil)
end

function Mapster:PLAYER_REGEN_ENABLED()
	WorldMapBlobFrame:SetParent(WorldMapFrame)
	WorldMapBlobFrame:ClearAllPoints()
	WorldMapBlobFrame:SetPoint("TOPLEFT", WorldMapDetailFrame)
	WorldMapBlobFrame.Hide = nil
	WorldMapBlobFrame.Show = nil
	WorldMapBlobFrame.SetScale = nil
	if blobWasVisible then
		WorldMapBlobFrame:Show()
		updateFrame:SetScript("OnUpdate", restoreBlobs)
	end
	if blobNewScale then
		WorldMapBlobFrame:SetScale(blobNewScale)
		WorldMapBlobFrame.xRatio = nil
		blobNewScale = nil
	end

	if WORLDMAP_SETTINGS.selectedQuest then
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuest.questId, false)
	end
end

local WORLDMAP_POI_MIN_X = 12
local WORLDMAP_POI_MIN_Y = -12
local WORLDMAP_POI_MAX_X     -- changes based on current scale, see WorldMapFrame_SetPOIMaxBounds
local WORLDMAP_POI_MAX_Y     -- changes based on current scale, see WorldMapFrame_SetPOIMaxBounds

local iconRefreshFrame = CreateFrame("Frame")
local iconRefreshPending
local iconRefreshTries = 0

local function detailMapScale()
	local scale = WorldMapDetailFrame:GetScale()
	if not scale or scale <= 0 then
		scale = WORLDMAP_SETTINGS.size
	end
	if not scale or scale <= 0 then
		scale = 1
	end
	return scale
end

function Mapster:RefreshMapIconsSoon()
	if iconRefreshPending or iconRefreshTries >= 5 then
		return
	end
	iconRefreshTries = iconRefreshTries + 1
	iconRefreshPending = true
	iconRefreshFrame:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		iconRefreshPending = false
		if not WorldMapFrame:IsShown() then
			return
		end
		EncounterJournal_AddMapButtons()
		WorldMapFrame_UpdateQuests()
		Mapster:ShowBlobs()
	end)
end

function Mapster:WorldMapFrame_DisplayQuestPOI(questFrame, isComplete)
	local _, posX, posY = QuestPOIGetIconInfo(questFrame.questId)
	if posX and posY and questFrame.poiIcon then
		local POIscale = detailMapScale()
		local width = WorldMapDetailFrame:GetWidth()
		local height = WorldMapDetailFrame:GetHeight()
		if not width or width <= 0 or not height or height <= 0 then
			self:RefreshMapIconsSoon()
			return
		end
		posX = posX * width * POIscale
		posY = -posY * height * POIscale

		-- keep outlying POIs within map borders
		if WORLDMAP_POI_MAX_X and WORLDMAP_POI_MAX_Y then
			if ( posY > WORLDMAP_POI_MIN_Y ) then
				posY = WORLDMAP_POI_MIN_Y
			elseif ( posY < WORLDMAP_POI_MAX_Y ) then
				posY = WORLDMAP_POI_MAX_Y
			end
			if ( posX < WORLDMAP_POI_MIN_X ) then
				posX = WORLDMAP_POI_MIN_X
			elseif ( posX > WORLDMAP_POI_MAX_X ) then
				posX = WORLDMAP_POI_MAX_X
			end
		end
		questFrame.poiIcon:ClearAllPoints()
		questFrame.poiIcon:SetPoint("CENTER", "WorldMapPOIFrame", "TOPLEFT", posX / db.poiScale, posY / db.poiScale)
		questFrame.poiIcon:SetScale(db.poiScale)
		local swap = QUEST_POI_SWAP_BUTTONS.WorldMapPOIFrame
		if swap then
			swap:SetScale(db.poiScale)
		end
	end
end

function Mapster:WorldMapFrame_SetPOIMaxBounds()
	local scale = detailMapScale()
	WORLDMAP_POI_MAX_Y = WorldMapDetailFrame:GetHeight() * -scale + 12;
	WORLDMAP_POI_MAX_X = WorldMapDetailFrame:GetWidth() * scale + 12;
end

function Mapster:EncounterJournal_AddMapButtons()
	local width = WorldMapDetailFrame:GetWidth()
	local height = WorldMapDetailFrame:GetHeight()
	if not width or width <= 0 or not height or height <= 0 or not WorldMapBossButtonFrame:GetLeft() then
		self:RefreshMapIconsSoon()
		return
	end
	iconRefreshTries = 0

	local index = 1
	local x, y, _, _, name = EJ_GetMapEncounter(index, WorldMapFrame.fromJournal)
	while name do
		local bossButton = _G["EJMapButton"..index]
		if bossButton then
			bossButton:SetScale(db.ejScale)
			bossButton:SetPoint("CENTER", WorldMapBossButtonFrame, "BOTTOMLEFT", x * width / db.ejScale, (1 - y) * height / db.ejScale)
		end
		index = index + 1
		x, y, _, _, name = EJ_GetMapEncounter(index, WorldMapFrame.fromJournal)
	end
end

function Mapster:Refresh()
	db_ = self.db.profile

	for k,v in self:IterateModules() do
		if self:GetModuleEnabled(k) and not v:IsEnabled() then
			self:EnableModule(k)
		elseif not self:GetModuleEnabled(k) and v:IsEnabled() then
			self:DisableModule(k)
		end
		if type(v.Refresh) == "function" then
			v:Refresh()
		end
	end

	if (db.miniMap and not self.miniMap) then
		self:SizeDown()
	elseif (not db.miniMap and self.miniMap) then
		self:SizeUp()
	end
	self.miniMap = db.miniMap

	self:SetStrata()
	self:SetAlpha()
	self:SetArrow()
	self:SetScale()
	self:SetPosition()

	if self.optionsButton then
		if db.hideMapButton then
			self.optionsButton:Hide()
		else
			self.optionsButton:Show()
		end
	end

	self:UpdateBorderVisibility()
	self:UpdateMouseInteractivity()
	self:UpdateModuleMapsizes()
	WorldMapFrame_UpdateQuests()
	self:ShowBlobs()
	EncounterJournal_AddMapButtons()
end

function Mapster:ToggleMapSize()
	local continentID, dungeonLevel
	local mapID = GetCurrentMapAreaID() - 1
	if mapID < 0 then
		continentID = GetCurrentMapContinent()
	else
		dungeonLevel = GetCurrentMapDungeonLevel()
	end

	self.miniMap = not self.miniMap
	db.miniMap = self.miniMap
	WorldMapFrame.toggling = true
	ToggleFrame(WorldMapFrame)
	if self.miniMap then
		self:SizeDown()
	else
		self:SizeUp()
	end
	self:SetAlpha()
	self:SetPosition()

	-- Notify the modules about the map size change,
	-- so they can re-anchor frames or stuff like that.
	self:UpdateModuleMapsizes()

	self:UpdateBorderVisibility()
	self:UpdateMouseInteractivity()

	WorldMapFrame.blockWorldMapUpdate = true
	ToggleFrame(WorldMapFrame)
	if continentID then
		SetMapZoom(continentID)
	else
		SetMapByID(mapID)
		if dungeonLevel > 0 then
			SetDungeonMapLevel(dungeonLevel)
		end
	end
	WorldMapFrame.blockWorldMapUpdate = nil
	WorldMapFrame_UpdateMap()
	WorldMapFrame_UpdateQuests()
	self:ShowBlobs()
end

function Mapster:UpdateModuleMapsizes()
	for k,v in self:IterateModules() do
		if v:IsEnabled() and type(v.UpdateMapsize) == "function" then
			v:UpdateMapsize(self.miniMap)
		end
	end
end

function Mapster:SizeUp()
	WORLDMAP_SETTINGS.size = WORLDMAP_QUESTLIST_SIZE
	-- adjust main frame
	WorldMapFrame:SetWidth(1024)
	WorldMapFrame:SetHeight(768)
	-- adjust map frames
	WorldMapPositioningGuide:ClearAllPoints()
	WorldMapPositioningGuide:SetPoint("CENTER")
	WorldMapDetailFrame:SetScale(WORLDMAP_QUESTLIST_SIZE)
	WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOP", -726, -99)
	WorldMapButton:SetScale(WORLDMAP_QUESTLIST_SIZE)
	WorldMapFrameAreaFrame:SetScale(WORLDMAP_QUESTLIST_SIZE)
	WorldMapBlobFrame:SetScale(WORLDMAP_QUESTLIST_SIZE)
	WorldMapBlobFrame.xRatio = nil		-- force hit recalculations
	-- show big window elements
	WorldMapZoneMinimapDropDown:Show()
	WorldMapZoomOutButton:Show()
	WorldMapZoneDropDown:Show()
	WorldMapContinentDropDown:Show()
	WorldMapQuestScrollFrame:Show()
	WorldMapQuestDetailScrollFrame:Show()
	WorldMapQuestRewardScrollFrame:Show()
	WorldMapFrameSizeDownButton:Show()
	-- hide small window elements
	WorldMapFrameMiniBorderLeft:Hide()
	WorldMapFrameMiniBorderRight:Hide()
	WorldMapFrameSizeUpButton:Hide()
	-- floor dropdown
	WorldMapLevelDropDown:SetPoint("TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -50, -35)
	WorldMapLevelDropDown.header:Show()
	-- tiny adjustments
	WorldMapFrameCloseButton:SetPoint("TOPRIGHT", WorldMapPositioningGuide, 4, 4)
	WorldMapFrameSizeDownButton:SetPoint("TOPRIGHT", WorldMapPositioningGuide, -16, 4)
	WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 16, 4)
	WorldMapFrameTitle:ClearAllPoints()
	WorldMapFrameTitle:SetPoint("CENTER", 0, 372)

	MapsterQuestObjectivesDropDown:Show()

	WorldMapFrame_SetPOIMaxBounds()
	--WorldMapQuestShowObjectives_AdjustPosition()
	self:WorldMapFrame_DisplayQuests()

	self.optionsButton:SetPoint("TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -43, -2)
end

function Mapster:SizeDown()
	WORLDMAP_SETTINGS.size = WORLDMAP_WINDOWED_SIZE
	-- adjust main frame
	WorldMapFrame:SetWidth(623)
	WorldMapFrame:SetHeight(437)
	-- adjust map frames
	WorldMapPositioningGuide:ClearAllPoints()
	WorldMapPositioningGuide:SetAllPoints()
	WorldMapDetailFrame:SetScale(WORLDMAP_WINDOWED_SIZE)
	WorldMapButton:SetScale(WORLDMAP_WINDOWED_SIZE)
	WorldMapFrameAreaFrame:SetScale(WORLDMAP_WINDOWED_SIZE)
	WorldMapBlobFrame:SetScale(WORLDMAP_WINDOWED_SIZE)
	WorldMapBlobFrame.xRatio = nil		-- force hit recalculations
	WorldMapFrameMiniBorderLeft:SetPoint("TOPLEFT", 10, -14)
	WorldMapDetailFrame:SetPoint("TOPLEFT", 37, -66)
	-- hide big window elements
	WorldMapZoneMinimapDropDown:Hide()
	WorldMapZoomOutButton:Hide()
	WorldMapZoneDropDown:Hide()
	WorldMapContinentDropDown:Hide()
	WorldMapLevelDropDown:Hide()
	WorldMapLevelUpButton:Hide()
	WorldMapLevelDownButton:Hide()
	WorldMapQuestScrollFrame:Hide()
	WorldMapQuestDetailScrollFrame:Hide()
	WorldMapQuestRewardScrollFrame:Hide()
	WorldMapFrameSizeDownButton:Hide()
	-- show small window elements
	WorldMapFrameMiniBorderLeft:Show()
	WorldMapFrameMiniBorderRight:Show()
	WorldMapFrameSizeUpButton:Show()
	-- floor dropdown
	WorldMapLevelDropDown:SetPoint("TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -441, -35)
	WorldMapLevelDropDown:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL + 2)
	WorldMapLevelDropDown.header:Hide()
	-- tiny adjustments
	WorldMapFrameCloseButton:SetPoint("TOPRIGHT", WorldMapFrameMiniBorderRight, "TOPRIGHT", -44, 5)
	WorldMapFrameSizeDownButton:SetPoint("TOPRIGHT", WorldMapFrameMiniBorderRight, "TOPRIGHT", -66, 5)
	WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapDetailFrame, "BOTTOMLeft", 2, -26)
	WorldMapFrameTitle:ClearAllPoints()
	WorldMapFrameTitle:SetPoint("TOP", WorldMapDetailFrame, 0, 20)

	MapsterQuestObjectivesDropDown:Hide()

	WorldMapFrame_SetPOIMaxBounds()
	--WorldMapQuestShowObjectives_AdjustPosition()

	self.optionsButton:SetPoint("TOPRIGHT", WorldMapFrameMiniBorderRight, "TOPRIGHT", -93, -2)
end

local function getZoneId()
	return (GetCurrentMapZone() + GetCurrentMapContinent() * 100)
end

function Mapster:ZONE_CHANGED_NEW_AREA()
	local curZone = getZoneId()
	if realZone == curZone or ((curZone % 100) > 0 and (GetPlayerMapPosition("player")) ~= 0) then
		SetMapToCurrentZone()
		realZone = getZoneId()
	end
end

local oldBFMOnUpdate
function wmfOnShow(frame)
	Mapster:SetStrata()
	Mapster:SetScale()
	realZone = getZoneId()
	if BattlefieldMinimap then
		oldBFMOnUpdate = BattlefieldMinimap:GetScript("OnUpdate")
		BattlefieldMinimap:SetScript("OnUpdate", nil)
	end

	if WORLDMAP_SETTINGS.selectedQuest then
		WorldMapFrame_SelectQuestFrame(WORLDMAP_SETTINGS.selectedQuest)
	end
	Mapster:RefreshMapIconsSoon()
end

function wmfOnHide(frame)
	iconRefreshTries = 0
	if not WorldMapFrame.toggling then
		SetMapToCurrentZone()
	end
	if BattlefieldMinimap then
		BattlefieldMinimap:SetScript("OnUpdate", oldBFMOnUpdate or BattlefieldMinimap_OnUpdate)
	end
end

function wmfStartMoving(frame)
	Mapster:HideBlobs()

	frame:StartMoving()
end

function wmfStopMoving(frame)
	frame:StopMovingOrSizing()
	LibWindow.SavePosition(frame)

	Mapster:ShowBlobs()
end

function dropdownScaleFix(self)
	local uiScale = 1
	local uiParentScale = UIParent:GetScale()
	if GetCVar("useUIScale") == "1" then
		uiScale = tonumber(GetCVar("uiscale"))
		if uiParentScale < uiScale then
			uiScale = uiParentScale
		end
	else
		uiScale = uiParentScale
	end
	DropDownList1:SetScale(uiScale * db.scale)
end

function Mapster:ShowBlobs()
	WorldMapBlobFrame_CalculateHitTranslations()
	if WORLDMAP_SETTINGS.selectedQuest and not WORLDMAP_SETTINGS.selectedQuest.completed then
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuest.questId, true)
	end
end

function Mapster:HideBlobs()
	if WORLDMAP_SETTINGS.selectedQuest then
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuest.questId, false)
	end
end

function Mapster:SetStrata()
	WorldMapFrame:SetFrameStrata(db.strata)
end

function Mapster:SetAlpha()
	WorldMapFrame:SetAlpha(db.alpha)
end

function Mapster:SetArrow()
	PlayerArrowFrame:SetModelScale(db.arrowScale)
	PlayerArrowEffectFrame:SetModelScale(db.arrowScale)
end

function Mapster:SetScale()
	WorldMapFrame:SetScale(db.scale)
end

function Mapster:SetPosition()
	LibWindow.RestorePosition(WorldMapFrame)
end

function Mapster:GetModuleEnabled(module)
	return db.modules[module]
end

function Mapster:UpdateBorderVisibility()
	if db.hideBorder then
		Mapster.bordersVisible = false
		if self.miniMap then
			WorldMapFrameMiniBorderLeft:Hide()
			WorldMapFrameMiniBorderRight:Hide()
			--WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapDetailFrame, "TOPRIGHT", -50 - WorldMapQuestShowObjectivesText:GetWidth(), 2);
		else
			-- TODO
		end
		WorldMapFrameTitle:Hide()
		self:RegisterEvent("WORLD_MAP_UPDATE", "UpdateDetailTiles")
		self:UpdateDetailTiles()
		self.optionsButton:Hide()
		if not self.hookedOnUpdate then
			self:HookScript(WorldMapFrame, "OnUpdate", "UpdateMapElements")
			self.hookedOnUpdate = true
		end
		self:UpdateMapElements()
	else
		Mapster.bordersVisible = true
		if self.miniMap then
			WorldMapFrameMiniBorderLeft:Show()
			WorldMapFrameMiniBorderRight:Show()
		else
			-- TODO
		end
		--WorldMapQuestShowObjectives_AdjustPosition()
		WorldMapFrameTitle:Show()
		self:UnregisterEvent("WORLD_MAP_UPDATE")
		self:UpdateDetailTiles()
		if not db.hideMapButton then
			self.optionsButton:Show()
		end
		if self.hookedOnUpdate then
			self:Unhook(WorldMapFrame, "OnUpdate")
			self.hookedOnUpdate = nil
		end
		self:UpdateMapElements()
	end

	for k,v in self:IterateModules() do
		if v:IsEnabled() and type(v.BorderVisibilityChanged) == "function" then
			v:BorderVisibilityChanged(not db.hideBorder)
		end
	end
end

function Mapster:UpdateMapElements()
	local mouseOver = WorldMapFrame:IsMouseOver()
	if self.elementsHidden and (mouseOver or not db.hideBorder) then
		self.elementsHidden = nil
		(self.miniMap and WorldMapFrameSizeUpButton or WorldMapFrameSizeDownButton):Show()
		WorldMapFrameCloseButton:Show()
		--WorldMapQuestShowObjectives:Show()
		for _, frame in pairs(self.elementsToHide) do
			frame:Show()
		end
	elseif not self.elementsHidden and not mouseOver and db.hideBorder then
		self.elementsHidden = true
		WorldMapFrameSizeUpButton:Hide()
		WorldMapFrameSizeDownButton:Hide()
		WorldMapFrameCloseButton:Hide()
		--WorldMapQuestShowObjectives:Hide()
		for _, frame in pairs(self.elementsToHide) do
			frame:Hide()
		end
	end
end

function Mapster:UpdateMouseInteractivity()
	if db.disableMouse then
		WorldMapButton:EnableMouse(false)
		WorldMapFrame:EnableMouse(false)
	else
		WorldMapButton:EnableMouse(true)
		WorldMapFrame:EnableMouse(true)
	end
end

function Mapster:RefreshQuestObjectivesDisplay()
	WorldMapQuestShowObjectives:SetChecked(db.questObjectives ~= 0)
	WorldMapQuestShowObjectives:GetScript("OnClick")(WorldMapQuestShowObjectives)
end

function Mapster:WorldMapFrame_DisplayQuests()
	if WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then return end
	if ObjectiveTrackerManager:CanShowPOIs(QuestObjectiveTracker) and WorldMapFrame.numQuests > 0 then
		if db.questObjectives == 1 then
			WorldMapFrame_SetFullMapView()
			
			WorldMapBlobFrame:SetScale(WORLDMAP_FULLMAP_SIZE)
			WorldMapBlobFrame.xRatio = nil		-- force hit recalculations
			WorldMapFrame_SetPOIMaxBounds()
			WorldMapFrame_UpdateQuests()
			self:ShowBlobs()
		elseif db.questObjectives == 2 then
			WorldMapFrame_SetQuestMapView()
			
			WorldMapBlobFrame:SetScale(WORLDMAP_QUESTLIST_SIZE)
			WorldMapBlobFrame.xRatio = nil		-- force hit recalculations
			WorldMapFrame_SetPOIMaxBounds()
			WorldMapFrame_UpdateQuests()
			self:ShowBlobs()
		end
	end
end

local function hasOverlays()
	if Mapster:GetModuleEnabled("FogClear") then
		return Mapster:GetModule("FogClear"):RealHasOverlays()
	else
		return GetNumMapOverlays() > 0
	end
end

function Mapster:UpdateDetailTiles()
	if db.hideBorder and GetCurrentMapZone() > 0 and hasOverlays() then
		for i=1, NUM_WORLDMAP_DETAIL_TILES do
			_G["WorldMapDetailTile"..i]:Hide()
		end
	else
		for i=1, NUM_WORLDMAP_DETAIL_TILES do
			_G["WorldMapDetailTile"..i]:Show()
		end
	end
end

function Mapster:SetModuleEnabled(module, value)
	local old = db.modules[module]
	db.modules[module] = value
	if old ~= value then
		if value then
			self:EnableModule(module)
		else
			self:DisableModule(module)
		end
	end
end

local function questObjDropDownOnClick(button)
	UIDropDownMenu_SetSelectedValue(MapsterQuestObjectivesDropDown, button.value)
	db.questObjectives = button.value
	Mapster:RefreshQuestObjectivesDisplay()
end

local questObjTexts = {
	[0] = L["Hide Completely"],
	[1] = L["Only WorldMap Blobs"],
	[2] = L["Blobs & Panels"],
}

function questObjDropDownInit()
	local info = UIDropDownMenu_CreateInfo()
	local value = db.questObjectives

	for i=0,2 do
		info.value = i
		info.text = questObjTexts[i]
		info.func = questObjDropDownOnClick
		if ( value == i ) then
			info.checked = 1
			UIDropDownMenu_SetText(MapsterQuestObjectivesDropDown, info.text)
		else
			info.checked = nil
		end
		UIDropDownMenu_AddButton(info)
	end
end

function questObjDropDownUpdate()
	UIDropDownMenu_SetSelectedValue(MapsterQuestObjectivesDropDown, db.questObjectives)
	UIDropDownMenu_SetText(MapsterQuestObjectivesDropDown,questObjTexts[db.questObjectives])
end
