--!strict
local _Package = script
local _Packages = _Package.Parent
-- Services
local Stats = game:GetService("Stats")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MemoryStoreService: MemoryStoreService = require(_Packages:WaitForChild("MockMemoryStoreService"))
-- Packages
local Maid = require(_Packages:WaitForChild("Maid"))
local Signal = require(_Packages:WaitForChild("Signal"))
-- Modules
-- Types
type Signal = Signal.Signal
type Maid = Maid.Maid
-- Constants
local SERVER_REGISTRY_EXPIRATION = 60

-- Variables
-- References
-- Private Functions
function getServerUsageScore(): number
	local bandwidthUsage = Stats.DataSendKbps + Stats.DataReceiveKbps
	local playerCount = #Players:GetPlayers()
	if playerCount > 0 then
		return bandwidthUsage / playerCount
	else
		return 1000000000000
	end
end

-- Class
local Util = {}

function Util.connectUniversalJob(
	path: string,
	interval: number,
	job: () -> ()
):RBXScriptConnection
	local serverRegistryMap = MemoryStoreService:GetSortedMap(path)
	serverRegistryMap:SetAsync(
		game.JobId,
		getServerUsageScore(),
		SERVER_REGISTRY_EXPIRATION
	)

	local lastUpdate = 0
	return RunService.Heartbeat:Connect(function(deltaTime: number)
		if tick() - lastUpdate >= interval then
			lastUpdate = tick()

			local isChosenOne = false
			local success, msg = pcall(function()
				local results = serverRegistryMap:GetRangeAsync(
					Enum.SortDirection.Ascending,
					1
				)
				if #results == 1 then
					local key = results[1]
					assert(typeof(key) == "string")
					if key == game.JobId then
						isChosenOne = true
					end
				end
			end)

			if not success then
				warn(msg)
			end
			if isChosenOne then
				job()
			end
		end
	end)
end

function Util.getDeltaSignal<T>(
	readMethod: () -> T,
	interval: number
): Signal

	local signal = Signal.new()
	task.spawn(function()
		local initialValue = readMethod()
		local loopEnabled = true
		repeat
			task.wait(interval)
			local readSuccess, readMsg = pcall(function()
				local value = readMethod()
				if value ~= initialValue then
					initialValue = value
					local success, _msg = pcall(function()
						signal:Fire(value)
					end)
					if not success then
						loopEnabled = false
					end
				end
			end)
			if readSuccess then
				warn(readMsg)
			end
		until not loopEnabled
	end)

	return signal
end

return Util