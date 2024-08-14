-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}


M.scenarioHandle = nil
M.rallyId = nil
M.mode = "none"
M.uiState = "none"

M.settings = {
    settingsVersion = 0,
    sound_data = {
        volume = 10
    },
    reset_threshold = 10,
    pacenote_playback = {
        lookahead_distance_base = 60,
        speed_multiplier = 3
    }
}

M.guiConfig = {
    panelOpen = true,
    isRallyChanged = false,
}

-- debugging sudden queue all
M.maxSpeedAlongTrack = 0

M.checkpoints_array = nil
M.checkpoint_index = nil
M.pacenotes_data = nil

M.tick = 0

-- Playback variables
M.last_distance = 0
M.distance_of_last_queued_note = 0
M.last_position = vec3(0, 0, 0)

M.audioQueue = {}
M.audioQueueClearing = false

-- Recording variables
M.checkpointResolution = 2 -- meters between stage checkpoints
M.checkpointMaxEcc = 10 -- prevent adding a checkpoint in a restart

M.recordingIndex = 0

M.recordingDistance = 0

M.savingRecce = false

M.logTag = "sopo_pacenotes.extension"

local micServer = nil

local function onExtensionLoaded()
    log('I', M.logTag, '>>>>>>>>>>>>>>>>>>>>> onExtensionLoaded from sopo ext')

    -- load the settings
    local settingsFile = jsonReadFile('settings/sopo_pacenotes/settings.json')
    if settingsFile and settingsFile.settingsVersion == 0 then
        M.settings = settingsFile
    end
end

local function computeDistSquared(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return dx * dx + dy * dy + dz * dz
end

local function queueUpUntil(lookahead_target)
    for i, note in ipairs(M.pacenotes_data) do
        if note.d > M.distance_of_last_queued_note and note.d < lookahead_target and not note.disabled then
            local newSound = {
                played = false,
                pacenote = note
            }
            table.insert(M.audioQueue, newSound)
            M.guiSendSelectedPacenote(i);
            log('I', M.logTag, 'queing note ' .. i)
        end
    end
    M.distance_of_last_queued_note = math.max(lookahead_target, M.distance_of_last_queued_note)
end

local function clearQueue()
    M.audioQueueClearing = true

    if #M.audioQueue > 0 then
        M.audioQueue = {M.audioQueue[1]}
    end
end

local function resetRally()
    log('I', M.logTag, 'resetRally called')

    -- find the closest checkpoint
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

    -- setup distance tracking from checkpoints
    M.last_distance = M.checkpoints_array[M.checkpoint_index][4]
    M.distance_of_last_queued_note = M.last_distance

    M.last_position = position

    -- reset the audio queue
    clearQueue()
end

local function resetRecce()
    log('I', M.logTag, 'resetRecce called')
    M.checkpoints_array = {}
    M.pacenotes_data = {}
    M.recordingDistance = 0
    M.serverResetCount()

    M.guiSendPacenoteData()
end

local function loadOrNewRally()
    local result = M.loadRally(M.rallyId)

    if not result then
        M.newRally()
    end
end

local function loadRally(rallyId)
    local file = jsonReadFile('art/sounds/' .. rallyId .. '/pacenotes.json')

    if not file then
        log('E', M.logTag, 'failed to load pacenote data')
        return false
    end

    M.rallyId = rallyId
    M.mode = "rally"

    M.checkpoints_array = file[1]
    M.pacenotes_data = file[2]

    resetRally()

    M.guiConfig.isRallyChanged = false

    M.serverUpdateMission()

    M.guiSendMissionData()
    M.guiSendPacenoteData()
    M.guiSendGuiData()

    return true
end

local function newRally()
    M.mode = "recce"

    resetRecce()
end

local function copyRally(newId)
    local oldId = M.rallyId
    M.rallyId = newId

    local oldPath = 'art/sounds/' .. oldId
    local newPath = 'art/sounds/' .. newId

    -- copy the folder
    if FS:directoryExists(oldPath) then
        FS:copyFile(oldPath .. '/pacenotes.json', newPath .. '/pacenotes.json')
        local files = FS:findFiles(oldPath .. '/pacenotes', '*.*', -1, true, false)
        for _, file in ipairs(files) do
            local relativePath = file:sub(#oldPath + 2)
            local newFilePath = newPath .. '/' .. relativePath
            FS:copyFile(file, newFilePath)
        end
    end

    -- save the pacenotes
    M.savePacenoteData()

    M.guiConfig.isRallyChanged = false
    M.guiSendGuiData()
    M.guiSendMissionData()
end

local function deleteRally()
    log('I', M.logTag, 'Deleting rally')

    local path = 'art/sounds/' .. M.rallyId
    if FS:directoryExists(path) and FS:fileExists(path .. '/pacenotes.json') then
        FS:removeFile(path .. '/pacenotes.json')

        -- Remove all files in /pacenotes/ directory
        local files = FS:findFiles(path .. '/pacenotes', '*.*', -1, true, false)
        for _, file in ipairs(files) do
            FS:removeFile(file)
        end
    end

    M.rallyId = nil
    M.mode = "none"

    M.checkpoints_array = nil
    M.pacenotes_data = nil

    clearQueue()

    M.serverCloseMission()
    M.guiSendMissionData()
end

local function cleanup()
    log('I', M.logTag, 'closing rally')

    if M.guiConfig.isRallyChanged then
        jsonWriteFile('art/sounds/' .. M.rallyId .. '/pacenotes_autosave.json', M.pacenotes_data)
    end
    M.mode = "none"
    M.rallyId = nil
    M.scenarioHandle = nil
    M.pacenotes_data = nil

    clearQueue()

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
        local directory = scenario.directory
        if directory:sub(1, 7) == "/levels" then
            directory = directory:sub(9)
        end
        return directory .. '/' .. scenario.scenarioName
    end

    return nil
end

local function setup(scenarioOrMission)
    if scenarioOrMission then
        local newPath = getPath(scenarioOrMission)
        -- don't reset the scenario if it's already loaded
        if M.rallyId == newPath then return end

        log('I', M.logTag, 'rally scenario path: ' .. newPath)
        M.scenarioHandle = scenarioOrMission
        M.rallyId = getPath(scenarioOrMission)
    end

    if M.rallyId then
        loadOrNewRally()
    end
    M.serverUpdateMission()
    M.guiSendMissionData()
end

-- mission / scenario callbacks

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

    -- save the settings
    jsonWriteFile('settings/sopo_pacenotes/settings.json', M.settings)
end

-- update functions

local function updateRally(dt)
    if M.mode ~= "rally" then return end

    M.tick = M.tick + dt

    -- only perform logic at 10hz
    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    if M.rallyId == nil then return end

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
    M.last_distance = M.checkpoints_array[M.checkpoint_index][4]

    local vel = my_veh:getVelocity()
    local speedAlongTrack = 0

    local checkpoint = M.checkpoints_array[M.checkpoint_index]
    if (M.checkpoint_index + 1) <= #M.checkpoints_array then
        local nextCheckpoint = M.checkpoints_array[M.checkpoint_index + 1]
        local checkpointDirection = vec3(nextCheckpoint[1] - checkpoint[1], nextCheckpoint[2] - checkpoint[2], nextCheckpoint[3] - checkpoint[3]):normalized()
        speedAlongTrack = vel:dot(checkpointDirection)

        -- if this speed is above 90, assume it is a reset and ignore it
        if speedAlongTrack > 90 then
            speedAlongTrack = 0
        end
    end

    queueUpUntil(checkpoint[4] + M.settings.pacenote_playback.lookahead_distance_base + speedAlongTrack * M.settings.pacenote_playback.speed_multiplier)

    M.guiSendRallyData()
end

local function updateAudioQueue(dt)
    -- heavily inspired by pacenotes core mod: https://www.beamng.com/resources/pacenotes-core.10349/

    -- if empty, do nothing
    if #M.audioQueue == 0 then return end

    local currentSound = M.audioQueue[1]

    -- play the sound
    if not currentSound.played then
        local path = 'art/sounds/' .. M.rallyId .. '/pacenotes/' .. currentSound.pacenote.wave_name
        local result = Engine.Audio.playOnce('AudioGui', path, M.settings.sound_data)

        if result ~= nil then
            currentSound.time = result.len
        else
            currentSound.time = 0
        end
        currentSound.played = 0

    -- track the time of the sound
    else
        currentSound.time = currentSound.time - dt

        local finishedPlaying = currentSound.time <= 0
        local continueCondition = currentSound.pacenote.continueDistance == nil or currentSound.pacenote.d - currentSound.pacenote.continueDistance <= M.last_distance
        if finishedPlaying and (continueCondition or M.audioQueueClearing) then
            table.remove(M.audioQueue, 1)
            M.audioQueueClearing = false
        end
    end
end

local function updateRecce(dt)
    if M.mode ~= "recce" then return end

    M.tick = M.tick + dt

    -- only perform logic at 10hz
    if M.tick < 0.1 then return end

    M.tick = M.tick - 0.1

    if M.rallyId == nil then return end

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

        M.last_distance = newD
    end

    M.guiSendRallyData()
end

local function onUpdate(dt)
    if M.mode == "rally" then
        updateRally(dt)
    elseif M.mode == "recce" then
        updateRecce(dt)
    end
    updateAudioQueue(dt)
end

-- pacenote management

local function deletePacenote(index)
    if index == nil then
        index = #M.pacenotes_data
    end

    if index > 0 then
        table.remove(M.pacenotes_data, index)
        M.guiSendPacenoteData()
    end
end

local function deleteDisabledPacenotes()
    for i = #M.pacenotes_data, 1, -1 do
        if M.pacenotes_data[i].disabled then
            table.remove(M.pacenotes_data, i)
        end
    end
    M.guiSendPacenoteData()
end

local function sortPacenotes()
    local function compare(a, b)
        if a.d == b.d then
            return a.wave_name < b.wave_name
        end
        return a.d < b.d
    end

    table.sort(M.pacenotes_data, compare)
    M.guiSendPacenoteData()
end

local function savePacenoteData()
    if M.rallyId == nil then return end

    local file = jsonWriteFile('art/sounds/' .. M.rallyId .. '/pacenotes.json', {M.checkpoints_array, M.pacenotes_data})
    if file then
        log('I', M.logTag, 'saved pacenote data')
        M.guiConfig.isRallyChanged = false
        M.guiSendGuiData()
    else
        log('E', M.logTag, 'failed to save pacenote data')
    end
end

-- server functions

local function connectToMicServer()
    if M.micServer ~= nil then
        log('I', M.logTag, 'already connected to server')
        M.guiSendMicData()
        return
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

    if M.rallyId ~= nil then
        M.serverUpdateMission()
    end
end

local function disconnectFromMicServer()
    if M.micServer == nil then
        log('I', M.logTag, 'not connected to server')
        M.guiSendMicData()
        return
    end

    M.micServer:close()
    M.micServer = nil
    log('I', M.logTag, 'disconnected from server')

    M.guiSendMicData()
end

local function serverUpdateMission()
    if M.micServer ~= nil then
        M.micServer:send('mission ' .. M.rallyId)

        -- in case we are recording more pacenotes, set the index
        if M.mode == "rally" then
            -- avoid overwriting existing pacenotes
            local maxNumber = 0
            for _, pacenote in ipairs(M.pacenotes_data) do
                local waveName = pacenote.wave_name
                local number = tonumber(waveName:match("%d+"))
                if number and number > maxNumber then
                    maxNumber = number
                end
            end

            M.micServer:send('\n')
            M.serverResetCount(maxNumber + 1)
        end
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
        M.recordingIndex = i
    end
end

local function handleStartRecording()
    log('I', M.logTag, 'start rec')

    if M.micServer == nil then
        log('I', M.logTag, 'Didn\'t start recording: not connected to server')
        return
    end

    if M.mode == "rally" or M.mode == "recce" then
        M.micServer:send('record_start')

        if M.mode == "recce" then
            local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
            M.recordingDistance = lastCheckpoint[4]
        elseif M.mode == "rally" then
            M.recordingDistance = M.last_distance
        end
    else
        log('I', M.logTag, 'Didn\'t start recording: not in rally or recce mode')
    end
end

local function handleStopRecording()
    log('I', M.logTag, 'stop rec')

    if M.micServer == nil then
        log('I', M.logTag, 'Didn\'t stop recording: not connected to server')
        return
    end

    M.micServer:send('record_stop')

    local newNote = {
        d = M.recordingDistance,
        wave_name = 'pacenote_' .. M.recordingIndex .. '.wav'
    }

    M.recordingIndex = M.recordingIndex + 1

    table.insert(M.pacenotes_data, newNote)

    -- May have inserted out of order if in rally mode
    if (M.mode == "rally") then
        M.sortPacenotes()
    end

    M.guiSendPacenoteData()
    -- M.guiSendSelectedPacenote(#M.pacenotes_data)

    if M.savingRecce then
        M.savePacenoteData()
    end
end

-- gui functions

local function guiSendMissionData()
    log('I', M.logTag, 'sending gui data')
    local rallyId = ''
    if M.rallyId then rallyId = M.rallyId end
    local data = {
        mode=M.mode,
        rallyId=rallyId,
        playback_lookahead=M.settings.pacenote_playback.lookahead_distance_base,
        speed_multiplier=M.settings.pacenote_playback.speed_multiplier
    }
    guihooks.trigger('MissionDataUpdate', data)

    M.guiSendPacenoteData()
end

local function guiSendGuiData()
    guihooks.trigger('GuiDataUpdate', M.guiConfig)
end

local function guiSendMicData()
    log('I', M.logTag, 'sending mic data')
    guihooks.trigger('MicDataUpdate', {connected=M.micServer ~= nil})
end

local function guiSendRallyData()
    guihooks.trigger('RallyDataUpdate', {distance=M.last_distance})
end

local function guiSendPacenoteData()
    guihooks.trigger('PacenoteDataUpdate', {pacenotes_data = M.pacenotes_data})
end

local function guiSendSelectedPacenote(index)
    guihooks.trigger('PacenoteSelected', {index=index-1})
end

local function guiInit()
    M.guiSendMissionData()
    M.guiSendMicData()
    M.guiSendGuiData()
end

M.loadRally = loadRally
M.newRally = newRally
M.copyRally = copyRally
M.deleteRally = deleteRally
M.onExtensionLoaded = onExtensionLoaded
M.onAnyMissionChanged = onAnyMissionChanged
M.onUiChangedState = onUiChangedState
M.onUpdate = onUpdate
M.deletePacenote = deletePacenote
M.deleteDisabledPacenotes = deleteDisabledPacenotes
M.sortPacenotes = sortPacenotes
M.savePacenoteData = savePacenoteData
M.onScenarioChange = onScenarioChange
M.connectToMicServer = connectToMicServer
M.disconnectFromMicServer = disconnectFromMicServer
M.serverCloseMission = serverCloseMission
M.serverUpdateMission = serverUpdateMission
M.serverDeleteLastPacenote = serverDeleteLastPacenote
M.serverResetCount = serverResetCount
M.handleStartRecording = handleStartRecording
M.handleStopRecording = handleStopRecording
M.guiSendMissionData = guiSendMissionData
M.guiSendGuiData = guiSendGuiData
M.guiSendMicData = guiSendMicData
M.guiSendRallyData = guiSendRallyData
M.guiSendPacenoteData = guiSendPacenoteData
M.guiSendSelectedPacenote = guiSendSelectedPacenote
M.guiInit = guiInit

return M
