local util = require("util")

local function addNode(intoNode, node)
    intoNode.deltaTime = intoNode.deltaTime + node.deltaTime
    intoNode.memoryDelta = intoNode.memoryDelta + node.memoryDelta
    intoNode.samples = intoNode.samples + 1

    for _, child in ipairs(node.children) do
        local intoChild = util.getChildByPath(intoNode, child.path[#child.path])
        if not intoChild then
            intoChild = {
                name = child.name,
                deltaTime = 0,
                memoryDelta = 0,
                parent = intoNode,
                samples = 0,
                children = {},
            }
            intoChild.path = {unpack(child.path)}
            table.insert(intoNode.children, intoChild)
        end
        addNode(intoChild, child)
    end
end

local function normalizeNode(node)
    node.deltaTime = node.deltaTime / node.samples
    node.memoryDelta = node.memoryDelta / node.samples
    for _, child in ipairs(node.children) do
        normalizeNode(child)
    end
end

local function getFrameAverage(frames, fromFrame, toFrame)
    local frame = {
        fromIndex = fromFrame,
        toIndex = toFrame,
        name = "frame",
        deltaTime = 0,
        memoryDelta = 0,
        parent = nil,
        children = {},
        path = {},
        samples = 0,
        pathCache = {},
    }

    for i = fromFrame, toFrame do
        addNode(frame, frames[i])
    end

    normalizeNode(frame)

    return frame
end

return getFrameAverage
