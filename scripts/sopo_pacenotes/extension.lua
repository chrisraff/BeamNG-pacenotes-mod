-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.missionHandle = nil
M.mode = "none"

M.settings = {
    sound_data = {
        volume = 10
    }
}

M.checkpoints_array = nil
M.checkpoint_index = nil
M.pacenotes_data = nil

M.last_distance = 0
M.distance_of_last_queued_note = 0

M.lookahead_distance = 150

M.tick = 0

local function queueUpUntil(lookahead_target)
    for i, note in ipairs(M.pacenotes_data) do
        if note.d > M.distance_of_last_queued_note and note.d < lookahead_target then
            Engine.Audio.playOnce('AudioGui', 'art/sounds/smi_mixed_1/pacenote_' .. i .. '.wav', M.settings.sound_data)
            print('queing note ' .. i)
        end
    end
    M.distance_of_last_queued_note = math.max(lookahead_target, M.distance_of_last_queued_note)
end

local function resetRally()
    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    M.checkpoint_index = 0
    local distance = math.huge
    local position = my_veh:getPosition()
    for i, checkpoint in ipairs(M.checkpoints_array) do
        local dx = checkpoint[1] - position.x
        local dy = checkpoint[2] - position.y
        local dz = checkpoint[3] - position.z
        local squaredDistance = dx * dx + dy * dy + dz * dz

        if squaredDistance < distance then
            M.checkpoint_index = i
            distance = squaredDistance
        end
    end

    M.last_distance = M.checkpoints_array[M.checkpoint_index][4]

    M.distance_of_last_queued_note = M.last_distance
end

local function loadRally(mission)
    M.mode = "rally"

    -- TODO figure out the appropriate thing to load
    local file = readJsonFile('levels/small_island/pacenotes/intro_rally_stage1.json')

    M.checkpoints_array = file[1]
    M.pacenotes_data = file[2]

    resetRally()
end

local function cleanup()
end

local function test()
    print('hello from pacenotes')
end

local function onAnyMissionChanged(started, mission, userSettings)
    if started == "started" then
        print('starting rally')
        M.missionHandle = mission
        loadRally(mission)
    elseif started == "stopped" then
        cleanup()
    end
end

local function onUpdate(dt)
    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    if M.mode ~= "rally" then return end

    M.tick = M.tick + dt

    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    local position = my_veh:getPosition()
    local shortest_distance = math.huge
    -- check the surrounding
    for i = math.max(M.checkpoint_index - 1, 1), math.min(M.checkpoint_index + 1, #M.checkpoints_array) do
        local dx = M.checkpoints_array[i][1] - position.x
        local dy = M.checkpoints_array[i][2] - position.y
        local dz = M.checkpoints_array[i][3] - position.z
        local squaredDistance = dx * dx + dy * dy + dz * dz

        if squaredDistance < shortest_distance then
            M.checkpoint_index = i
            shortest_distance = squaredDistance
        end
    end

    queueUpUntil(M.checkpoints_array[M.checkpoint_index][4] + M.lookahead_distance)
end

M.test = test
M.onAnyMissionChanged = onAnyMissionChanged
M.onUpdate = onUpdate

return M
