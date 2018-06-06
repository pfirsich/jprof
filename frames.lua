-- the frames itself are stored in this table as well
local frames = {}

frames.current = nil

frames.minDeltaTime, frames.maxDeltaTime = nil, nil
frames.minMemUsage, frames.maxMemUsage = nil, nil

local function getNodeCount(node)
    assert(node.parent)
    local counter = 1
    for _, child in ipairs(node.parent.children) do
        if child.name == node.name then
            counter = counter + 1
            if child == node then
                break
            end
        end
    end
    return counter
end

local function buildNodeGraph(data)
    prof.push("buildNodeGraph")
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
                parent = top,
                children = {},
            }
            if top then
                node.path = {unpack(top.path)}
                table.insert(node.path, {node.name, getNodeCount(node)})
            else
                node.path = {}
            end

            if name == "frame" then
                if #nodeStack > 0 then
                    error("Profiling data malformed: Pushed a new frame when the last one was not popped yet!")
                end

                node.pathCache = {}
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
    prof.pop("buildNodeGraph")
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

local deltaTimes = {}
local memUsages = {}

local function updateRanges(newFrames)
    prof.push("updateRanges")
    frames.minDeltaTime, frames.maxDeltaTime =
        updateRange(newFrames, deltaTimes, "deltaTime", 0.005, 5)
    frames.minMemUsage, frames.maxMemUsage =
        updateRange(newFrames, memUsages, "memoryEnd")
    prof.pop("updateRanges")
end

function frames.addFrames(data)
    prof.push("frames.addFrames")
    local newFrames = buildNodeGraph(data)

    prof.push("extend list")
    for i, frame in ipairs(newFrames) do
        table.insert(frames, frame)
        frame.index = #frames
    end
    frames.current = frames.current or frames[1]
    prof.pop("extend list")

    updateRanges(newFrames)
    prof.pop("frames.addFrames")
end

return frames
