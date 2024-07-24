-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}


M.scenarioHandle = nil
M.scenarioPath = nil
M.mode = "none"
M.uiState = "none"

M.settings = {
    sound_data = {
        volume = 10
    },
    reset_threshold = 10,
    pacenote_playback = {
        lookahead_distance_base = 100,
        speed_multiplier = 5
    }
}

M.checkpoints_array = nil
M.checkpoint_index = nil
M.pacenotes_data = nil

M.tick = 0

-- Playback variables
M.last_distance = 0
M.distance_of_last_queued_note = 0
M.last_position = vec3(0, 0, 0)

M.audioQueue = {}

-- Recording variables
M.checkpointResolution = 2 -- meters between stage checkpoints
M.checkpointMaxEcc = 10 -- prevent adding a checkpoint in a restart

M.recordingDistance = 0

M.savingRecce = false

M.logTag = "sopo_pacenotes.extension"

local micServer = nil

local function onExtensionLoaded()
    log('I', M.logTag, '>>>>>>>>>>>>>>>>>>>>> onExtensionLoaded from sopo ext')
end

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
                file = 'art/sounds/' .. M.scenarioPath .. '/pacenotes/' .. note.wave_name
            }
            table.insert(M.audioQueue, newSound)
            log('I', M.logTag, 'queing note ' .. i)
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
    log('I', M.logTag, 'resetRally called')
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

local function resetRecce()
    log('I', M.logTag, 'resetRecce called')
    M.checkpoints_array = {}
    M.pacenotes_data = {}
    M.recordingDistance = 0
    M.serverResetCount()
end

local function loadRally()
    local file = jsonReadFile('art/sounds/' .. M.scenarioPath .. '/pacenotes.json')
    if file then
        M.mode = "rally"

        M.checkpoints_array = file[1]
        M.pacenotes_data = file[2]

        resetRally()
    else
        -- if we don't have a file but we're in a mission, then we're in recce mode
        M.mode = "recce"

        resetRecce()
    end
end

local function cleanup()
    log('I', M.logTag, 'closing rally')
    M.mode = "none"
    M.scenarioPath = nil
    M.scenarioHandle = nil
    M.serverCloseMission()
    M.guiSendMissionData()
end

local function getPath(scenario)
    if scenario.id then
        return scenario.id
    end
    if scenario.sourceFile then
        return scenario.sourceFile:sub(1, -6) -- remove .json from the source file
    end
    if scenario.directory and scenario.scenarioName then
        return scenario.directory .. '/' .. scenario.scenarioName
    end

    return nil
end

local function setup(scenarioOrMission)
    if scenarioOrMission then
        local newPath = getPath(scenarioOrMission)
        -- don't reset the scenario if it's already loaded
        if M.scenarioPath == newPath then return end

        log('I', M.logTag, 'rally scenario path: ' .. newPath)
        M.scenarioHandle = scenarioOrMission
        M.scenarioPath = getPath(scenarioOrMission)
    end

    if M.scenarioPath then
        loadRally()
    end
    M.serverUpdateMission()
    M.guiSendMissionData()
end

local function onAnyMissionChanged(started, mission, userSettings)
    log('I', M.logTag, 'onAnyMissionChanged: ' .. started)
    if started == "started" then
        log('I', M.logTag, 'starting rally')
        setup(mission)
    elseif started == "stopped" then
        cleanup()
    end
end

local function onScenarioChange(scenario)
    if not scenario then
        cleanup()
        return
    end

    setup(scenario)
end

local function onUiChangedState(curUIState, prevUIState)
    log('I', M.logTag, 'ui changed state: ' .. curUIState .. ', ' .. prevUIState)
    M.uiState = curUIState
end

local function updateRally(dt)
    if M.mode ~= "rally" then return end

    M.tick = M.tick + dt

    -- only preform logic at 10hz
    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    if M.scenarioPath == nil then return end

    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    local position = my_veh:getPosition()
    local shortest_distance = math.huge

    if computeDistSquared(position.x, position.y, position.z, M.last_position.x, M.last_position.y, M.last_position.z) > M.settings.reset_threshold^2 then
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

    local vel = my_veh:getVelocity()
    local speedAlongTrack = 0

    local checkpoint = M.checkpoints_array[M.checkpoint_index]
    if (M.checkpoint_index + 1) <= #M.checkpoints_array then
        local nextCheckpoint = M.checkpoints_array[M.checkpoint_index + 1]
        local checkpointDirection = vec3(nextCheckpoint[1] - checkpoint[1], nextCheckpoint[2] - checkpoint[2], nextCheckpoint[3] - checkpoint[3]):normalized()
        speedAlongTrack = vel:dot(checkpointDirection)
    end

    queueUpUntil(checkpoint[4] + M.settings.pacenote_playback.lookahead_distance_base + speedAlongTrack * M.settings.pacenote_playback.speed_multiplier)
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

local function updateRecce(dt)
    if M.mode ~= "recce" then return end

    M.tick = M.tick + dt

    -- only preform logic at 10hz
    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    if M.scenarioPath == nil then return end

    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end

    local position = my_veh:getPosition()

    -- if we haven't recorded any checkpoints yet, set the distance so we will trigger a recording
    local distance2FromLast = math.huge

    -- see if we need to record a new checkpoint
    if #M.checkpoints_array > 0 then
        local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
        distance2FromLast = computeDistSquared(lastCheckpoint[1], lastCheckpoint[2], lastCheckpoint[3], position.x, position.y, position.z)
    end

    if M.debug.printTick then
        log('I', M.logTag, 'distance2FromLast: ' .. distance2FromLast .. ', ' .. M.checkpointResolution^2)
    end

    if distance2FromLast >= M.checkpointResolution^2 and (distance2FromLast < M.checkpointMaxEcc^2 or distance2FromLast == math.huge) and M.uiState == "play" then
        -- record the checkpoint
        local newD = 0
        if #M.checkpoints_array > 0 then
            local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
            newD = lastCheckpoint[4] + math.sqrt(distance2FromLast)
        end

        log('I', M.logTag, '>> recording checkpoint at ' .. position.x .. ', ' .. position.y .. ', ' .. position.z .. ' with d ' .. newD)

        local newPoint = {position.x, position.y, position.z, newD}
        table.insert(M.checkpoints_array, newPoint) -- Append new_point to checkpoints_array
    end

    M.guiSendRecceData()
end

local function saveRecce()
    if M.mode ~= "recce" then return end

    local file = jsonWriteFile('art/sounds/' .. M.scenarioPath .. '/pacenotes.json', {M.checkpoints_array, M.pacenotes_data})
    if file then
        log('I', M.logTag, 'saved recce data')
    else
        log('E', M.logTag, 'failed to save recce data')
    end
end

local function onUpdate(dt)
    if M.mode == "rally" then
        updateRally(dt)
    elseif M.mode == "recce" then
        updateRecce(dt)
    end
    updateAudioQueue(dt)
end

-- server functions

local function connectToMicServer()
    if M.micServer ~= nil then
        log('I', M.logTag, 'already connected to server')
    end

    M.micServer = assert(socket.tcp())
    M.micServer:settimeout(2) -- 2 second timeout
    local result = M.micServer:connect('127.0.0.1', 43434)
    if not result then
        M.micServer = nil
        log('I', M.logTag, 'couldn\'t connect to server')
    end
    log('I', M.logTag, 'connected to server')

    M.guiSendMicData()

    if M.scenarioPath ~= nil then
        M.serverUpdateMission()
    end
end

local function serverUpdateMission()
    if M.micServer ~= nil then
        M.micServer:send('mission ' .. M.scenarioPath)
    end
end

local function serverCloseMission()
    if M.micServer ~= nil then
        M.micServer:send('mission_end')
    end
end

local function serverDeleteLastPacenote()
    if M.micServer ~= nil then
        M.micServer:send('delete_last_pacenote')
    end
end

local function serverResetCount(i)
    if M.micServer ~= nil then
        i = i or 0
        M.micServer:send('reset_count ' .. i)
    end
end

local function handleStartRecording()
    log('I', M.logTag, 'start rec')
    -- if we're connected and in recce mode, then we can start recording
    if M.micServer ~= nil and M.mode == "recce" then
        M.micServer:send('record_start')

        local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
        M.recordingDistance = lastCheckpoint[4]
    end
end

local function handleStopRecording()
    log('I', M.logTag, 'stop rec')
    if M.micServer ~= nil then
        M.micServer:send('record_stop')
    end

    local newNote = {
        d = M.recordingDistance,
        wave_name = 'pacenote_' .. #M.pacenotes_data .. '.wav'
    }

    table.insert(M.pacenotes_data, newNote)

    if M.savingRecce then
        M.saveRecce()
    end
end

-- gui functions

local function guiSendMissionData()
    log('I', M.logTag, 'sending gui data')
    local mission_id = ''
    if M.scenarioPath then mission_id = M.scenarioPath end
    data = {
        mode=M.mode,
        mission_id=mission_id,
        playback_lookahead=M.settings.pacenote_playback.lookahead_distance_base,
        speed_multiplier=M.settings.pacenote_playback.speed_multiplier
    }
    guihooks.trigger('MissionDataUpdate', data)
end

local function guiSendMicData()
    log('I', M.logTag, 'sending mic data')
    guihooks.trigger('MicDataUpdate', {connected=M.micServer ~= nil})
end

local function guiSendRecceData()
    local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
    if lastCheckpoint == nil then
        lastCheckpoint = {0, 0, 0, 0}
    end
    guihooks.trigger('RecceDataUpdate', {distance=lastCheckpoint[4], pacenoteNumber=#M.pacenotes_data})
end

local function guiInit()
    M.guiSendMissionData()
    M.guiSendMicData()
end

M.onExtensionLoaded = onExtensionLoaded
M.onAnyMissionChanged = onAnyMissionChanged
M.onUiChangedState = onUiChangedState
M.saveRecce = saveRecce
M.onUpdate = onUpdate
M.onScenarioChange = onScenarioChange
M.connectToMicServer = connectToMicServer
M.serverCloseMission = serverCloseMission
M.serverUpdateMission = serverUpdateMission
M.serverDeleteLastPacenote = serverDeleteLastPacenote
M.serverResetCount = serverResetCount
M.handleStartRecording = handleStartRecording
M.handleStopRecording = handleStopRecording
M.guiSendMissionData = guiSendMissionData
M.guiSendMicData = guiSendMicData
M.guiSendRecceData = guiSendRecceData
M.guiInit = guiInit

return M
