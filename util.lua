local util = {}

function util.clamp(x, lo, hi)
    if not lo and not hi then
        lo, hi = 0, 1
    end
    return math.min(hi, math.max(lo, x))
end

return util
