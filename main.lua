local lg = love.graphics
local msgpack = require "MessagePack"

PROF_CAPTURE = false
prof = require("jprof")
prof.enabled(false)

local draw = require("draw")
local getFrameAverage = require("frameAverage")
local util = require("util")
local const = require("const")
local frames = require("frames")

local netMsgBuffer = ""
local netChannel = love.thread.newChannel()

local function readFileData(fileData)
    frames.addFrames(msgpack.unpack(fileData))
    draw.updateGraphs()

    if #frames == 0 then
        error("Frame count in the capture is zero!")
    end
end

function love.load(arg)
    if arg[1] == "listen" then
        print("Waiting for connection...")
        local netThread = love.thread.newThread("networkThread.lua")
        netThread:start(netChannel, arg[2] and tonumber(arg[2]) or const.defaultPort)
    elseif arg[1] and not arg[2] then
        local file, msg = io.open(arg[1], "rb")
        local fileData = assert(file:read("*a"), "Could not read file.")
        readFileData(fileData)
    elseif arg[1] and arg[2] then
        love.filesystem.setIdentity(arg[1])
        local fileData, msg = assert(love.filesystem.read(arg[2]))
        readFileData(fileData)
    else
        print("Usage: love jprof <identity> <filename>\nor: love jprof <path>\nor: love jprof listen [port]")
        love.event.quit()
        return
    end

    -- some löve things
    lg.setLineJoin("none") -- lines freak out otherwise
    lg.setLineStyle("rough") -- lines are patchy otherwise
    love.keyboard.setKeyRepeat(true)
    love.window.maximize()
end

local function lrDown(key)
    return love.keyboard.isDown("l" .. key) or love.keyboard.isDown("r" .. key)
end

function love.keypressed(key)
    local delta = lrDown("ctrl") and 100 or 1
    if frames.current then
        if key == "left" then
            if frames.current.index then -- average frames don't have .index
                frames.current = frames[math.max(1, frames.current.index - delta)]
            end
        elseif key == "right" then
            if frames.current.index then -- average frames don't have .index
                frames.current = frames[math.min(#frames, frames.current.index + delta)]
            end
        end
    end

    if key == "space" then
        draw.flameGraphType = draw.flameGraphType == "time" and "memory" or "time"
    end

    if key == "lalt" or key == "ralt" then
        draw.graphMean = draw.nextGraphMean[draw.graphMean]
        draw.notice("graph mean: " .. draw.graphMean)
    end
end

local function pickFrameIndex(x)
    return math.floor(x / lg.getWidth() * #frames) + 1
end

function love.mousepressed(x, y, button)
    if button == 2 and y < select(1, draw.getGraphCoords()) then
        draw.popRootPath()
    end
end

function love.resize()
    draw.updateGraphs()
end

function love.quit()
    prof.write("prof.mpack")
end

local function peekHeader(msgBuffer)
    local a, b, c, d = msgBuffer:byte(1, 4)
    return d + 0x100 * (c + 0x100 * (b + 0x100 * a))
end

local function processMessage(msgBuffer, msgLen)
    prof.push("processMessage")
    local headerLen = 4
    local msg = msgBuffer:sub(headerLen+1, headerLen+msgLen)
    local data = msgpack.unpack(msg)
    frames.addFrames(data)
    prof.pop("processMessage")
end

function love.update()
    prof.enabled(true)
    prof.push("frame")
    prof.push("love.update")
    local x, y = love.mouse.getPosition()
    if love.mouse.isDown(1) and y > select(1, draw.getGraphCoords()) then
        local frameIndex = pickFrameIndex(x)
        if lrDown("shift") then
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

    prof.push("read messages")
    local headerLen = 4
    local updateGraphs = false
    while netMsgBuffer:len() > headerLen do
        local msgLen = peekHeader(netMsgBuffer)

        if netMsgBuffer:len() >= headerLen + msgLen then
            processMessage(netMsgBuffer, msgLen)
            netMsgBuffer = netMsgBuffer:sub(headerLen+msgLen+1)
            updateGraphs = true
        else
            break
        end
    end
    prof.pop("read messages")

    if updateGraphs or love.keyboard.isDown("u") then
        draw.updateGraphs()
    end
    prof.pop("love.update")
end
