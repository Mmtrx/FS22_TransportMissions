--=======================================================================================================
-- TransportMissions SCRIPT
--
-- Purpose:     Enable simple transport missions.
-- Author:      Mmtrx
-- Changelog:
--  v1.0.0.0    09.02.2022  initial 
--  v1.0.1.0 	28.04.2022  Waldstetten special
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
function Trans:testEmpty(id)
	-- call overlapBox() with std trigger sizes around node id
	local rx, ry, rz = getWorldRotation(tonumber(id))
	local tx, ty, tz = getWorldTranslation(tonumber(id))
	local height = TransportMission.TEST_HEIGHT *0.5
	ty = ty + height - 0.5

	self.tempHasCollision = false
	local nc = overlapBox(tx, ty, tz, rx, ry, rz, 1.5 * (1.7 + 0.1), height, 
		1 * (2 + 0.1), "collision", self, 537087)
	if self.tempHasCollision then 
		return string.format("triggerbox has %d collisions", nc)
	else
		return "clear"
	end
end
function Trans:collision(transformId)
	if g_currentMission.nodeToObject[transformId] ~= nil or g_currentMission.players[transformId] ~= nil or g_currentMission:getNodeObject(transformId) ~= nil then
		self.tempHasCollision = true
		debugPrint("      nodeToObject[%d] = %s. players[] = %s. i3dFile = %s",
		transformId, 
		g_currentMission.nodeToObject[transformId], g_currentMission.players[transformId],
		g_currentMission:getNodeObject(transformId).i3dFilename:sub(-20))
		table.insert(Trans.draw.nodes, transformId)
	end
end
function TransportMission:isTriggerEmpty(trigger, objectSizeX, objectSizeZ)
	local rx, ry, rz = getWorldRotation(trigger.triggerId)
	local tx, ty, tz = getWorldTranslation(trigger.triggerId)
	local height = TransportMission.TEST_HEIGHT *0.5
	ty = ty + height - 0.5

	self.tempHasCollision = false
	overlapBox(tx, ty, tz, rx, ry, rz, 1.5 * (objectSizeX + 0.1), height, 
		1 * (objectSizeZ + 0.1), "collisionTestCallback", self, 537087)
	return not self.tempHasCollision
end
function collisionTestCallback(self,superf, transformId)
	if self.mission.nodeToObject[transformId] ~= nil or self.mission.players[transformId] ~= nil or self.mission:getNodeObject(transformId) ~= nil then
		self.tempHasCollision = true
		debugPrint("      nodeToObject[%d] = %s. players[] = %s. i3dFile = %s",
		transformId, 
		self.mission.nodeToObject[transformId], self.mission.players[transformId],
		self.mission:getNodeObject(transformId).i3dFilename:sub(-20))
		table.insert(Trans.draw.nodes, transformId)
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
		print(string.format("** %s %s loaded. id/ node: %d/ %d",self.typeName, 
			self.i3dFilename:sub(-15), self.id, self.rootNode ))
	end
end
