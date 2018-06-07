local lg = love.graphics

local const = require("const")
local util = require("util")
local frames = require("frames")

local draw = {}

draw.graphMean = "max"
draw.nextGraphMean = {
    max = "arithmetic",
    arithmetic = "harmonic",
    harmonic = "max",
}

draw.flameGraphType = "time" -- so far: "time" or "memory"

local rootPath = {}
local rootPathHistory = {}

local fonts = {
    mode = lg.newFont(22),
    node = lg.newFont(18),
    graph = lg.newFont(12),
}

-- the data to to be passed to love.graphics.line is saved here, so I don't create new tables all the time
local graphs = {
    mem = {},
    time = {},
}

local noticeText = lg.newText(fonts.mode, "")
local noticeSent = 0

local helpText
do
    local L = const.helpTitleColor
    local R = const.helpColor
    helpText = {
        L, "Left Click (graph area):  ", R, "Select a frame.\n",
        L, "Shift + Left Click (graph area):  ", R, "Select a frame range.\n\n",

        L, "Left Click (flame graph):  ", R, "Select a node as the new root node.\n",
        L, "Right Click (flame graph):  ", R, "Return to the previous root node.\n\n",

        L, "Arrow Left/Right:  ", R, "Seek 1 frame left/right.\n",
        L, "Ctrl + Arrow Left/Right:  ", R, "Seek 100 frames left/right.\n\n",

        L, "Space:  ", R, "Switch between 'time' and 'memory' mode.\n\n",

        L, "Alt:  ", R, "Cycle through graph averaging modes.\n\n",
    }
end

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
    if draw.flameGraphType == "time" then
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
    prof.push("renderSubGraph")
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
    prof.pop("renderSubGraph")
    return hovered
end

local function getFramePos(i)
    return lg.getWidth() / (#frames - 1) * (i - 1)
end

local function buildGraph(graph, key, valueOffset, valueScale, mean, path)
    prof.push("buildGraph")
    local x, w = 0, lg.getWidth()
    local y, h = draw.getGraphCoords()

    local numPoints = math.min(#frames, lg.getWidth()*4)
    local frameIndex = 1
    local step = #frames / numPoints
    for p = 1, numPoints do
        local startIndex = math.floor(frameIndex)
        local endIndex = math.floor(frameIndex + step - 1)
        local accum = nil
        local n = endIndex - startIndex + 1
        for f = startIndex, endIndex do
            local node = util.getNodeByPath(frames[f], path)
            if node then
                accum = mean.add(accum, util.clamp((node[key] - valueOffset) / valueScale))
            end
        end
        frameIndex = frameIndex + step
        graph[p*2-1+0] = x + (p - 1) / (numPoints - 1) * w
        graph[p*2-1+1] = y + (1 - (mean.mean(accum, n) or 0)) * h
    end
    prof.pop("buildGraph")
end

function draw.updateGraphs()
    prof.push("draw.updateGraphs")
    buildGraph(graphs.time, "deltaTime", 0, frames.maxDeltaTime, util.mean[draw.graphMean], rootPath)
    buildGraph(graphs.mem, "memoryEnd", 0, frames.maxMemUsage, util.mean[draw.graphMean], rootPath)
    prof.pop("draw.updateGraphs")
end

function draw.getGraphCoords()
    local winH = love.graphics.getHeight()
    local graphHeight = winH * const.graphHeightFactor
    local graphY = winH - const.graphYOffset - graphHeight
    return graphY, graphHeight
end

function draw.notice(str)
    noticeText:set(str)
    noticeSent = love.timer.getTime()
end

local function setRootPath(path)
    rootPath = path
    draw.updateGraphs()
    draw.notice("new draw root: " .. util.nodePathToStr(path))
end

function draw.pushRootPath(path)
    table.insert(rootPathHistory, rootPath)
    setRootPath(path)
end

function draw.popRootPath(path)
    if #rootPathHistory > 0 then
        setRootPath(rootPathHistory[#rootPathHistory])
        table.remove(rootPathHistory)
    end
end

function love.draw()
    prof.push("love.draw")
    local winW, winH = lg.getDimensions()

    if #frames < 1 then
        lg.setFont(fonts.mode)
        lg.print("Waiting for frames..", 5, 5)

        prof.pop("love.draw")
        prof.pop("frame")
        prof.enabled(false)
        return
    end

    local mean = util.mean[draw.graphMean]

    -- render frame overview at the bottom
    prof.push("heatmap")
    local vMargin = 5
    local numLines = math.min(#frames, winW)
    local lineWidth = winW / numLines
    local frameIndex = 1
    local step = #frames / numLines
    for p = 1, numLines do
        local startIndex = math.floor(frameIndex)
        local endIndex = math.floor(frameIndex + step - 1)
        local accum = nil
        local n = endIndex - startIndex + 1
        for f = startIndex, endIndex do
            accum = mean.add(accum,
                util.clamp((frames[f].deltaTime - frames.minDeltaTime) /
                (frames.maxDeltaTime - frames.minDeltaTime)))
        end
        frameIndex = frameIndex + step

        local x = lg.getWidth() / (numLines - 1) * (p - 1)
        local y = winH - const.frameOverviewHeight + vMargin
        local c = mean.mean(accum, n)
        lg.setColor(c, c, c)
        lg.rectangle("fill", x, y, lineWidth, const.frameOverviewHeight - vMargin*2)
    end
    prof.pop("heatmap")

    local graphY, graphHeight = draw.getGraphCoords()

    -- draw current frame/selection
    if frames.current.index then
        lg.setColor(const.frameCursorColor)
        local x = getFramePos(frames.current.index)
        lg.line(x, graphY, x, winH)
    else
        lg.setColor(const.frameSelectionColor)
        local x = getFramePos(frames.current.fromIndex)
        local endX = getFramePos(frames.current.toIndex)
        lg.rectangle("fill", x, graphY, endX - x, winH - graphY)
    end

    local infoLine = nil

    -- render graphs
    lg.setFont(fonts.graph)
    lg.setColor(const.graphBorderColor)
    lg.line(0, graphY, winW, graphY)
    lg.line(0, graphY + graphHeight, winW, graphY + graphHeight)

    local mouseX, mouseY = love.mouse.getPosition()
    if mouseX > 0 and mouseX < winW and mouseY > graphY and mouseY < graphY + graphHeight then
        local relY = (graphY + graphHeight - mouseY) / graphHeight

        local frame = math.floor(mouseX / winW * (#frames - 1) + 1 + 0.5)
        local duration = frames[frame].deltaTime
        local memory = frames[frame].memoryEnd

        infoLine = ("frame %d: %.4f ms, %.3f KB"):format(frame, duration, memory)
    end

    -- draw ticks
    local totalDur = frames[#frames].endTime - frames[1].startTime
    local tickInterval = 10
    local numTicks = math.floor(totalDur / tickInterval)
    for i = 1, numTicks do
        local x = tickInterval / totalDur * winW * (i - 1)
        lg.print(tostring(tickInterval * (i - 1)), x, graphY)
        lg.line(x, graphY, x, graphY + graphHeight)
    end

    if #frames > 1 then
        lg.setLineWidth(1)
        lg.setColor(const.timeGraphColor)
        lg.line(graphs.time)

        lg.setLineWidth(2)
        lg.setColor(const.memGraphColor)
        lg.line(graphs.mem)
    end

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
    prof.push("flame graph")
    lg.setFont(fonts.mode)
    lg.print("graph type: " .. draw.flameGraphType, 5, 5)
    lg.setFont(fonts.node)
    -- do not order flame layers (just center) if either memory graph or average frame
    local node = util.getNodeByPath(frames.current, rootPath)
    if node then
        local hovered = renderSubGraph(node, 0, graphY - const.infoLineHeight, winW,
            flameGraphFuncs[draw.flameGraphType],
            flameGraphType == "memory" or not frames.current.index)
        if hovered then
            infoLine = hovered.name .. " " .. getNodeString(hovered)

            local mouseDown = love.mouse.isDown(1)
            if mouseDown and not lastMouseDown then
                draw.pushRootPath(hovered.path)
            end
            lastMouseDown = mouseDown
        end
    else
        infoLine = ("This frame does not have a node with path '%s'"):format(
            util.nodePathToStr(rootPath))
    end
    prof.pop("flame graph")

    if infoLine then
        lg.print(infoLine, 5, graphY - const.infoLineHeight + 5)
    end

    -- draw notice
    local dt = love.timer.getTime() - noticeSent
    if dt < const.noticeDuration then
        local alpha = 1.0 - math.max(0, dt - const.noticeFadeoutAfter) /
            (const.noticeDuration - const.noticeFadeoutAfter)
        lg.setColor(1, 1, 1, alpha)
        lg.draw(noticeText, winW - noticeText:getWidth() - 5, 5)
    end

    -- draw help overlay
    if love.keyboard.isDown("h") or love.keyboard.isDown("f1") then
        lg.setColor(const.helpOverlayColor)
        lg.rectangle("fill", 0, 0, winW, winH)
        lg.setColor(1, 1, 1)
        lg.printf(helpText, 20, 20, winW - 40)
    end

    prof.pop("love.draw")
    prof.pop("frame")
    prof.enabled(false)
end

return draw
