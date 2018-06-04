local lg = love.graphics

local const = require("const")
local util = require("util")

local draw = {}

function draw.getGraphCoords()
    local winH = love.graphics.getHeight()
    local graphHeight = winH * const.graphHeightFactor
    local graphY = winH - const.graphYOffset - graphHeight
    return graphY, graphHeight
end

local fonts = {
    mode = lg.newFont(22),
    node = lg.newFont(18),
    graph = lg.newFont(12),
}

local flameGraphFuncs = {
    time = function(node, child)
        local x
        -- this will be false for averge frames for which we use center=true anyways
        if child.startTime and node.startTime and node.endTime then
            assert(child.startTime >= node.startTime and child.endTime <= node.endTime)
            x = (child.startTime - node.startTime) / (node.endTime - node.startTime)
        else
            x = 0
        end
        return x, child.deltaTime / node.deltaTime
    end,

    memory = function(node, child)
        -- if not same sign
        if node.memoryDelta * child.memoryDelta < 0 then
            return 0, 0
        else
            return 0, math.abs(child.memoryDelta) / math.abs(node.memoryDelta)
        end
    end
}

local function getNodeString(node)
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

local function renderSubGraph(node, x, y, width, graphFunc, center)
    --print(node.name, x, y, width)

    local border = 2
    local font = lg.getFont()

    local hovered = nil
    local mx, my = love.mouse.getPosition()
    if mx > x and mx < x + width and my > y - const.nodeHeight and my < y then
        hovered = node
        lg.setColor(const.hoverNodeColor)
        lg.rectangle("fill", x, y - const.nodeHeight, width, const.nodeHeight)
    end

    lg.setColor(const.nodeBgColor)
    lg.rectangle("fill", x + border, y - const.nodeHeight + border,
        width - border*2, const.nodeHeight - border*2)


    lg.setScissor(x + border, y - const.nodeHeight + border,
        width - border*2, const.nodeHeight - border*2)
    lg.setColor(const.nodeNameColor)
    local tx = x + border + border
    local ty = y - const.nodeHeight/2 - font:getHeight()/2
    lg.print(node.name, tx, ty)
    lg.setColor(const.nodeAnnotColor)
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
            local childHover = renderSubGraph(child, childX, y - const.nodeHeight,
                childWidth, graphFunc, center)
            hovered = hovered or childHover
        end
    end

    return hovered
end

local function getFramePos(i)
    return lg.getWidth() / (#frames - 1) * (i - 1)
end

-- These are versions of the graphs in the graphs table, but with actual screen coordinates
-- So they can be passed to love.graphics.line, instead of normalized data
-- They are stored here so I don't have to create a couple of huge tables every draw
local drawGraphs = {}

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
        local c = util.clamp((frame.deltaTime - frames.minDeltaTime) /
            (frames.maxDeltaTime - frames.minDeltaTime))
        lg.setColor(c, c, c)
        local x, y = getFramePos(i) - width/2, winH - const.frameOverviewHeight + vMargin
        lg.rectangle("fill", x, y, width, const.frameOverviewHeight - vMargin*2)
    end

    local graphY, graphHeight = draw.getGraphCoords()

    if frames.current.index then
        lg.setColor(const.frameCursorColor)
        local x = getFramePos(frames.current.index)
        lg.line(x, graphY, x, winH)
    else
        lg.setColor(const.frameSelectionColor)
        local x, endX = getFramePos(frames.current.fromIndex), getFramePos(frames.current.toIndex)
        lg.rectangle("fill", x, graphY, endX - x, winH - graphY)
    end

    local infoLine = nil

    -- render graphs
    lg.setFont(fonts.graph)
    lg.setColor(const.graphBorderColor)
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

    for graphName, graphData in pairs(graphs) do
        if not drawGraphs[graphName] then
            drawGraphs[graphName] = {}
        end
        for i = 1, #graphData, 2 do
            drawGraphs[graphName][i+0] = graphData[i+0] * winW
            drawGraphs[graphName][i+1] = graphY + (1 - graphData[i+1]) * graphHeight
        end
    end

    lg.setColor(const.timeGraphColor)
    lg.setLineWidth(1)
    lg.line(drawGraphs.time)

    lg.setColor(const.memGraphColor)
    lg.setLineWidth(2)
    lg.line(drawGraphs.mem)

    lg.setColor(const.textColor)
    local textY = graphY + graphHeight + 5
    local frameText
    if frames.current.index then
        frameText = ("frame %d"):format(frames.current.index)
    else
        frameText = ("frame %d - frame %d (%d frames)"):format(
            frames.current.fromIndex, frames.current.toIndex,
            frames.current.toIndex - frames.current.fromIndex + 1)
    end
    lg.print(frameText, 5, textY)
    local totalFramesText = ("total frames: %d"):format(#frames)
    lg.print(totalFramesText, winW - lg.getFont():getWidth(totalFramesText) - 5, textY)

    lg.print(("frame time (max: %f ms)"):format(frames.maxDeltaTime*1000),
        5, graphY + lg.getFont():getHeight())
    lg.print(("memory usage (max: %d KB)"):format(frames.maxMemUsage), 5, graphY)

    -- render flame graph for current frame
    lg.setFont(fonts.mode)
    lg.print("graph type: " .. flameGraphType, 5, 5)
    lg.setFont(fonts.node)
    -- do not order flame layers (just center) if either memory graph or average frame
    local hovered = renderSubGraph(frames.current, 0, graphY - const.infoLineHeight, winW,
        flameGraphFuncs[flameGraphType], flameGraphType == "memory" or not frames.current.index)
    if hovered then
        infoLine = hovered.name .. " " .. getNodeString(hovered)
    end

    if infoLine then
        lg.print(infoLine, 5, graphY - const.infoLineHeight + 5)
    end
end

return draw
