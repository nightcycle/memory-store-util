--!strict
local _Package = script.Parent
local _Packages = _Package.Parent
-- Services
-- Packages
local Maid = require(_Packages:WaitForChild("Maid"))
local Signal = require(_Packages:WaitForChild("Signal"))

-- Modules
-- Types
type Signal = Signal.Signal
type Maid = Maid.Maid

-- Constants
local DEFAULT_TIMEOUT = 30
local FAIL_DELAY = 1

-- Variables
-- References
-- Private Functions

-- Class
local Util = {}

function Util.escalatingRepeatAsync<T>(process: () -> T, failCount: number?): T
	failCount = failCount or 0
	assert(failCount)

	local out: T
	local success, msg = pcall(function()
		out = process()
	end)
	if success then
		return out
	else
		local interval = 2 ^ failCount
		warn(msg)
		warn(`process failed, waiting {interval}`)
		task.wait(interval)
		return Util.escalatingRepeatAsync(process, failCount + 1)
	end
end

function Util.processQueueItemAsync<T>(queue: MemoryStoreQueue, processor: (data: T?) -> (), timeout: number?): boolean
	local readId: string
	local items: { [number]: T } = {}
	local readSuccess, readMessage = pcall(function()
		items, readId = queue:ReadAsync(1, false, timeout or DEFAULT_TIMEOUT)
	end)
	if not readSuccess then
		warn(readMessage)
		task.wait(FAIL_DELAY)
	elseif #items >= 0 then
		local item = items[1]
		if item then
			assert(item ~= nil)

			local removeSuccess, removeError = pcall(function()
				queue:RemoveAsync(readId)
			end)
			if not removeSuccess then
				warn(removeError)
			else
				processor(item)
				return true
			end
		else
			processor(nil)
			return true
		end
	
		
	end
	return false
end

return Util
