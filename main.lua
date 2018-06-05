inspect = require("inspect") -- global on purpose, so debugging is easier
local lg = love.graphics
local msgpack = require "MessagePack"

local draw = require("draw")
local getFrameAverage = require("frameAverage")
local util = require("util")
local const = require("const")

local netMsgBuffer = ""
local netChannel = love.thread.newChannel()

local deltaTimes = {}
local memUsages = {}

local function buildGraph(data)
    local frames = {}
    local nodeStack = {}
    for _, event in ipairs(data) do
        local name, time, memory, annotation = unpack(event)
        local top = nodeStack[#nodeStack]
        if name ~= "pop" then
            local node = {
                name = name,
                startTime = time,
                memoryStart = memory,
                annotation = annotation,
                children = {},
            }

            if name == "frame" then
                if #nodeStack > 0 then
                    error("Profiling data malformed: Pushed a new frame when the last one was not popped yet!")
                end

                node.index = #frames + 1
                table.insert(frames, node)
            else
                if not top then
                    error("Profiling data malformed: Pushed a profiling zone without a 'frame' profiling zone on the stack!")
                end

                table.insert(top.children, node)
            end

            table.insert(nodeStack, node)
        else
            if not top then
                error("Profiling data malformed: Popped a profiling zone on an empty stack!")
            end

            top.endTime = time + 1e-8
            top.deltaTime = top.endTime - top.startTime
            top.memoryEnd = memory
            top.memoryDelta = top.memoryEnd - top.memoryStart
            table.remove(nodeStack)
        end
    end
    return frames
end

local function updateRange(newFrames, valueList, key, cutoffPercent, cutoffMin)
    if #frames == 0 then
        for _, frame in ipairs(newFrames) do
            table.insert(valueList, frame[key])
        end
        table.sort(valueList)
    else
        for _, frame in ipairs(newFrames) do
            local value = frame[key]
            local i = 1
            while valueList[i] and valueList[i] < value do
                i = i + 1
            end
            table.insert(valueList, i, value)
            i = i + 1
        end
    end

    local margin = 0
    if cutoffPercent then
        assert(cutoffMin)
        -- cut off the lowest and highest cutoffPercent of the values
        margin = math.max(cutoffMin, math.floor(cutoffPercent * #valueList))
    end
    if cutoffMin and #valueList > cutoffMin * 5 then
        return valueList[1 + margin], valueList[#valueList - margin]
    else
        return valueList[1], valueList[#valueList]
    end
end

local function updateRanges(newFrames)
    frames.minDeltaTime, frames.maxDeltaTime =
        updateRange(newFrames, deltaTimes, "deltaTime", 0.005, 5)
    frames.minMemUsage, frames.maxMemUsage =
        updateRange(newFrames, memUsages, "memoryEnd")
end

function love.load(arg)
    local identity, filename = arg[1], arg[2]
    if identity == "listen" then
        frames = {}

        print("Waiting for connection...")
        local netThread = love.thread.newThread("networkThread.lua")
        netThread:start(netChannel, arg[2] and tonumber(arg[2]) or const.defaultPort)
    elseif not identity or not filename then
        print("Usage: love jprof <identity> <filename>\nor: love jprof listen [port]")
        love.event.quit()
        return
    else
        love.filesystem.setIdentity(identity)
        local fileData, msg = love.filesystem.read(filename)
        assert(fileData, msg)
        local data = msgpack.unpack(fileData)
        frames = buildGraph(data)
        updateRanges(frames)

        if #frames == 0 then
            error("Frame count in the capture is zero!")
        end
    end

    frames.current = frames[1]

    flameGraphType = "time" -- so far: "time" or "memory"

    -- some löve things
    lg.setLineJoin("none") -- lines freak out otherwise
    lg.setLineStyle("rough") -- lines are patchy otherwise
    love.keyboard.setKeyRepeat(true)
    love.window.maximize()
end

function love.keypressed(key)
    local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    local delta = ctrl and 100 or 1
    if key == "left" then
        if frames.current.index then -- average frames don't have .index
            frames.current = frames[math.max(1, frames.current.index - delta)]
        end
    elseif key == "right" then
        if frames.current.index then -- average frames don't have .index
            frames.current = frames[math.min(#frames, frames.current.index + delta)]
        end
    end

    if key == "space" then
        flameGraphType = flameGraphType == "time" and "memory" or "time"
    end

    if key == "rctrl" then
        draw.graphMean = draw.nextGraphMean[draw.graphMean]
        draw.notice("graph mean: " .. draw.graphMean)
    end
end

local function pickFrameIndex(x)
    return math.floor(x / lg.getWidth() * #frames) + 1
end

function love.update()
    local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local x, y = love.mouse.getPosition()
    if love.mouse.isDown(1) and y > select(1, draw.getGraphCoords()) then
        local frameIndex = pickFrameIndex(x)
        if shift then
            if frames.current.index then
                frames.current = getFrameAverage(frames, frames.current.index, frameIndex)
            else
                if frameIndex > frames.current.fromIndex then
                    frames.current = getFrameAverage(frames, frames.current.fromIndex, frameIndex)
                else
                    frames.current = getFrameAverage(frames, frameIndex, frames.current.toIndex)
                end
            end
        else
            frames.current = frames[frameIndex]
        end
    end

    repeat
        local netData = netChannel:pop()
        if netData then
            netMsgBuffer = netMsgBuffer .. netData
        end
    until netData == nil

    local headerLen = 4
    while netMsgBuffer:len() > headerLen do
        local a, b, c, d = netMsgBuffer:byte(1, 4)
        local len = d + 0x100 * (c + 0x100 * (b + 0x100 * a))

        if netMsgBuffer:len() >= headerLen + len then
            local msg = netMsgBuffer:sub(headerLen+1, headerLen+len)
            netMsgBuffer = netMsgBuffer:sub(headerLen+len+1)
            local data = msgpack.unpack(msg)

            local newFrames = buildGraph(data)
            for i, frame in ipairs(newFrames) do
                table.insert(frames, frame)
                frame.index = #frames
            end
            if frames.current == nil then
                frames.current = frames[1]
            end

            updateRanges(newFrames)
        else
            break
        end
    end
end
