local function getChildByName(node, name)
    for _, child in ipairs(node.children) do
        if child.name == name then
            return child
        end
    end
    return nil
end

local function addNode(intoNode, node)
    intoNode.deltaTime = intoNode.deltaTime + node.deltaTime
    intoNode.memoryDelta = intoNode.memoryDelta + node.memoryDelta

    for _, child in ipairs(node.children) do
        local intoChild = getChildByName(intoNode, child.name)
        if not intoChild then
            intoChild = {
                name = child.name,
                deltaTime = 0,
                memoryDelta = 0,
                children = {},
            }
            table.insert(intoNode.children, intoChild)
        end
        addNode(intoChild, child)
    end
end

local function rescaleNode(node, factor)
    node.deltaTime = node.deltaTime * factor
    node.memoryDelta = node.memoryDelta * factor
    for _, child in ipairs(node.children) do
        rescaleNode(child, factor)
    end
end

local function getFrameAverage(frames, fromFrame, toFrame)
    local frame = {
        fromIndex = fromFrame.index,
        toIndex = toFrame.index,
        name = "frame",
        deltaTime = 0,
        memoryDelta = 0,
        children = {},
    }

    for i = fromFrame.index, toFrame.index do
        addNode(frame, frames[i])
    end

    rescaleNode(frame, 1/(frame.toIndex - frame.fromIndex + 1))

    return frame
end

return getFrameAverage
