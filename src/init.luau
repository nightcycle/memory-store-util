--!strict
local _Package = script
local _Packages = _Package.Parent
-- Services
-- Packages
local Maid = require(_Packages:WaitForChild("Maid"))
local Signal = require(_Packages:WaitForChild("Signal"))

-- Modules
local ServerMatchmaker = require(_Package:WaitForChild("ServerMatchmaker"))
local Util = require(_Package:WaitForChild("Util"))
-- Types
type Signal = Signal.Signal
type Maid = Maid.Maid

-- Constants


-- Variables
-- References
-- Private Functions


-- Class
local MSUtil = {}

MSUtil.ServerMatchmaker = ServerMatchmaker
MSUtil.escalatingRepeatAsync = Util.escalatingRepeatAsync
MSUtil.processQueueItemAsync = Util.processQueueItemAsync

return MSUtil