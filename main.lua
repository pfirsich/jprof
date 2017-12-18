msgpack = require "MessagePack"

lg = love.graphics

-- layout constants (from bottom to top)
frameOverviewHeight = 40
graphHeightFactor = 0.3
graphYOffset = frameOverviewHeight + 20
infoLineHeight = 35
nodeHeight = 40

modeFont = lg.newFont(25)
nodeFont = lg.newFont(18)
graphFont = lg.newFont(12)

function love.load(arg)
    local identity, filename = arg[2], arg[3]
    if not identity or not filename then
        love.event.quit()
        print("Usage: love jprofViewer <identity> <filename>")
        return
    end

    love.filesystem.setIdentity(identity)
    local fileData, msg = love.filesystem.read(filename)
    assert(fileData, msg)
    local data = msgpack.unpack(fileData)

    frames = {}
    local nodeStack = {}
    for _, event in ipairs(data) do
        local top = nodeStack[#nodeStack]
        local name, time, memory, annotation = unpack(event)
        if name ~= "pop" then
            local node = {
                name = name,
                startTime = time,
                memoryStart = memory,
                annotation = annotation,
                children = {},
            }

            if name == "frame" then
                assert(#nodeStack == 0)
                node.index = #frames + 1
                table.insert(frames, node)
            else
                table.insert(top.children, node)
            end

            table.insert(nodeStack, node)
        else
            top.endTime = time + 1e-8
            top.deltaTime = top.endTime - top.startTime
            top.memoryEnd = memory
            top.memoryDelta = top.memoryEnd - top.memoryStart
            table.remove(nodeStack)
        end
    end

    -- determine frame and memory ranges
    frameDurMin, frameDurMax = math.huge, -math.huge
    memUsageMin, memUsageMax = math.huge, -math.huge
    local frameTimes = {}
    for _, frame in ipairs(frames) do
        frameDurMin = math.min(frameDurMin, frame.deltaTime)
        frameDurMax = math.max(frameDurMax, frame.deltaTime)
        memUsageMin = math.min(memUsageMin, frame.memoryEnd)
        memUsageMax = math.max(memUsageMax, frame.memoryEnd)
        table.insert(frameTimes, frame.deltaTime)
    end

    -- determine new min/max out of histogram
    table.sort(frameTimes)
    local margin = math.max(5, math.floor(0.005 * #frames))
    frameDurMin = frameTimes[margin]
    frameDurMax = frameTimes[#frames - margin]

    --
    currentFrame = frames[1]
    flameGraphType = "time" -- so far: "time" or "memory"

    -- some löve things
    lg.setLineJoin("none") -- lines freak out otherwise
    lg.setLineStyle("rough") -- lines are patchy otherwise
    love.keyboard.setKeyRepeat(true)
    love.window.maximize()

    -- setup graphs
    -- the non _draw-versions contain the graph data normalized (0-1)
    -- and the _draw versions are updated before every draw with actual screen coordinates
    memGraph, memGraph_draw = {}, {}
    timeGraph, timeGraph_draw = {}, {}

    for i, frame in ipairs(frames) do
        local x = (i - 1) / (#frames - 1)
        memGraph[#memGraph+1] = x
        memGraph[#memGraph+1] = math.min(1, math.max(0, frame.memoryEnd / memUsageMax))

        timeGraph[#timeGraph+1] = x
        timeGraph[#timeGraph+1] = math.min(1, math.max(0, frame.deltaTime / frameDurMax))
    end
end

flameGraphFuncs = {}

function flameGraphFuncs.time(node, child)
    local x
    -- this will be false for averge frames for which we use center=true anyways
    if child.startTime and node.startTime and node.endTime then
        assert(child.startTime >= node.startTime and child.endTime <= node.endTime)
        x = (child.startTime - node.startTime) / (node.endTime - node.startTime)
    else
        x = 0
    end
    return x, child.deltaTime / node.deltaTime
end

function flameGraphFuncs.memory(node, child)
    -- if not same sign
    if node.memoryDelta * child.memoryDelta < 0 then
        return 0, 0
    else
        return 0, math.abs(child.memoryDelta) / math.abs(node.memoryDelta)
    end
end

function getNodeString(node)
    local memStr = tostring(math.floor(node.memoryDelta*1024 + 0.5)) .. " B"
    if node.memoryDelta >= 1.0 then
        memStr = ("%.3f KB"):format(node.memoryDelta)
    end
    if node.memoryDelta >= 0 then
        memStr = "+" .. memStr
    else
        memStr = "-" .. memStr
    end

    local str
    if flameGraphType == "time" then
        str = ("- %.4f ms, %s"):format(node.deltaTime*1000, memStr)
    else
        str = ("- %s, %.4f ms"):format(memStr, node.deltaTime*1000)
    end

    if node.annotation then
        str = ("(%s) "):format(node.annotation) .. str
    end

    return str
end

function renderSubGraph(node, x, y, width, graphFunc, center)
    --print(node.name, x, y, width)

    local border = 2
    local font = lg.getFont()

    local hovered = nil
    local mx, my = love.mouse.getPosition()
    if mx > x and mx < x + width and my > y - nodeHeight and my < y then
        hovered = node
        lg.setColor(255, 0, 0, 255)
        lg.rectangle("fill", x, y - nodeHeight, width, nodeHeight)
    end

    lg.setColor(200, 200, 200, 255)
    lg.rectangle("fill", x + border, y - nodeHeight + border, width - border*2, nodeHeight - border*2)


    lg.setScissor(x + border, y - nodeHeight + border, width - border*2, nodeHeight - border*2)
    lg.setColor(0, 0, 0, 255)
    local tx = x + border + border
    local ty = y - nodeHeight/2 - font:getHeight()/2
    lg.print(node.name, tx, ty)
    lg.setColor(120, 120, 120, 255)
    lg.print(getNodeString(node), tx + font:getWidth(node.name) + 10, ty)
    lg.setScissor()

    local widthThresh = 5

    local totalChildrenWidth = 0
    if center then
        for i, child in ipairs(node.children) do
            local childX, childWidth = graphFunc(node, child)
            childWidth = math.floor(childWidth * width + 0.5)
            if childWidth >= widthThresh then
                totalChildrenWidth = totalChildrenWidth + childWidth
            end
        end
    end

    local nextChildX = math.floor((width - totalChildrenWidth) / 2 + x + 0.5)
    for i, child in ipairs(node.children) do
        local childX, childWidth = graphFunc(node, child)

        childX = math.floor(childX * width + x + 0.5)
        childWidth = math.floor(childWidth * width + 0.5)

        if center then
            childX = nextChildX
            nextChildX = nextChildX + childWidth
        end

        if childWidth >= widthThresh then
            local childHover = renderSubGraph(child, childX, y - nodeHeight, childWidth, graphFunc, center)
            hovered = hovered or childHover
        end
    end

    return hovered
end

function getFramePos(i)
    return lg.getWidth() / (#frames - 1) * (i - 1)
end

function getGraphCoords()
    local winH = lg.getHeight()
    local graphHeight = winH * graphHeightFactor
    local graphY = winH - graphYOffset - graphHeight
    return graphY, graphHeight
end

function love.draw()
    local winW, winH = lg.getDimensions()

    -- render frame overview at the bottom
    local spacing = 1
    if winW / #frames < 3 then
        spacing = 0
    end
    local width = (winW - spacing) / #frames - spacing
    local vMargin = 5

    for i, frame in ipairs(frames) do
        local c = math.floor((frame.deltaTime - frameDurMin) / (frameDurMax - frameDurMin) * 255 + 0.5)
        c = math.min(255, math.max(0, c))
        lg.setColor(c, c, c, 255)
        local x, y = getFramePos(i) - width/2, winH - frameOverviewHeight + vMargin
        lg.rectangle("fill", x, y, width, frameOverviewHeight - vMargin*2)
    end

    local graphY, graphHeight = getGraphCoords()

    if currentFrame.index then
        lg.setColor(255, 0, 0, 255)
        local x = getFramePos(currentFrame.index)
        lg.line(x, graphY, x, winH)
    else
        lg.setColor(255, 0, 0, 50)
        local x, endX = getFramePos(currentFrame.fromIndex), getFramePos(currentFrame.toIndex)
        lg.rectangle("fill", x, graphY, endX - x, winH - graphY)
    end

    local infoLine = nil

    -- render graphs
    lg.setFont(graphFont)
    lg.setColor(80, 80, 80, 255)
    lg.line(0, graphY, winW, graphY)
    lg.line(0, graphY + graphHeight, winW, graphY + graphHeight)

    local mouseX, mouseY = love.mouse.getPosition()
    if mouseY > graphY and mouseY < graphY + graphHeight then
        local relY = (graphY + graphHeight - mouseY) / graphHeight

        local frame = math.floor(mouseX / winW * (#frames - 1) + 1 + 0.5)
        local duration = frames[frame].deltaTime
        local memory = frames[frame].memoryEnd

        infoLine = ("frame %d: %.4f ms, %.3f KB"):format(frame, duration, memory)
    end

    local totalDur = frames[#frames].endTime - frames[1].startTime
    local tickInterval = 10
    local numTicks = math.floor(totalDur / tickInterval)
    for i = 1, numTicks do
        local x = tickInterval / totalDur * winW * (i - 1)
        lg.print(tostring(tickInterval * (i - 1)), x, graphY)
        lg.line(x, graphY, x, graphY + graphHeight)
    end

    for i = 1, #frames*2, 2 do
        memGraph_draw[i+0] = memGraph[i+0] * winW
        memGraph_draw[i+1] = graphY + (1 - memGraph[i+1]) * graphHeight

        timeGraph_draw[i+0] = timeGraph[i+0] * winW
        timeGraph_draw[i+1] = graphY + (1 - timeGraph[i+1]) * graphHeight
    end

    lg.setColor(255, 0, 255, 255)
    lg.setLineWidth(1)
    lg.line(timeGraph_draw)

    lg.setColor(0, 255, 0, 255)
    lg.setLineWidth(2)
    lg.line(memGraph_draw)

    lg.setColor(255, 255, 255, 255)
    local textY = graphY + graphHeight + 5
    local frameText
    if currentFrame.index then
        frameText = ("frame %d"):format(currentFrame.index)
    else
        frameText = ("frame %d - frame %d (%d frames)"):format(
            currentFrame.fromIndex, currentFrame.toIndex, currentFrame.toIndex - currentFrame.fromIndex + 1)
    end
    lg.print(frameText, 5, textY)
    local totalFramesText = ("total frames: %d"):format(#frames)
    lg.print(totalFramesText, winW - lg.getFont():getWidth(totalFramesText) - 5, textY)

    lg.setColor(255, 255, 255, 255)
    lg.print(("frame time (max: %f ms)"):format(frameDurMax*1000),
        5, graphY + lg.getFont():getHeight())
    lg.print(("memory usage (max: %d KB)"):format(memUsageMax), 5, graphY)

    -- render flame graph for current frame
    lg.setColor(255, 255, 255, 255)
    lg.setFont(modeFont)
    lg.print("graph type: " .. flameGraphType, 5, 5)
    lg.setFont(nodeFont)
    -- do not order flame layers (just center) if either memory graph or average frame
    local hovered = renderSubGraph(currentFrame, 0, graphY - infoLineHeight, winW,
        flameGraphFuncs[flameGraphType], flameGraphType == "memory" or not currentFrame.index)
    if hovered then
        infoLine = hovered.name .. " " .. getNodeString(hovered)
    end

    if infoLine then
        lg.print(infoLine, 5, graphY - infoLineHeight + 5)
    end
end

function getChildByName(node, name)
    for _, child in ipairs(node.children) do
        if child.name == name then
            return child
        end
    end
    return nil
end

function addNode(intoNode, node)
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

function rescaleNode(node, factor)
    node.deltaTime = node.deltaTime * factor
    node.memoryDelta = node.memoryDelta * factor
    for _, child in ipairs(node.children) do
        rescaleNode(child, factor)
    end
end

function getFrameAverage(fromFrame, toFrame)
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

function love.keypressed(key)
    local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    delta = ctrl and 100 or 1
    if key == "left" then
        if currentFrame.index then -- average frames don't have .index
            currentFrame = frames[math.max(1, currentFrame.index - delta)]
        end
    elseif key == "right" then
        if currentFrame.index then -- average frames don't have .index
            currentFrame = frames[math.min(#frames, currentFrame.index + delta)]
        end
    end

    if key == "space" then
        flameGraphType = flameGraphType == "time" and "memory" or "time"
    end
end

function pickFrame(x)
    return frames[math.floor(x / lg.getWidth() * #frames) + 1]
end

function love.mousepressed(x, y, button)
end

function love.update()
    local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local x, y = love.mouse.getPosition()
    if love.mouse.isDown(1) and y > select(1, getGraphCoords()) then
        local frame = pickFrame(x)
        if shift then
            if currentFrame.index then
                currentFrame = getFrameAverage(currentFrame, frame)
            else
                if frame.index > currentFrame.fromIndex then
                    currentFrame = getFrameAverage(frames[currentFrame.fromIndex], frame)
                else
                    currentFrame = getFrameAverage(frame, frames[currentFrame.toIndex])
                end
            end
        else
            currentFrame = frame
        end
    end
end