local eventChannel, chunkSize = ...

love.filesystem = require 'love.filesystem'
local msgpack = require("MessagePack")
msgpack.set_number("double")

local eventList = {}

-- record events
local complete = false
while not complete do
	local event = eventChannel:demand()
	if event == true then
		complete = true
	else
		table.insert(eventList, event)
	end
end

-- serialize events
local buf = {}
local function pushBuf()
	local str = table.concat(buf)
	eventChannel:push(str)
	for i=#buf, 1, -1 do
		buf[i] = nil
	end
end

for _, event in ipairs(eventList) do
	local str = msgpack.pack(event)
	table.insert(buf, str)
	if #buf == chunkSize then
		pushBuf()
	end
end

if #buf ~= 0 then
	-- push final incomplete chunk
	-- there should only be one worker that actually runs this
	pushBuf()
end
