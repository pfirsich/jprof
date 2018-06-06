local lg = love.graphics
local msgpack = require "MessagePack"

local draw = require("draw")
local getFrameAverage = require("frameAverage")
local util = require("util")
local const = require("const")
local frames = require("frames")

local netMsgBuffer = ""
local netChannel = love.thread.newChannel()

function love.load(arg)
    local identity, filename = arg[1], arg[2]
    if identity == "listen" then
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
        frames.addFrames(data)
        draw.updateGraphs()

        if #frames == 0 then
            error("Frame count in the capture is zero!")
        end
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

function love.update()
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

    local headerLen = 4
    while netMsgBuffer:len() > headerLen do
        local a, b, c, d = netMsgBuffer:byte(1, 4)
        local len = d + 0x100 * (c + 0x100 * (b + 0x100 * a))

        if netMsgBuffer:len() >= headerLen + len then
            local msg = netMsgBuffer:sub(headerLen+1, headerLen+len)
            netMsgBuffer = netMsgBuffer:sub(headerLen+len+1)
            local data = msgpack.unpack(msg)
            frames.addFrames(data)
            draw.updateGraphs()
        else
            break
        end
    end
end
