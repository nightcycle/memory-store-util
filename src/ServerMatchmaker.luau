--!strict
local _Package = script.Parent
local _Packages = _Package.Parent
-- Services
local RunService = game:GetService("RunService")
local MemoryStoreService = require(_Packages:WaitForChild("MockMemoryStoreService"))
local MessagingService = require(_Packages:WaitForChild("MockMessagingService"))

-- Packages
local Maid = require(_Packages:WaitForChild("Maid"))
local Signal = require(_Packages:WaitForChild("Signal"))
local CompressionUtil = require(_Packages:WaitForChild("CompressionUtil"))
local TableUtil = require(_Packages:WaitForChild("TableUtil"))

-- Modules
local Util = require(_Package:WaitForChild("Util"))

-- Types
type Signal = Signal.Signal
type Maid = Maid.Maid
type SubscriptionData = 	{
	Data: any?,
	Sent: number,
}

-- Constants
local DEFAULT_INVISIBILITY_TIMEOUT = 30

-- Variables
-- References
-- Private Functions
function getStartedTopicName(name: string, jobId: string)
	return `MSU_NEW_MATCH_{name}_{jobId}`
end
function getUpdatedTopicName(name: string, jobId: string)
	return `MSU_MATCH_UPDATE_{name}_{jobId}`
end
function getFinishTopicName(name: string, jobId: string)
	return `MSU_MATCH_FINISH_{name}_{jobId}`
end
function getQueueName(name: string)
	return `MSU_SERVER_MATCHMAKE_QUEUE_{name}`
end

function processQueueAsync(name: string, goalSize: number, registerMatch: (matchId: string, userIds: { [number]: number }) -> ()): ()
	local queue = MemoryStoreService:GetQueue(getQueueName(name), DEFAULT_INVISIBILITY_TIMEOUT)

	local registry: { [number]: string } = {}

	local isComplete = false

	repeat
		Util.processQueueItemAsync(queue, function(data: string?)
			-- print("processing data: ", data)
			if data == nil then
				isComplete = true
			else
				local jobId, encodedUserIdArray = string.unpack("ss", data)
				local userIds = CompressionUtil.decodeIntegerArray(encodedUserIdArray)
				for i, userId in ipairs(userIds) do
					registry[userId] = jobId
				end
				-- print(`process result: {#userIds == 0}, {#userIds >= goalSize}`)
				if #userIds >= goalSize then
					isComplete = true
					-- print("\n\n\n\nComplete!\n\n\n\n")
				end
			end
		end)
	until isComplete

	-- print("out!")

	local userIds = TableUtil.keys(registry)
	local serverJobIds = TableUtil.deduplicate(TableUtil.values(registry))

	if #userIds > 0 then
		local matchId = CompressionUtil.encodeStringArray(serverJobIds)
		registerMatch(matchId, userIds)

		for i, jobId in ipairs(serverJobIds) do
			MessagingService:PublishAsync(getStartedTopicName(name, game.JobId), matchId)
		end
	end
end

-- Class
-- Types
export type ServerMatchmaker = {
	__index: ServerMatchmaker,
	_Maid: Maid,
	_IsAlive: boolean,
	_Name: string,
	_CurrentMatchId: string?,
	_GoalMatchSize: number,
	_QueueProcessingInterval: number,
	_RegisterMatchProcess: (matchId: string, userIds: { [number]: number }) -> (),
	_OnMatchStartInvoke: (matchId: string) -> (),
	_OnMatchUpdateInvoke: (matchId: string) -> (),
	_OnMatchCompleteInvoke: (matchId: string) -> (),
	Destroy: (self: ServerMatchmaker) -> (),
	RegisterUsers: (self: ServerMatchmaker, userIds: { [number]: number }) -> (),
	GetIfStarted: (self: ServerMatchmaker) -> boolean,
	FireUpdate: (self: ServerMatchmaker) -> (),
	FireCompletion: (self: ServerMatchmaker) -> (),
	new: (
		name: string,
		queueProcessingInterval: number,
		goalMatchSize: number,
		registerMatchProcess: (matchId: string, userIds: { [number]: number }) -> (),
		onMatchStartInvoke: (matchId: string) -> (),
		onMatchUpdateInvoke: (matchId: string) -> (),
		onMatchCompleteInvoke: (matchId: string) -> ()
	) -> ServerMatchmaker,
	init: (maid: Maid) -> nil,
}

-- Class
local ServerMatchmaker = {} :: ServerMatchmaker
ServerMatchmaker.__index = ServerMatchmaker

function ServerMatchmaker:Destroy()
	if not self._IsAlive then
		return
	end
	self._IsAlive = false
	self._Maid:Destroy()
	local t: any = self
	for k, v in pairs(t) do
		t[k] = nil
	end
	setmetatable(t, nil)
end

function ServerMatchmaker:RegisterUsers(userIds: { [number]: number })
	local queue = MemoryStoreService:GetQueue(getQueueName(self._Name), DEFAULT_INVISIBILITY_TIMEOUT)

	Util.escalatingRepeatAsync(function()
		local value = string.pack("ss", game.JobId, CompressionUtil.encodeIntegerArray(userIds))
		-- print("attempting to add: ", value)
		return queue:AddAsync(value, self._QueueProcessingInterval + 60)
	end)
end

function ServerMatchmaker:GetIfStarted(): boolean
	return self._CurrentMatchId ~= nil
end

function ServerMatchmaker:FireUpdate(): ()
	if not self:GetIfStarted() then
		return
	end
	local matchId = self._CurrentMatchId
	assert(matchId)
	for i, jobId in ipairs(CompressionUtil.decodeStringArray(matchId)) do
		MessagingService:PublishAsync(getUpdatedTopicName(self._Name, jobId), matchId)
	end
end

function ServerMatchmaker:FireCompletion(): ()
	if not self:GetIfStarted() then
		return
	end
	local matchId = self._CurrentMatchId
	assert(matchId)
	for i, jobId in ipairs(CompressionUtil.decodeStringArray(matchId)) do
		MessagingService:PublishAsync(getFinishTopicName(self._Name, jobId), matchId)
	end
end

function ServerMatchmaker.new(
	name: string,
	queueProcessingInterval: number,
	goalMatchSize: number,
	registerMatchProcess: (matchId: string, userIds: { [number]: number }) -> (),
	onMatchStartInvoke: (matchId: string) -> (),
	onMatchUpdateInvoke: (matchId: string) -> (),
	onMatchCompleteInvoke: (matchId: string) -> ()
): ServerMatchmaker
	local self: ServerMatchmaker = setmetatable({}, ServerMatchmaker) :: any
	self._IsAlive = true
	self._Maid = Maid.new()
	self._Name = name
	self._CurrentMatchId = nil
	self._QueueProcessingInterval = queueProcessingInterval
	self._GoalMatchSize = goalMatchSize
	self._RegisterMatchProcess = registerMatchProcess
	self._OnMatchStartInvoke = onMatchStartInvoke
	self._OnMatchUpdateInvoke = onMatchUpdateInvoke
	self._OnMatchCompleteInvoke = onMatchCompleteInvoke

	self._Maid:GiveTask(MessagingService:SubscribeAsync(getStartedTopicName(name, game.JobId), function(matchData: SubscriptionData)
		local matchId = matchData.Data
		assert(matchId)
		assert(self._CurrentMatchId == nil)
		self._CurrentMatchId = matchId
		self._OnMatchStartInvoke(matchId)
	end))
	self._Maid:GiveTask(MessagingService:SubscribeAsync(getFinishTopicName(name, game.JobId), function(matchData: SubscriptionData)
		local matchId = matchData.Data
		assert(matchId)
		assert(matchId == self._CurrentMatchId)
		self._OnMatchUpdateInvoke(matchId)
	end))
	self._Maid:GiveTask(MessagingService:SubscribeAsync(getUpdatedTopicName(name, game.JobId), function(matchData: SubscriptionData)
		local matchId = matchData.Data
		assert(matchId)
		assert(matchId == self._CurrentMatchId)
		self._CurrentMatchId = nil
		self._OnMatchCompleteInvoke(matchId)
	end))

	local function getNextProcessTimestamp(): number
		local now = DateTime.now().UnixTimestamp
		return now - (now % queueProcessingInterval) + queueProcessingInterval
	end
	local nextProcessTimestamp = getNextProcessTimestamp()

	self._Maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime: number)
		-- print(`heartbeat {nextProcessTimestamp} vs now {DateTime.now().UnixTimestamp}`)
		if nextProcessTimestamp < DateTime.now().UnixTimestamp and self._CurrentMatchId == nil then
			-- print("process")
			nextProcessTimestamp = getNextProcessTimestamp()
			processQueueAsync(self._Name, self._GoalMatchSize, self._RegisterMatchProcess)
		end
	end))

	return self
end

return ServerMatchmaker
