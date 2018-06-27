local util = {}

function util.clamp(x, lo, hi)
    if not lo and not hi then
        lo, hi = 0, 1
    end
    return math.min(hi, math.max(lo, x))
end

util.mean = {}

util.mean.arithmetic = {
    add = function(accum, value)
        return (accum or 0) + value
    end,
    mean = function(accum, n)
        return accum and accum / n
    end,
}

util.mean.max = {
    add = function(accum, value)
        return accum and math.max(accum, value) or value
    end,
    mean = function(accum, n)
        return accum
    end,
}

util.mean.min = {
    add = function(accum, value)
        return accum and math.min(accum, value) or value
    end,
    mean = function(accum, n)
        return accum
    end,
}

util.mean.quadratic = {
    add = function(accum, value)
        return (accum or 0) + value*value
    end,
    mean = function(accum, n)
        return accum and math.sqrt(accum / n)
    end,
}

util.mean.harmonic = {
    add = function(accum, value)
        return (accum or 0) + 1 / value
    end,
    mean = function(accum, n)
        return accum and n / accum
    end,
}

function util.nodePathToStr(nodePath)
    local str = ""
    for _, part in ipairs(nodePath) do
        str = str .. "/" .. part[1]
        if part[2] > 1 then
            str = str .. "[" .. part[2] .. "]"
        end
    end
    return str:len() > 0 and str or "/"
end

-- path should only be the last part of the path
function util.getChildByPath(node, path)
    for _, child in ipairs(node.children) do
        local childPart = child.path[#child.path]
        if path[1] == childPart[1] and path[2] == childPart[2] then
            return child
        end
    end
    return nil
end

function util.getNodeByPath(frame, path)
    if frame.pathCache[path] then
        return frame.pathCache[path]
    end

    local current = frame
    for _, part in ipairs(path) do
        current = util.getChildByPath(current, part)
        if not current then
            return nil
        end
    end
    frame.pathCache[path] = current
    return current
end

return util
