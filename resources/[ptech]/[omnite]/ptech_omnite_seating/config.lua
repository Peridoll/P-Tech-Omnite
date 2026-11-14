Config = {}

Config.Placement = {
    item = 'pomnite_toolbox',
    command = 'omnite_seating',
    adminAce = 'omnite.seating.admin',
    maxDistance = 8.0,
    maxPerOwner = 250,
    maxTotal = 5000,
    medicalResource = 'ptech_mediora_medical',
    emsJobs = { ambulance = true }, -- JOBのみ判定。グレード・出勤状態は問わない。
    bedAnimation = { dict = 'anim@gangops@morgue@table@', clip = 'body_search' },
}

Config.Seating = {
    targetLabel = '座る',
    targetDistance = 2.0,
    serverDistance = 3.0,
    standKey = 'X',
    styleKey = 'G',
    defaultStyle = 'standard',
    styles = {
        { id = 'standard', label = '標準', scenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'upright', label = '背筋を伸ばす', scenario = 'PROP_HUMAN_SEAT_CHAIR_UPRIGHT', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'armchair', label = 'ゆったり', scenario = 'PROP_HUMAN_SEAT_ARMCHAIR', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
    },
}

-- Enable only while setting up MLO seats. Both commands are ACE-restricted.
Config.SeatRecorder = {
    enabled = false,
    command = 'omnite_seatrecord',
    setupCommand = 'omnite_seatsetup',
    radius = 0.45,
    fineStep = 0.01,
    coarseStep = 0.05,
    headingStep = 1.0,
}

-- ACE-restricted tooling for inspecting configured seating in-game.
Config.SeatDebug = {
    command = 'omnite_seatdebug',
    ghostCommand = 'omnite_seatghost',
    markerDistance = 120.0,
    ghostDistance = 3.0,
    ghostScanDistance = 8.0,
}

-- Offsets are local to each object model. Tune them for chair models whose
-- default seat position or facing does not line up with the sitting scenario.
-- Add `styles = { 'standard', 'upright' }` to restrict a model when needed.
Config.ChairModels = {
    ['prop_chair_01a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_01b'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_02'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_03'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_04a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_04b'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_05'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_06'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_07'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_08'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_09'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_10'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_01'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_03'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_04'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_01_chr_a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_02_chr'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_03b_chr'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
}

-- Use fixed seats for MLO chairs that are not exposed as individual objects.
-- Each entry is one exclusive seat position.
Config.FixedSeats = {
    -- Example:
    -- { id = 'clinic_waiting_01', coords = vec3(307.25, -595.10, 43.28), heading = 70.0, styles = { 'standard', 'upright' } },
}
