--=======================================================================================================
-- TransportMissions SCRIPT
--
-- Purpose:     Enable simple transport missions.
-- Author:      Mmtrx
-- Changelog:
--  v1.0.0.0    09.02.2022  initial 
--======================================================================================
function debugPrint(text, ...)
	if Trans.debug then
		Logging.info(text,...)
	end
end
------------------ Test functions -----------------------------------------
function Trans:testVis(index, on)
	-- toggle visibility of a placeable
	local state = on ~= nil 
	g_currentMission.placeableSystem.placeables[tonumber(index)]:setVisibility(state)
end
function Trans:showTriggers()
	for i,u in ipairs(g_currentMission.nonUpdateables) do
		debugPrint("%3d %s",i, ClassUtil.getClassName(u))
	end
end
function Trans:makeTransport(index, iobj)
	-- generate transport mission with specified pickup trigger, 
	-- and (optional) object index
	if not index or index == "" then 
		print("** specify pickup trigger index")
		return
	elseif g_missionManager.transportTriggers[index] == nil then 
		print("** "..index.." not found in transportTriggers")
		return
	end
	local pickupTr = g_missionManager.transportTriggers[index]
	if pickupTr.mission then 
		print("** trigger already has a mission")
		return
	end
	local mission = TransportMission.new(true, g_client ~= nil)
	mission.type = g_missionManager.possibleTransportMissionsWeighted[1]
	mission:register()
	pickupTr:setMission(mission)

	-- find mission definition with this pickupTr
	local found, tMission = false
	for _,trm in ipairs(g_missionManager.transportMissions) do
		for _,tr in ipairs(trm.pickupTriggers) do
			if tr.index == index then 
				found = true
				break
			end
		end
		if found then 
			tMission = trm
			break 
		end
	end
	if tMission == nil then 
		return "** could not find a mission definition with this pickup"
	end
	-- find dropoff trigger
	local dropoff 
	for i = 1, table.getn(tMission.dropoffTriggers) do
		local item = tMission.dropoffTriggers[i]
		local trigger = g_missionManager.transportTriggers[item.index]
		if trigger ~= nil and trigger.mission == nil then
			dropoff = item
			trigger:setMission(mission)
			break
		end
	end
	if dropoff == nil then 
		mission:delete()
		print("** could not find a free dropoff trigger")
		return 
	end
	local object
	if iobj and tonumber(iobj) and tonumber(iobj) <= #tMission.objects then 
		object = tMission.objects[tonumber(iobj)]
	else
		object = table.getRandomElement(tMission.objects)
	end
	mission.numObjects = 6
	mission.pickup = index
	mission.dropoff = dropoff.index
	mission.objectFilename = object.filename
	mission.missionConfig = tMission
	mission.timeLeft = TransportMission.CONTRACT_DURATION
	mission.reward = 5555
	table.insert(g_missionManager.missions, mission)
	g_missionManager.numTransportMissions = g_missionManager.numTransportMissions +1
	g_messageCenter:publish(MessageType.MISSION_GENERATED)
	return "** mission generated **"
end
function collisionTestCallback(self,superf, transformId)
	if self.mission.nodeToObject[transformId] ~= nil or self.mission.players[transformId] ~= nil or self.mission:getNodeObject(transformId) ~= nil then
		self.tempHasCollision = true
		debugPrint("      nodeToObject[%d] = %s. players[] = %s. :getNodeObject() = %s",
		transformId, 
		self.mission.nodeToObject[transformId], self.mission.players[transformId],
		self.mission:getNodeObject(transformId))
	end
end
function createObject( self, superf, x, y, z, rx, ry, rz )
	debugPrint("** :createObject called with %s, %s, %s, %s, %s, %s",
		x, y, z, rx, ry, rz)
	local transportObject = MissionPhysicsObject.new(self.mission:getIsServer(), self.mission:getIsClient())
	local r = transportObject:load(self.objectFilename, x, y, z, rx, ry, rz)
	debugPrint("   load() filename %s. object: %s returns %s", self.objectFilename, transportObject, r)
end
function look(self)
	if g_currentMission.isMissionStarted then
		print(string.format("** %s %s loaded. id: %s",self.typeName, self.i3dFilename:sub(-15), self.id ))
	end
end
