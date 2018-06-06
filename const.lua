local const = {
    defaultPort = 1338,

    frameOverviewHeight = 40,
    graphHeightFactor = 0.3,
    infoLineHeight = 35,
    nodeHeight = 40,

    noticeDuration = 4,
    noticeFadeoutAfter = 3,

    -- colors
    textColor = {1, 1, 1},

    hoverNodeColor = {1, 0, 0},
    nodeBgColor = {0.75, 0.75, 0.75},
    nodeNameColor = {0, 0, 0},
    nodeAnnotColor = {0.45, 0.45, 0.45},

    frameCursorColor = {1, 0, 0},
    frameSelectionColor = {1, 0, 0, 0.2},

    graphBorderColor = {0.3, 0.3, 0.3},
    timeGraphColor = {1, 0, 1},
    memGraphColor = {0, 1, 0},

    helpOverlayColor = {0, 0, 0, 0.8},
    helpTitleColor = {1, 1, 1},
    helpColor = {0.85, 0.85, 0.85},
}

const.graphYOffset = const.frameOverviewHeight + 20

return const
