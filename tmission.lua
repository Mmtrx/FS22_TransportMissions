--=======================================================================================================
-- TransportMissions SCRIPT
--
-- Purpose:     Enable simple transport missions.
-- Author:      Mmtrx
-- Changelog:
--  v1.0.0.0    09.02.2022  initial 
--  (modHub)    14.03.2022  MP: transp mission / trigger handling ok. 
--  v1.0.1.0 	28.04.2022  Waldstetten special
--=======================================================================================================
function fakeTrigger(tMission, index)
	local trigger = g_missionManager.transportTriggers[index]
	if trigger then 
		trigger:setMission(tMission)
	else
		trigger = "fake"
		Trans.usedTriggers[index] = tMission
	end
	return trigger
end
function getl10n(xmlFile, key)
	-- get string from xmlFile, and resolve "$l10n_" prefix
	local title = xmlFile:getString(key)
	if title and title:sub(1, 6) == "$l10n_" then
    	return g_i18n:getText(title:sub(7))
    end
    return title
end
-- completely overwritten ----------------------------------------------------------
function MissionManager:loadTransportMissions(xmlFilename)
	local xmlFile = XMLFile.load("TransportMissions", xmlFilename)
	if not xmlFile then
		Logging.error("(%s) File could not be opened", xmlFilename)
		return false
	end
	xmlFile:iterate("transportMissions.mission", function (i, key)
		local mission = {
			rewardScale = xmlFile:getFloat(key .. "#rewardScale", 1),
			name = xmlFile:getString(key .. "#name"),
			title = xmlFile:getString(key .. "#title"),  -- never used?
			description = getl10n(xmlFile, key .. "#description"),
			npc = xmlFile:getInt(key .. "#npcIndex"),
			id = i
		}
		local npc = g_npcManager:getNPCByIndex(xmlFile:getInt(key .. "#npcIndex"))
		mission.npcIndex = g_npcManager:getRandomIndex()
		if npc ~= nil then
			mission.npcIndex = npc.index
		end
		npc = g_npcManager:getNPCByName(xmlFile:getString(key .. "#npcName"))
		if npc ~= nil then
			mission.npcIndex = npc.index
		end
		if mission.name == nil then
			Logging.error("Transport mission definition requires name")
		else
			mission.pickupTriggers = {}
			mission.dropoffTriggers = {}
			mission.objects = {}

			xmlFile:iterate(key .. ".pickupTrigger", function (_, subKey)
				local index = xmlFile:getString(subKey .. "#index")
				if index == nil then
					Logging.error("(%s) Pickup trigger requires valid index", xmlFilename)
				else
					table.insert(mission.pickupTriggers, {
						index = index,
						rewardScale = xmlFile:getFloat(subKey .. "#rewardScale", 1),
						title = getl10n(xmlFile, subKey.."#title")
					})
				end
			end)
			xmlFile:iterate(key .. ".dropoffTrigger", function (_, subKey)
				local index = xmlFile:getString(subKey .. "#index")
				if index == nil then
					Logging.error("(%s) Dropoff trigger requires valid index", xmlFilename)
				else
					table.insert(mission.dropoffTriggers, {
						index = index,
						rewardScale = xmlFile:getFloat(subKey .. "#rewardScale", 1),
						title = getl10n(xmlFile, subKey.."#title")
					})
				end
			end)
			xmlFile:iterate(key .. ".object", function (_, subKey)
				local filename = xmlFile:getString(subKey .. "#filename")
				if filename == nil then
					Logging.error("(%s) Object requires valid filename", xmlFilename)
				else
					filename = NetworkUtil.convertFromNetworkFilename(filename) -- expands "$moddir$"
					table.insert(mission.objects, {
						filename = Utils.getFilename(filename, g_currentMission.baseDirectory), -- removes $ at pos 1
						min = math.max(xmlFile:getInt(subKey .. "#min", 1), 1),
						max = math.min(xmlFile:getInt(subKey .. "#max", 1), 6),
						rewardScale = xmlFile:getFloat(subKey .. "#rewardScale", 1),
						size = string.getVectorN(xmlFile:getString(subKey .. "#size", "1 1 1"), 3),
						offset = string.getVectorN(xmlFile:getString(subKey .. "#offset", "0 0 0"), 3),
						title = getl10n(xmlFile, subKey .. "#title")
					})
				end
			end)
			table.insert(self.transportMissions, mission)
		end
	end)
	xmlFile:delete()
	return true
end
function TransportMission:readStream(streamId, connection)
	TransportMission:superClass().readStream(self, streamId, connection)
	self.pickup = streamReadString(streamId)
	self.dropoff = streamReadString(streamId)
	self.objectFilename = NetworkUtil.convertFromNetworkFilename(streamReadString(streamId))
	self.numObjects = streamReadUInt8(streamId)
	self.missionConfig = g_missionManager:getTransportMissionConfigById(streamReadUInt8(streamId))
	local trigger = fakeTrigger(self, self.pickup)
	debugPrint("** readStream transportMission %s(%s, %s): %s",self.missionConfig.name,
		self.pickup, self.dropoff, trigger)
	fakeTrigger(self, self.dropoff)
	if self.status == AbstractMission.STATUS_RUNNING then 

	end
end
function TransportMission:updateTriggerVisibility()
	local trigger = g_missionManager.transportTriggers[self.pickup]
	if trigger == nil then return end
	trigger:onMissionUpdated()
	trigger = g_missionManager.transportTriggers[self.dropoff]
	trigger:onMissionUpdated()
end
function TransportMission:getData()
	local pickup = self:getTriggerTitle(self.pickup, true)
	local dropoff = self:getTriggerTitle(self.dropoff, false)
	local desc = self.missionConfig.description
	if desc and desc:find("%s",1,true) then 
		if g_languageShort == "de" then 
			local pre = Trans.dePref[Trans.mapId][self.dropoff]
			if pre == nil then pre = "m" end
			desc = string.format(desc, pre, dropoff)
		else
			desc = string.format(desc, dropoff)
		end
	else
		desc = string.format(g_i18n:getText("fieldJob_desc_transporting_generic"),pickup, dropoff)
	end
	return {
		action = "",
		location = pickup,
		jobType = g_i18n:getText("fieldJob_jobType_transporting"),
		description = desc 
	}
end
function TransportMission:objectEnteredTrigger(trigger, objectId)
	if g_server and self.objects[objectId] ~= nil and 
		trigger == self:getDropoffTrigger() and self.objectsAtTrigger[objectId] ~= true then
		self.objectsAtTrigger[objectId] = true
		self.numFinished = self.numFinished + 1
	end
	debugPrint("** object %d entered Trigger %s. miss.objectsAtTrigger: ", 
		objectId, trigger.index)
	for id,v in pairs(self.objectsAtTrigger) do
		debugPrint("   %i: %s", id, v)
	end
end
function TransportMission:loadObjects()
	debugPrint("** TransportMission:loadObjects called for %s miss %s / %s",
		self.missionConfig.name ,self.id, self.objectFilename)
	for i,o in ipairs(self.missionConfig.objects) do
		debugPrint("%d: %s %s", i, o.filename, o.title)
	end
	local trigger = self:getPickupTrigger()
	debugPrint("   pickupTrigger id %s, index %s", trigger.triggerId, trigger.index)

	local objectConfig = nil
	for _, object in pairs(self.missionConfig.objects) do
		if object.filename == self.objectFilename then
			objectConfig = object
			break
		end
	end
	if objectConfig == nil then
		print("    * objectConfig is nil!")
		return false
	end
	debugPrint("   objectConfig.title: %s", objectConfig.title)
	local sizeX, _, sizeZ = unpack(objectConfig.size)
	local offX, _, offZ = unpack(objectConfig.offset)
	local rx, ry, rz = getWorldRotation(trigger.triggerId)
	local tx, ty, tz = getWorldTranslation(trigger.triggerId)
	local rowOffset = sizeZ / 2 + 0.3
	local xCellOffset = sizeX + 0.1
	local rcos = math.cos(ry)
	local rsin = math.sin(ry)
	Trans.draw = {
		triggerId = trigger.triggerId,
		sizeX = sizeX,
		sizeZ = sizeZ,
		nodes = {}
	}
	-- move trigger origin back to center of warning stripes:
	tx = tx + rsin*offZ + rcos*offX
	tz = tz + rcos*offZ - rsin*offX 
	debugPrint("   Trigger pos: %.1f, %.1f, %.1f, yrot %.1f / offset %.1f, %.1f/ rcos,rsin: %.2f, %.2f",
		tx, ty, tz, ry, offX, offZ, rcos,rsin)
	debugPrint("   callin isTriggerEmpty with (%s, %s)", sizeX, sizeZ)
	if not self:isTriggerEmpty(trigger, sizeX, sizeZ) then
		Logging.warning("[%s] * Pickup Trigger is not Empty. Could not start mission",Trans.name)
		Trans.drawTrigger = true
		return false
	end
	Trans.currentM = self 
	Trans.numToLoad = self.numObjects
	local dx, dz, dxS, dzS
	local location = {
		x =    tx,
		y =    ty,
		z =    tz,
		xRot = rx,
		yRot = ry,
		zRot = rz
	}
	--local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId).farmId
	for i = 1, self.numObjects do 	-- numObjects is max 6
		dxS = 0
		if i >= 5 then
			dxS = -xCellOffset
		elseif i >= 3 then
			dxS = xCellOffset
		end
		dzS = rowOffset
		if i % 2 == 0 then
			dzS = -rowOffset
		end
		dx = rsin * dzS + rcos * dxS
		dz = rcos * dzS - rsin * dxS
		--debugPrint("   object %d: %.1f, %.1f rot %.1f, %.1f, %.1f",
		--	i, tx + dx, tz + dz, rx, ry, rz)
		location.x = tx + dx 
		location.z = tz + dz 
		VehicleLoadingUtil.loadVehicle(objectConfig.filename, location, true, 0, 
			Vehicle.PROPERTY_STATE_OWNED, 0, nil, nil, 
			Trans.onPalletLoaded, Trans)
	end
	return true
end
function Trans:onPalletLoaded(pallet, loadState)
	self.numToLoad = self.numToLoad -1
	if loadState ~= VehicleLoadingUtil.VEHICLE_LOAD_OK then 
		local states = {"ok","VEHICLE_LOAD_ERROR","VEHICLE_LOAD_DELAYED","VEHICLE_LOAD_NO_SPACE"}
		debugPrint("** loadVehicle returns %s. numToLoad: %d", 
			states[loadState], self.numToLoad)
		return
	end	
	if pallet ~= nil then
		local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId).farmId
		local ft = pallet:getFillUnitFirstSupportedFillType(1)
		-- empty liquid tank, fillable pallets:
		if string.find(pallet.i3dFilename, "/liquidTank") or 
			string.find(pallet.i3dFilename, "/fillablePallet") or
			string.find(pallet.i3dFilename, "/grapePallet") then
			pallet.spec_fillUnit.removeVehicleIfEmpty = false
			pallet:addFillUnitFillLevel(farm, 1, -math.huge, ft, ToolType.UNDEFINED)
		-- prevent from selling elsewhere:
		elseif #pallet.spec_dischargeable.dischargeNodes > 0 then 
			pallet.spec_dischargeable.dischargeNodes[1].canDischargeToObject = false
			pallet.spec_dischargeable.dischargeNodes[1].canStartDischargeAutomatically = false
		-- fill it up:
			pallet:addFillUnitFillLevel(farm, 1, math.huge, ft, ToolType.UNDEFINED)
		end
		-- store in current transport mission:
		Trans.currentM.objects[pallet.rootNode] = pallet
		debugPrint("* pallet %d loaded. Owner: %d",pallet.rootNode, pallet.ownerFarmId)
	end
	if self.numToLoad <= 0 then 
		debugPrint("** all pallets loaded for current transport mission")
	end
end
function TransportMission:saveToXMLFile(xmlFile, key)
	TransportMission:superClass().saveToXMLFile(self, xmlFile, key)
	setXMLInt(xmlFile, key .. "#timeLeft", self.timeLeft)
	setXMLString(xmlFile, key .. "#config", self.missionConfig.name)
	setXMLString(xmlFile, key .. "#pickupTrigger", self.pickup)
	setXMLString(xmlFile, key .. "#dropoffTrigger", self.dropoff)
	setXMLString(xmlFile, key .. "#objectFilename", HTMLUtil.encodeToHTML(NetworkUtil.convertToNetworkFilename(self.objectFilename)))
	setXMLInt(xmlFile, key .. "#numObjects", self.numObjects)
	local index = 0
	for _, pal in pairs(self.objects) do  -- only is mission was active on savegame
		local objectKey = string.format("%s.object(%d)", key, index)
		setXMLInt(xmlFile, objectKey.."#savegameId", pal.currentSavegameId)
		index = index + 1
	end
end
function TransportMission:loadFromXMLFile(xmlFile, key)
	if not TransportMission:superClass().loadFromXMLFile(self, xmlFile, key) then
		return false
	end
	self.timeLeft = getXMLInt(xmlFile, key .. "#timeLeft")
	local name = getXMLString(xmlFile, key .. "#config")
	self.missionConfig = g_missionManager:getTransportMissionConfig(name)
	if self.missionConfig == nil then
		return false
	end
	self.pickup = getXMLString(xmlFile, key .. "#pickupTrigger")
	self.dropoff = getXMLString(xmlFile, key .. "#dropoffTrigger")
	self.objectFilename = NetworkUtil.convertFromNetworkFilename(getXMLString(xmlFile, key .. "#objectFilename"))
	self.numObjects = getXMLInt(xmlFile, key .. "#numObjects")
	if self.status == AbstractMission.STATUS_RUNNING then
		local i, id, pal = 0
		while true do
			local objectKey = string.format("%s.object(%d)", key, i)
			if not hasXMLProperty(xmlFile, objectKey) then
				break
			end
			id = getXMLInt(xmlFile, objectKey.."#savegameId")
			pal = g_currentMission.vehicles[id]
			if pal and pal.typeName == "pallet" then 
				self.objects[pal.rootNode] = pal 
				if #pal.spec_dischargeable.dischargeNodes > 0 then 
					pal.spec_dischargeable.dischargeNodes[1].canDischargeToObject = false
					pal.spec_dischargeable.dischargeNodes[1].canStartDischargeAutomatically = false
				end
			else
				Logging.warning("[%s] could not find pallet mission object with savegameId %d",
					id)
			end
			i = i + 1

		end
	end
	local pickupTrigger = self:getPickupTrigger()
	local dropoffTrigger = self:getDropoffTrigger()
	if pickupTrigger == nil or dropoffTrigger == nil then
		return false
	end
	pickupTrigger:setMission(self)
	dropoffTrigger:setMission(self)
	return true
end
function TransportMissionTrigger.new(id, index, isClient)
	debugPrint("**transportTriggerNew %s, %s",id, index)
	local self = {}
	setmetatable(self, Class(TransportMissionTrigger))

	self.triggerId = id
	self.isClient = Utils.getNoNil(isClient, false)
	if index then
		self.index = index 
		g_currentMission:addNonUpdateable(self)
	else 	-- we were called by TransportMissionTrigger:onCreate()
		self.index = getUserAttribute(id, "index")
	end
	addTrigger(id, "triggerCallback", self)
	self.isEnabled = true

	g_missionManager:addTransportMissionTrigger(self)
	self:setMission(nil)
	return self
end
function TransportMissionTrigger:onMissionUpdated()
	if not self.isClient then return end
	
	local state = self.mission ~= nil and self.mission.status == AbstractMission.STATUS_RUNNING
	local isMyFarm = state and self.mission.farmId == g_currentMission:getFarmId()
	--debugPrint("* set visibility for %s/%s to %s",self.index, self.triggerId, state)
	
	local tr = g_currentMission.nodeToObject[self.triggerId]
	if tr ~= nil then tr:setVisibility(state) end

	if self.mission and self.mission:hasHotspots() then
		self.mission.pickupHotspot:setVisible(isMyFarm)
		self.mission.dropoffHotspot:setVisible(isMyFarm)
	end
end
