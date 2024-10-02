-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}


M.scenarioHandle = nil
M.rallyId = nil
M.levelId = nil
M.mode = "none"
M.uiState = "none"

M.settings = {
    settingsVersion = 1,
    sound_data = {
        volume = 10
    },
    reset_threshold = 10, -- if you move this much since last tick, reset
    off_course_playback_reset_dist = 30, -- if you drive off course this much, reset playback
    pacenote_playback = {
        lookahead_distance_base = 60,
        speed_multiplier = 3
    },
    rallyPaths = {}
}

M.guiConfig = {
    panelOpen = true,
    isRallyChanged = false,
    playbackVolume = 10
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
M.audioQueueClearing = false

-- Recording variables
M.checkpointResolution = 2 -- meters between stage checkpoints
M.checkpointMaxEcc = 10 -- prevent adding a checkpoint in a restart

M.isRecordingNewPositions = false

M.recordingIndex = 0

M.recordingDistance = 0

M.isRecording = false
M.recordAtNote = false

M.savingRecce = false

M.logTag = "sopo_pacenotes.extension"

local micServer = nil

local function adaptCheckpointsArray(checkpoints)
    for i = 1, #checkpoints do
        -- Extract positional array values [x, y, z, d]
        local x, y, z, d = checkpoints[i][1], checkpoints[i][2], checkpoints[i][3], checkpoints[i][4]

        -- Create a labeled table
        checkpoints[i] = {
            x = roundNear(x, 0.001),
            y = roundNear(y, 0.001),
            z = roundNear(z, 0.001),
            d = roundNear(d, 0.001)
        }

        -- If not the last checkpoint, compute the direction vector
        if i < #checkpoints then
            local nextCheckpoint = checkpoints[i + 1]
            local dirVector = vec3(
                nextCheckpoint[1] - checkpoints[i].x,
                nextCheckpoint[2] - checkpoints[i].y,
                nextCheckpoint[3] - checkpoints[i].z
            ):normalized()

            -- Add the direction vector to the current checkpoint
            checkpoints[i].dx = roundNear(dirVector.x, 0.001)
            checkpoints[i].dy = roundNear(dirVector.y, 0.001)
            checkpoints[i].dz = roundNear(dirVector.z, 0.001)
        else
            -- For the last checkpoint, copy the previous direction
            checkpoints[i].dx = checkpoints[i - 1].dx
            checkpoints[i].dy = checkpoints[i - 1].dy
            checkpoints[i].dz = checkpoints[i - 1].dz
        end
    end

    return checkpoints
end

local function adaptPacenotesData(pacenotes)
    for i = 1, #pacenotes do
        pacenotes[i].d = roundNear(pacenotes[i].d, 0.001)
    end

    return pacenotes
end

local function onExtensionLoaded()
    log('I', M.logTag, '>>>>>>>>>>>>>>>>>>>>> onExtensionLoaded from sopo ext')

    setExtensionUnloadMode(M, 'manual')

    -- load the settings
    local settingsFile = jsonReadFile('settings/sopo_pacenotes/settings.json')
    if settingsFile and settingsFile.settingsVersion == M.settings.settingsVersion then
        M.settings = settingsFile
        M.guiSendGuiData()
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

local function findClosestCheckpoint(position)
    if not position then
        local my_veh = be:getPlayerVehicle(0)
        if my_veh == nil then return end
        position = my_veh:getPosition()
    end

    local checkpoint_index = 0
    local distance = math.huge
    for i, checkpoint in ipairs(M.checkpoints_array) do
        local squaredDistance = computeDistSquared(checkpoint.x, checkpoint.y, checkpoint.z, position.x, position.y, position.z)

        if squaredDistance < distance then
            checkpoint_index = i
            distance = squaredDistance
        end
    end

    return checkpoint_index
end

local function resetRally(checkpoint_index)
    local my_veh = be:getPlayerVehicle(0)
    if my_veh == nil then return end
    local position = my_veh:getPosition()

    log('I', M.logTag, 'resetRally called')

    if checkpoint_index then
        M.checkpoint_index = checkpoint_index
    else
        M.checkpoint_index = findClosestCheckpoint(position)
    end

    -- setup distance tracking from checkpoints
    M.last_distance = M.checkpoints_array[M.checkpoint_index].d
    M.distance_of_last_queued_note = M.last_distance

    M.last_position = position

    -- reset the audio queue
    clearQueue()
end

local function initRecce()
    log('I', M.logTag, 'initRecce called')
    M.checkpoints_array = {}
    M.pacenotes_data = {}
    M.recordingDistance = 0
    M.savingRecce = false
    M.isRecordingNewPositions = true

    M.serverResetCount()

    M.guiSendPacenoteData()
    M.guiSendMissionData()
end

local function loadOrNewRally()
    local result = M.loadRally(M.rallyId)

    if not result then
        M.newRally(M.rallyId)
    end
end

local function loadRally(rallyId)
    M.levelId = getCurrentLevelIdentifier()

    local file = jsonReadFile('art/sounds/' .. M.levelId .. '/' .. rallyId .. '/pacenotes.json')

    if not file then
        log('E', M.logTag, 'failed to load pacenote data')
        return false
    end

    -- temporary adaptation step
    if file[1][1].x == nil then
        print(' >>>>>>>>> adapting checkpoints array')
        file[1] = adaptCheckpointsArray(file[1])

        file[2] = adaptPacenotesData(file[2])
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

local function newRally(rallyId)
    M.levelId = getCurrentLevelIdentifier()
    M.rallyId = rallyId;
    M.mode = "recce"

    initRecce()
end

local function copyRally(newId)
    local oldId = M.rallyId
    M.rallyId = newId

    local oldPath = 'art/sounds/' .. M.levelId .. '/' .. oldId
    local newPath = 'art/sounds/' .. M.levelId .. '/' .. newId

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

    local path = 'art/sounds/' .. M.levelId .. '/'.. M.rallyId
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
    log('I', M.logTag, 'rally / recce: cleanup called')

    if M.savingRecce then
        M.savePacenoteData()
    end

    if M.guiConfig.isRallyChanged then
        jsonWriteFile('art/sounds/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes_autosave.json', M.pacenotes_data)
    end
    M.mode = "none"
    M.rallyId = nil
    M.scenarioHandle = nil
    M.pacenotes_data = nil

    M.isRecordingNewPositions = false

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

        -- Extract the first part of the path (before the first '/')
        local level, remainingPath = newPath:match("([^/]+)/(.+)")

        if M.settings.rallyPaths[level] == nil then
            M.settings.rallyPaths[level] = {}
        end

        -- Only add remainingPath to rallyPaths if it is not already in the list
        local pathExists = false
        for _, path in ipairs(M.settings.rallyPaths[level]) do
            if path == remainingPath then
                pathExists = true
                break
            end
        end

        if not pathExists then
            table.insert(M.settings.rallyPaths[level], remainingPath)
        end

        -- Don't reset the scenario if it's already loaded
        if M.rallyId == remainingPath then return end

        log('I', M.logTag, 'rally scenario path: ' .. remainingPath)
        M.scenarioHandle = scenarioOrMission
        M.rallyId = remainingPath
    end

    if M.rallyId then
        loadOrNewRally()
    end
    M.serverUpdateMission()
    M.guiSendMissionData()
end

local function switchRallyFromRecce()
    M.savePacenoteData();

    M.mode = 'rally';

    M.recordingDistance = 0
    M.distance_of_last_queued_note = M.last_distance
    M.savingRecce = false

    M.guiSendPacenoteData()
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

    M.guiSendGuiData()
end

local function onClientPostStartMission(levelPath)
    -- extract just the name
    local levelName = string.match(levelPath, "/levels/(.-)/")

    if levelName ~= M.levelId then
        log('I', M.logTag, 'Level changed, closing rally')
        cleanup()
        M.levelId = levelName
    end
end

-- update functions

local function updateDistance(position)
    local shortest_distance = math.huge

    -- check the surrounding checkpoints
    for i = math.max(M.checkpoint_index - 2, 1), math.min(M.checkpoint_index + 2, #M.checkpoints_array) do
        local squaredDistance = computeDistSquared(M.checkpoints_array[i].x, M.checkpoints_array[i].y, M.checkpoints_array[i].z, position.x, position.y, position.z)

        if squaredDistance < shortest_distance then
            M.checkpoint_index = i
            shortest_distance = squaredDistance
        end
    end

    M.last_distance = M.checkpoints_array[M.checkpoint_index].d

    -- if we are very far from the current checkpoint, find the closest one
    local dist2 = computeDistSquared(position.x, position.y, position.z, M.checkpoints_array[M.checkpoint_index].x, M.checkpoints_array[M.checkpoint_index].y, M.checkpoints_array[M.checkpoint_index].z)
    local thresh2 = M.settings.off_course_playback_reset_dist * M.settings.off_course_playback_reset_dist
    if dist2 > thresh2 then
        local newCheckpoint = findClosestCheckpoint(position)

        -- if we're not near any nearby checkpoints, reset playback based on nearest checkpoint
        if math.abs(newCheckpoint - M.checkpoint_index) > 2 then
            resetRally(newCheckpoint)
        end
    end

end

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
    local reset_this_tick = false

    if computeDistSquared(position.x, position.y, position.z, M.last_position.x, M.last_position.y, M.last_position.z) > M.settings.reset_threshold^2 then
        resetRally()
        reset_this_tick = true
    else
        updateDistance(position)
    end

    M.last_position = position

    local vel = my_veh:getVelocity()
    local speedAlongTrack = 0

    local checkpoint = M.checkpoints_array[M.checkpoint_index]
    speedAlongTrack = vel:dot(vec3(checkpoint.dx, checkpoint.dy, checkpoint.dz))

    -- if this speed is above 90, assume it is a reset and ignore it
    if speedAlongTrack > 90 then
        if reset_this_tick then
            speedAlongTrack = 0
        else
            speedAlongTrack = 90
        end
    end

    queueUpUntil(checkpoint.d + M.settings.pacenote_playback.lookahead_distance_base + speedAlongTrack * M.settings.pacenote_playback.speed_multiplier)

    M.guiSendRallyData()
end

local function updateAudioQueue(dt)
    -- heavily inspired by pacenotes core mod: https://www.beamng.com/resources/pacenotes-core.10349/

    -- if empty, do nothing
    if #M.audioQueue == 0 then return end

    local currentSound = M.audioQueue[1]

    -- play the sound
    if not currentSound.played then
        local path = 'art/sounds/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes/' .. currentSound.pacenote.wave_name
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

    if computeDistSquared(position.x, position.y, position.z, M.last_position.x, M.last_position.y, M.last_position.z) > M.settings.reset_threshold^2 then
        log('I', M.logTag, 'resetting recce checkpoint index')
        M.checkpoint_index = findClosestCheckpoint(position)
    end

    M.last_position = position

    -- if we haven't recorded any checkpoints yet, set the distance so we will trigger a recording
    local distance2FromLast = math.huge

    local dotProduct = 1

    -- see if we need to record a new checkpoint
    if #M.checkpoints_array > 0 then
        local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
        distance2FromLast = computeDistSquared(lastCheckpoint.x, lastCheckpoint.y, lastCheckpoint.z, position.x, position.y, position.z)

        -- subtract out the direction vector
        local lastCheckpointPos = vec3(lastCheckpoint.x, lastCheckpoint.y, lastCheckpoint.z)
        local lastCheckpointDir = (position - lastCheckpointPos):normalized()

        if #M.checkpoints_array > 1 then
            dotProduct = lastCheckpointDir:dot(vec3(lastCheckpoint.dx, lastCheckpoint.dy, lastCheckpoint.dz))
        end
    end

    local farEnough = distance2FromLast >= M.checkpointResolution^2
    local closeEnough = distance2FromLast < M.checkpointMaxEcc^2 or distance2FromLast == math.huge
    local uiPlaying = (M.uiState == "play" or M.uiState == "none")
    local forwardEnough = dotProduct > -0.8

    if M.isRecordingNewPositions then
        if farEnough and closeEnough and uiPlaying and forwardEnough then
            -- record the checkpoint
            local newD = 0
            local dx, dy, dz = 0, 0, 0

            if #M.checkpoints_array > 0 then
                local lastCheckpoint = M.checkpoints_array[#M.checkpoints_array]
                newD = lastCheckpoint.d + math.sqrt(distance2FromLast)

                -- calculate the new direction vector for previous checkpoint
                local dirVector = vec3(
                    position.x - lastCheckpoint.x,
                    position.y - lastCheckpoint.y,
                    position.z - lastCheckpoint.z
                ):normalized()

                -- Add the direction vector to the current checkpoint
                lastCheckpoint.dx = roundNear(dirVector.x, 0.001)
                lastCheckpoint.dy = roundNear(dirVector.y, 0.001)
                lastCheckpoint.dz = roundNear(dirVector.z, 0.001)

                dx = lastCheckpoint.dx
                dy = lastCheckpoint.dy
                dz = lastCheckpoint.dz
            else
                -- if this is the first checkpoint, set direction to vehicle's forward
                local forward = my_veh:getForwardVector()
                dx = roundNear(forward.x, 0.0001)
                dy = roundNear(forward.y, 0.0001)
                dz = roundNear(forward.z, 0.0001)
            end

            log('I', M.logTag, '>> recording checkpoint at ' .. position.x .. ', ' .. position.y .. ', ' .. position.z .. ' with d ' .. newD)

            local newPoint = {
                x=roundNear(position.x, 0.0001),
                y=roundNear(position.y, 0.0001),
                z=roundNear(position.z, 0.0001),
                dx=dx,
                dy=dy,
                dz=dz,
                d=roundNear(newD, 0.001)}
            table.insert(M.checkpoints_array, newPoint) -- Append new_point to checkpoints_array

            M.last_distance = newD
            M.checkpoint_index = #M.checkpoints_array
        elseif not forwardEnough and not closeEnough then
            M.isRecordingNewPositions = false

            log('I', M.logTag, '>> recording stopped')
        end
    else
        -- if not recording new positions
        updateDistance(position)

        -- check if we need to start recording
        if closeEnough and uiPlaying then
            -- presume we are at the tip of the track:
            -- delete points further than current pos and start recording
            log('I', M.logTag, '>> recording started')
            M.isRecordingNewPositions = true
            -- delete checkpoints after this index
            for i = #M.checkpoints_array, M.checkpoint_index + 1, -1 do
                table.remove(M.checkpoints_array, i)
            end
        end
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

    local file = jsonWriteFile('art/sounds/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes.json', {M.checkpoints_array, M.pacenotes_data})
    if file then
        log('I', M.logTag, 'saved pacenote data')
        M.guiConfig.isRallyChanged = false
        M.guiSendGuiData()
    else
        log('E', M.logTag, 'failed to save pacenote data')
        guihooks.trigger('toastrMsg', {type = "error", title = "Failed to Save Pacenotes", msg = "", config = {timeOut = 7000}})
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

    M.serverUpdateDataPath()
    M.micServer:send('\n')

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

local function serverUpdateDataPath()
    if M.micServer ~= nil then
        M.micServer:send('data_path ' .. FS:getFileRealPath('/art/sounds'))
    end
end

local function serverUpdateMission()
    if M.micServer ~= nil then
        M.micServer:send('mission ' .. M.levelId .. '/' .. M.rallyId)

        -- in case we are recording more pacenotes, set the index
        if M.mode == "rally" or M.mode == "recce" then
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

    -- if in recce, set autosave to true
    if M.mode == "recce" and not M.savingRecce then
        M.savingRecce = true
        guihooks.trigger('toastrMsg', {type = "info", title = "Recording Recce:", msg = "The Rally will auto save.", config = {timeOut = 5000}})
    elseif M.mode == "rally" then
        M.guiConfig.isRallyChanged = true
        M.guiSendGuiData()
    end

    if M.micServer == nil then
        log('I', M.logTag, 'Didn\'t start recording: not connected to server')
        Engine.Audio.playOnce('AudioGui', 'event:>UI>Main>Back', {volume=5})
        guihooks.trigger('toastrMsg', {type = "warning", title = "No Mic Connected", msg = "You must use the Pacenotes GUI to connect to the mic server.", config = {timeOut = 7000}})
        return
    end

    if M.mode == "rally" or M.mode == "recce" then
        M.micServer:send('record_start')

        if not M.recordAtNote then
            M.recordingDistance = M.last_distance
        end

        M.isRecording = true
        M.guiSendMicData()
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

    if not (M.mode == "rally" or M.mode == "recce") then
        return
    end

    M.micServer:send('record_stop')

    M.isRecording = false
    M.guiSendMicData()

    local newNote = {
        d = roundNear(M.recordingDistance, 0.001),
        wave_name = 'pacenote_' .. M.recordingIndex .. '.wav'
    }

    M.recordingIndex = M.recordingIndex + 1

    table.insert(M.pacenotes_data, newNote)

    -- The note may have been inserted out of order
    M.sortPacenotes()

    M.recordAtNote = false

    M.guiSendPacenoteData()

    -- Find the index of the recently recorded pacenote and select it
    local recentNoteIndex = #M.pacenotes_data
    for i, note in ipairs(M.pacenotes_data) do
        if note.wave_name == newNote.wave_name and note.d == newNote.d then
            recentNoteIndex = i
            break
        end
    end
    M.guiSendSelectedPacenote(recentNoteIndex)

    if M.savingRecce then
        M.savePacenoteData()
    end
end

-- gui functions

local function guiSendMissionData()
    log('I', M.logTag, 'sending gui data')
    local rallyId = ''
    if M.rallyId then rallyId = M.rallyId end
    if M.levelId == nil then M.levelId = getCurrentLevelIdentifier() end

    local data = {
        mode=M.mode,
        level=M.levelId,
        rallyPaths=M.settings.rallyPaths[M.levelId],
        rallyId=rallyId,
        playback_lookahead=M.settings.pacenote_playback.lookahead_distance_base,
        speed_multiplier=M.settings.pacenote_playback.speed_multiplier
    }
    guihooks.trigger('MissionDataUpdate', data)

    M.guiSendPacenoteData()
end

local function guiSendGuiData()
    M.guiConfig.playbackVolume = M.settings.sound_data.volume
    guihooks.trigger('GuiDataUpdate', M.guiConfig)
end

local function guiSendMicData()
    log('I', M.logTag, 'sending mic data')
    guihooks.trigger('MicDataUpdate', {connected=M.micServer ~= nil, isRecording = M.isRecording})
end

local function guiSendRallyData()
    guihooks.trigger('RallyDataUpdate', {distance=M.last_distance})
end

local function guiSendPacenoteData()
    guihooks.trigger('PacenoteDataUpdate', {pacenotes_data = M.pacenotes_data, recordAtNote = M.recordAtNote})
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
M.cleanup = cleanup
M.onExtensionLoaded = onExtensionLoaded
M.switchRallyFromRecce = switchRallyFromRecce
M.onAnyMissionChanged = onAnyMissionChanged
M.onUiChangedState = onUiChangedState
M.onClientPostStartMission = onClientPostStartMission
M.onUpdate = onUpdate
M.deletePacenote = deletePacenote
M.deleteDisabledPacenotes = deleteDisabledPacenotes
M.sortPacenotes = sortPacenotes
M.savePacenoteData = savePacenoteData
M.onScenarioChange = onScenarioChange
M.connectToMicServer = connectToMicServer
M.disconnectFromMicServer = disconnectFromMicServer
M.serverUpdateDataPath = serverUpdateDataPath
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
