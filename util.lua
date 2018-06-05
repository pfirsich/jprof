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
        assert(accum)
        return accum / n
    end,
}

util.mean.max = {
    add = function(accum, value)
        return accum and math.max(accum, value) or value
    end,
    mean = function(accum, n)
        assert(accum)
        return accum
    end,
}

util.mean.min = {
    add = function(accum, value)
        return accum and math.min(accum, value) or value
    end,
    mean = function(accum, n)
        assert(accum)
        return accum
    end,
}

util.mean.quadratic = {
    add = function(accum, value)
        return (accum or 0) + value*value
    end,
    mean = function(accum, n)
        assert(accum)
        return math.sqrt(accum / n)
    end,
}

util.mean.harmonic = {
    add = function(accum, value)
        return (accum or 0) + 1 / value
    end,
    mean = function(accum, n)
        assert(accum)
        return n / accum
    end,
}

return util
