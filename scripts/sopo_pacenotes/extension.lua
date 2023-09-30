-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.missionHandle = nil
M.mode = "none"

M.settings = {
    sound_data = {
        volume = 10
    },
    reset_threshold = 10
}

M.checkpoints_array = nil
M.checkpoint_index = nil
M.pacenotes_data = nil

M.last_distance = 0
M.distance_of_last_queued_note = 0
M.last_position = vec3(0, 0, 0)

M.audioQueue = {}

M.lookahead_distance = 150

M.tick = 0

local function computeDistSquared(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return dx * dx + dy * dy + dz * dz
end

local function queueUpUntil(lookahead_target)
    for i, note in ipairs(M.pacenotes_data) do
        if note.d > M.distance_of_last_queued_note and note.d < lookahead_target then
            local newSound = {
                played = false,
                file = 'art/sounds/' .. M.missionHandle.id .. '/pacenotes/pacenote_' .. i-1 .. '.wav'
            }
            table.insert(M.audioQueue, newSound)
            print('queing note ' .. i)
        end
    end
    M.distance_of_last_queued_note = math.max(lookahead_target, M.distance_of_last_queued_note)
end

local function clearQueue()
    if #M.audioQueue > 0 then
        M.audioQueue = {M.audioQueue[1]}
    end
end

local function resetRally()
    print('resetRally called')
    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    M.checkpoint_index = 0
    local distance = math.huge
    local position = my_veh:getPosition()
    for i, checkpoint in ipairs(M.checkpoints_array) do
        local squaredDistance = computeDistSquared(checkpoint[1], checkpoint[2], checkpoint[3], position.x, position.y, position.z)

        if squaredDistance < distance then
            M.checkpoint_index = i
            distance = squaredDistance
        end
    end

    M.last_distance = M.checkpoints_array[M.checkpoint_index][4]

    M.distance_of_last_queued_note = M.last_distance

    M.last_position = position

    clearQueue()
end

local function loadRally(mission)
    local file = readJsonFile('art/sounds/' .. mission.id .. '/pacenotes.json')
    if not file then return end

    M.missionHandle = mission

    M.mode = "rally"

    M.checkpoints_array = file[1]
    M.pacenotes_data = file[2]

    resetRally()
end

local function cleanup()
    print('closing rally')
    M.mode = "none"
    M.missionHandle = nil
end

local function test()
    print('hello from pacenotes')
end

local function onAnyMissionChanged(started, mission, userSettings)
    if started == "started" then
        print('starting rally')
        loadRally(mission)
    elseif started == "stopped" then
        cleanup()
    end
end

local function updateRally(dt)
    if M.mode ~= "rally" then return end

    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    M.tick = M.tick + dt

    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    local position = my_veh:getPosition()
    local shortest_distance = math.huge

    if computeDistSquared(position.x, position.y, position.z, M.last_position.x, M.last_position.y, M.last_position.z) > M.settings.reset_threshold * M.settings.reset_threshold then
        resetRally()
    else
        -- check the surrounding
        for i = math.max(M.checkpoint_index - 2, 1), math.min(M.checkpoint_index + 2, #M.checkpoints_array) do
            local squaredDistance = computeDistSquared(M.checkpoints_array[i][1], M.checkpoints_array[i][2], M.checkpoints_array[i][3], position.x, position.y, position.z)

            if squaredDistance < shortest_distance then
                M.checkpoint_index = i
                shortest_distance = squaredDistance
            end
        end
    end

    M.last_position = position

    queueUpUntil(M.checkpoints_array[M.checkpoint_index][4] + M.lookahead_distance)
end

local function updateAudioQueue(dt)
    -- heavily inspired by pacenotes core mod: https://www.beamng.com/resources/pacenotes-core.10349/

    -- if empty, do nothing
    if #M.audioQueue == 0 then return end

    local currentSound = M.audioQueue[1]

    -- play the sound
    if not currentSound.played then
        local result = Engine.Audio.playOnce('AudioGui', currentSound.file, M.settings.sound_data)
        if result ~= nil then
            currentSound.time = result.len
        else
            currentSound.time = 0
        end
        currentSound.played = 0
    -- track the time of the sound
    else
        currentSound.time = currentSound.time - dt
        if currentSound.time <= 0 then
            table.remove(M.audioQueue, 1)
        end
    end
end

local function onUpdate(dt)
    updateRally(dt)
    updateAudioQueue(dt)
end

local function onScenarioChange(scenario)
    if not scenario then
        cleanup()
        return
    end

    M.debugHandle = scenario

    local resource_path = scenario.sourceFile:sub(1, -6) -- remove .json from the source file

    -- don't reset the scenario if it's already loaded
    if M.missionHandle and resource_path == M.missionHandle.id then return end

    print('rally scenario path: ' .. resource_path)

    M.missionHandle = {
        fakeMission = true,
        id = resource_path
    }

    loadRally(M.missionHandle)
end

M.test = test
M.onAnyMissionChanged = onAnyMissionChanged
M.onUpdate = onUpdate
M.onScenarioChange = onScenarioChange

return M
