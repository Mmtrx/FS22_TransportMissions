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
InitRoyalUtility(Utils.getFilename("lib/utility/", g_currentModDirectory))
InitRoyalMod(Utils.getFilename("lib/rmod/", g_currentModDirectory))
Trans = RoyalMod.new(false, true)     --params bool debug, bool sync
source(Utils.getFilename("tmission.lua", Trans.directory))
source(Utils.getFilename("debug.lua", Trans.directory))

function Trans:initialize()
	debugPrint("[%s] initialize(): %s", self.name,self.initialized)
	if self.initialized ~= nil then return end -- run only once

	-- check for debug switch in modSettings/
	self.modSettings= getUserProfileAppPath().."modSettings/"
	if not self.debug and      
		fileExists(self.modSettings.."Trans.debug") then
		self.debug = true 
	end
	if g_modIsLoaded["FS22_BetterContracts"] then
		self.betterContracts = true
	else
	-- fix AbstractMission: 
		Utility.overwrittenFunction(AbstractMission, "new", abstractMissionNew)
	-- to allow multiple missions:
		MissionManager.hasFarmReachedMissionLimit =
		Utils.overwrittenFunction(nil, function() return false end)
	end
	self.isModMap = false 
	self.maps = { 				 -- max transport missions
		MapUS = {dir = "mapUS/", num = 6},
		-- as long as HautB. and Erlengrat not ready:
		MapFR = {dir = "mapFR/", num = 8}, 					-- mapFR/
		mapAlpine = {dir = "mapAlpine/", num = 4},			-- mapAlpine/
		Waldstetten = {dir = "Waldstetten/", num = 8},	
	}
	-- Todo: adjust for other 2 maps
	self.dePref = { 		-- German prepositions for female (or no prep) names 
		MapUS = {			--  for US map triggers
			TRANS01 = " der", 	-- Mühle
			TRANS05 = " der", 	-- Weberei
			TRANS08 = " der", 	-- Tankstelle
			TRANS09 = " der", 	-- BGA
			TRANS10 = " der", 	-- Bäckerei
			TRANS11 = " der", 	-- Öl-Mühle
			TRANS14 = "", 		-- Futter Süd
			TRANS15 = " der" 	-- Meierei
		},
		Waldstetten = {
			TRANS06 = " der", 	-- bakery" 
			TRANS07 = " der", 	-- gasstation
			TRANS10 = " der", 	-- pizza" 		
			TRANS12 = " der", 	-- pigfarm" 
			TRANS13 = " der", 	-- refinery" 
			TRANS15 = " der", 	-- restarea" 
			TRANS16 = " der", 	-- raisinplant
			TRANS20 = " der", 	-- liftstation
			TRANS22 = " der", 	-- sugarmill"
			TRANS27 = " der", 	-- spinnery" 
			TRANS28 = " der", 	-- roadbuchen
			TRANS29 = " der", 	-- bga" 		
		}
	}
	self.triggers = {} 		-- save relation between placeable and trigger index
	self.usedTriggers = {} 	-- keep index names of not yet created triggers 
	self.numTriggers = 0  	-- # of loaded placeables with transport triggers
	self.seenTriggers = 0 	-- # of already loaded placeables on client, after join game
	self.LOADED_MY_PLACEABLES = 1001 	-- my own message id
	self.draw = {} 			-- debug draw a trigger colli check cube

	-- to save our self.placsLoaded switch: 
	Utility.appendedFunction(PlaceableSystem, "saveToXML", placSaveXML)
	Utility.appendedFunction(TransportMission, "createHotspots", createHotspots)
	Utility.appendedFunction(Placeable, "onFinishedLoading", placeableOnFinishedLoading)

	if self.debug then 
	-- test prints:
		Utility.appendedFunction(Placeable, "finalizePlacement", look)
		Utility.overwrittenFunction(TransportMission, "collisionTestCallback", collisionTestCallback)
        addConsoleCommand("makeTransport", "[index] [(opt) object]- generate a transport mission with specified pickup trigger and (optional) object nr", "makeTransport", self)
        addConsoleCommand("testEmpty", "[nodeId] - test for objects in overlapBox", "testEmpty", self)
        addConsoleCommand("testVis", "[index] - toggle visibility of placeable[index]", "testVis", self)
        addConsoleCommand("showTriggers", "list nonUpdateables by Class", "showTriggers", self)
    end
    -- call our load function after all placeables are loaded
	g_messageCenter:subscribe(MessageType.LOADED_ALL_SAVEGAME_PLACEABLES, self.load, self)
	g_messageCenter:subscribe(self.LOADED_MY_PLACEABLES, self.clientLoad, self, nil, true)
	self.initialized = true
end
function Trans:onMissionInitialize(baseDirectory, missionCollaborators)
	MissionManager.AI_PRICE_MULTIPLIER = 1.5
	MissionManager.MISSION_GENERATION_INTERVAL = 3600000 -- every 1 game hour
	TransportMission.REWARD_PER_METER = 1
	TransportMission.TEST_HEIGHT = 3
end
function Trans:onPostLoadMap(mapNode, mapFile)
	-- check for correct map
	local map = g_currentMission.missionInfo.map
	local mapId = map.id
	if mapId:find("FS22_Waldstetten") then mapId = "Waldstetten" end
	local mapDir = self.maps[mapId] and self.maps[mapId].dir
	local shut = false 
	debugPrint("[%s] mapId: %s, mapDir: %s, isMod: %s", self.name, map.id, mapDir, map.isModMap)
	
	if not mapDir then 
		Logging.error("[%s] does not work for mod maps. Mod will shut down.", self.name)
		g_gui:showInfoDialog({
			text = string.format("%s does not work with this mod map. Please start a game with one of the standard maps.", self.name)
		})
		shut = true
	else
		self.mapDir = self.directory..mapDir
		self.mapId = mapId
		shut = not fileExists(Utils.getFilename("placeables.xml",self.mapDir))
		if shut then 
			local txt = string.format("%s does not work for %s yet. Mod will shut down.", 
				self.name,mapId)
			Logging.error(txt)
			g_gui:showInfoDialog({text = txt})
		end
	end
	if shut then
		g_messageCenter:unsubscribeAll(self)
		removeModEventListener(self.super)
		return
	end

	-- adjust max missions
	if g_server then
		MissionManager.MAX_TRANSPORT_MISSIONS = self.maps[mapId].num 
		MissionManager.MAX_MISSIONS = MissionManager.MAX_MISSIONS + MissionManager.MAX_TRANSPORT_MISSIONS -- add max transport missions to max missions
		MissionManager.MAX_MISSIONS_PER_GENERATION = math.min(MissionManager.MAX_MISSIONS / 5, 30) -- max missions per generation = max mission / 5 but not more then 30
		MissionManager.MAX_TRIES_PER_GENERATION = math.ceil(MissionManager.MAX_MISSIONS_PER_GENERATION * 1.5) -- max tries per generation 50% more then max missions per generation
	end
	debugPrint("[%s] MAX_MISSIONS set to %s", self.name, MissionManager.MAX_MISSIONS)
	debugPrint("[%s] MAX_TRANSPORT_MISSIONS set to %s", self.name, MissionManager.MAX_TRANSPORT_MISSIONS)
	debugPrint("[%s] MAX_MISSIONS_PER_GENERATION set to %s", self.name, MissionManager.MAX_MISSIONS_PER_GENERATION)
	debugPrint("[%s] MAX_TRIES_PER_GENERATION set to %s", self.name, MissionManager.MAX_TRIES_PER_GENERATION)
end
function Trans:onDraw()
	-- draw debug cube, if trigger not empty
	if not self.drawTrigger then return end

	local rx, ry, rz = getWorldRotation(self.draw.triggerId)
	local tx, ty, tz = getWorldTranslation(self.draw.triggerId)
	local height = TransportMission.TEST_HEIGHT *0.5
	ty = ty + height - 0.5
	DebugUtil.drawDebugNode(self.draw.triggerId, "trigger", false, 1)
	DebugUtil.drawOverlapBox(tx,ty,tz, rx,ry,rz, 1.5* (self.draw.sizeX +0.1), height,
	 (self.draw.sizeZ +0.1))
	for _,v in ipairs(self.draw.nodes) do
		DebugUtil.drawDebugNode(v, tostring(v), false, 1)
	end
end
function Trans:onWriteStream(streamId)
	-- write to a client when it joins
	local num = g_missionManager.numTransportTriggers
	debugPrint("** writing %d transportTriggers:", num)
	streamWriteUInt8(streamId, num)
	for id,t in pairs(self.triggers) do
		NetworkUtil.writeNodeObjectId(streamId, id)
		streamWriteString(streamId, self.triggers[id])
	end
end
function Trans:onReadStream(streamId)
	-- client reads our triggers array when it joins
	self.numTriggers = streamReadUInt8(streamId)
	debugPrint("** reading %d transportTriggers:", self.numTriggers)
	local triggerId, id, p 
	for i = 1, self.numTriggers do
		id = NetworkUtil.readNodeObjectId(streamId)
		self.triggers[id] = streamReadString(streamId)
	end
end
function Trans:load()
	local g = g_currentMission
    if g:getIsServer() then
		if g.missionInfo.placeablesXML then 
			local xml = loadXMLFile("plac", g.missionInfo.placeablesXML)
			self.placsLoaded = Utils.getNoNil(getXMLBool(xml, "placeables#transport"), false)
			delete(xml)
		else
			Logging.warning("[%s] could not find placeables.xml in savegame. Maybe new map start.",self.name)
		end	
		-- load our placeables if not already in savegame, and insert triggers
		if not self.placsLoaded then 
			self:loadPlaceables(Utils.getFilename("placeables.xml",self.mapDir)) -- also calls loadTriggers()
			self.placsLoaded = true
		else 
			self:loadTriggers()
		end
	end
	-- load our transport mission definitions (on server and on client)
	g_missionManager:loadTransportMissions(Utils.getFilename("transportMissions.xml", self.mapDir))
end
function Trans:loadPlaceables(filename) 
	-- load our transp trigger placeables
	local g = g_currentMission
	debugPrint("** load my placeables from %s: **", filename)
	g.placeableSystem:load(filename, 
		g.missionInfo.defaultPlaceablesXMLFilename, 
		g.missionInfo, g.missionDynamicInfo,
		self.loadTriggers, self) 
end
function Trans:loadTriggers()
	debugPrint("** loadTriggers() on Server, g_client: %s",g_client)
	local index = 1
	for _, p in ipairs(g_currentMission.placeableSystem.placeables) do
		if p.baseDirectory == self.directory then
			local node = p.i3dMappings.trigger.nodeId
			local txt = string.format("TRANS%02d",index)
			-- only needed when defining new trigger places:
			if #p.spec_hotspots.mapHotspots > 0 then 
				if p.name then
					p.spec_hotspots.mapHotspots[1].name = name  
				else
					p.spec_hotspots.mapHotspots[1].name = txt 
				end
			end
			TransportMissionTrigger.new(node, txt, g_dedicatedServer == nil)
			if g_currentMission.missionDynamicInfo.isMultiplayer then 
				self.triggers[g_server:getObjectId(p)] = txt -- save for writestream to client
			end
			p:setVisibility(false)		-- start invisible
			index = index +1
		end
	end
end
function Trans:clientLoad()
	debugPrint("** %s loaded all transport triggers **", self.name)
end
-- overwritten / appended -------------------------------------------------
function placeableOnFinishedLoading(p)
	if g_currentMission:getIsServer() then return end
	
	-- for client in an MP game: recreate local triggers for each of our placeables
	if p.baseDirectory == Trans.directory then 
		-- just created a  trigger placeable on client. 
		p:setVisibility(false)
		local node = p.i3dMappings.trigger.nodeId
		local objId = g_client:getObjectId(p)
		local index = Trans.triggers[objId]
		local tr = TransportMissionTrigger.new(node, index, true)
		local m = Trans.usedTriggers[index]
		if m then 
			tr:setMission(m)
			p:setVisibility(m.status == AbstractMission.STATUS_RUNNING)
		end		 
		Trans.seenTriggers = Trans.seenTriggers +1
		if Trans.seenTriggers >= Trans.numTriggers then 
			g_messageCenter:publish(Trans.LOADED_MY_PLACEABLES)
		end
	end
end
function createHotspots(self)
	self.pickupHotspot:setBlinking(true)
	self.pickupHotspot:setOwnerFarmId(self.farmId)
	self.dropoffHotspot:setOwnerFarmId(self.farmId)
end
function placSaveXML(pSystem, xmlFile, usedModNames)
	-- record our switch in savegame/placeables.xml
	xmlFile:setBool("placeables#transport", Trans.placsLoaded or false)
	xmlFile:save()
end
function abstractMissionNew(isServer, superf, isClient, customMt )
	local self = superf(isServer, isClient, customMt)
	self.mission = g_currentMission 
	-- Fix for error in AbstractMission 'self.mission' still missing in Version 1.3
	return self
end
