local lg = love.graphics
local msgpack = require "MessagePack"

local draw = require("draw")
local getFrameAverage = require("frameAverage")
local util = require("util")

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

local function getRange(frames, property, cutoffPercent, cutoffMin)
    local values = {}
    for _, frame in ipairs(frames) do
        table.insert(values, frame[property])
    end
    table.sort(values)

    local margin = 0
    if cutoffPercent then
        assert(cutoffMin)
        -- cut off the lowest and highest cutoffPercent of the values
        margin = math.max(cutoffMin, math.floor(cutoffPercent * #values))
    end
    return values[1 + margin], values[#values - margin]
end

function love.load(arg)
    local identity, filename = arg[1], arg[2]
    if not identity or not filename then
        error("Usage: love jprofViewer <identity> <filename>")
    end

    love.filesystem.setIdentity(identity)
    local fileData, msg = love.filesystem.read(filename)
    assert(fileData, msg)
    local data = msgpack.unpack(fileData)

    frames = buildGraph(data)
    if #frames == 0 then
        error("Frame count in the capture is zero!")
    end

    frames.minDeltaTime, frames.maxDeltaTime = getRange(frames, "deltaTime", 0.005, 5)
    frames.minMemUsage, frames.maxMemUsage = getRange(frames, "memoryEnd")

    frames.current = frames[1]

    flameGraphType = "time" -- so far: "time" or "memory"

    -- some löve things
    lg.setLineJoin("none") -- lines freak out otherwise
    lg.setLineStyle("rough") -- lines are patchy otherwise
    love.keyboard.setKeyRepeat(true)
    love.window.maximize()

    -- setup graphs
    graphs = {
        mem = {},
        time = {},
    }

    for i, frame in ipairs(frames) do
        local x = (i - 1) / (#frames - 1)
        graphs.mem[#graphs.mem+1] = x
        graphs.mem[#graphs.mem+1] = util.clamp(frame.memoryEnd / frames.maxMemUsage)

        graphs.time[#graphs.time+1] = x
        graphs.time[#graphs.time+1] = util.clamp(frame.deltaTime / frames.maxDeltaTime)
    end
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
end

local function pickFrame(x)
    return frames[math.floor(x / lg.getWidth() * #frames) + 1]
end

function love.update()
    local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local x, y = love.mouse.getPosition()
    if love.mouse.isDown(1) and y > select(1, draw.getGraphCoords()) then
        local frame = pickFrame(x)
        if shift then
            if frames.current.index then
                frames.current = getFrameAverage(frames.current, frame)
            else
                if frame.index > frames.current.fromIndex then
                    frames.current = getFrameAverage(frames[frames.current.fromIndex], frame)
                else
                    frames.current = getFrameAverage(frame, frames[frames.current.toIndex])
                end
            end
        else
            frames.current = frame
        end
    end
end
