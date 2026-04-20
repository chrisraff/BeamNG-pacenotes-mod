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
        volume = 20
    },
    reset_threshold = 10, -- if you move this much since last tick, reset
    wrong_way_threshold = 10, -- if you travel this far backwards, play wrong way sound and reset notes
    wrong_way_repeat_distance = 40, -- if you keep going backwards, you will be warned again at this distance
    off_course_playback_reset_dist = 30, -- if you drive off course this much, reset playback
    pacenote_playback = {
        lookahead_distance_base = 60,
        speed_multiplier = 3
    },
    guiPanelStates = {
        ["main-panel"] = true,
        ["load-save-panel"] = false,
        ["delete-panel"] = false,
        ["playback-panel"] = true,
        ["mic-server-panel"] = false
    },
    muteOnAiPacenotes = false,
    guiTableHeight = 300,
    rallyPaths = {}
}

M.guiConfig = {
    isRallyChanged = false,
    playbackVolume = 20,
    guiPanelStates = {}
}

M.tempPlaybackVolumeMultiplier = 1
M.micId = nil

M.checkpoints_array = nil
M.checkpoint_index = nil
M.pacenotes_data = nil
M.rally_metadata = nil

M.tick = 0

-- Playback variables
M.last_distance = 0
M.furthest_distance = 0
M.backtrack_distance = 0
M.is_going_forwards = true
M.distance_of_last_queued_note = -1
M.last_position = vec3(0, 0, 0)
M.isAipacenotesRally = false

M.showedUserMuteWarning = false

M.audioQueue = {}
M.audioQueueClearing = false

M.isAnalyzing = true

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

M.onInit = function()
    log('I', M.logTag, '>>>>>>>>>>>>>>>>>>>>> onInit from sopo pacenotes')

    setExtensionUnloadMode(M, 'manual')

    -- load the settings
    local settingsFile = jsonReadFile('settings/sopo_pacenotes/settings.json')
    if settingsFile and settingsFile.settingsVersion == M.settings.settingsVersion then
        for key, value in pairs(M.settings) do
            if settingsFile[key] == nil then
                log('I', M.logTag, 'populating ' .. key .. ' from default')
                settingsFile[key] = value
            end
        end
        M.settings = settingsFile
    end
    M.guiSendGuiData()
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

            local veh_speed = be:getPlayerVehicle(0):getVelocity():length() * 3.6 -- convert m/s to km/h

            if M.isAnalyzing then
                note.analysis = {
                    queueDistance = M.last_distance,
                    queueSpeed = roundNear(veh_speed, 0.001),
                    playbackTime = 0,
                    playStartDistance = nil,
                    playEndDistance = nil
                }
            end

            -- once per session, alert the user of the mute setting
            if (not M.showedUserMuteWarning) and M.settings.muteOnAiPacenotes and M.isAipacenotesRally then
                guihooks.trigger('toastrMsg', {type = "info", title = "Custom Rally Pacenotes Muted", msg = "This Rally has custom voice calls, but BeamNG pacenotes are playing. In keybindings, search 'toggle playback' to toggle which pacenotes play.", config = {timeOut = 15000}})
                M.showedUserMuteWarning = true
            end
        end
    end
    M.distance_of_last_queued_note = math.max(lookahead_target, M.distance_of_last_queued_note)
end

local function clearQueue()
    M.audioQueueClearing = true

    -- finish tracking the current note
    if #M.audioQueue > 0 and M.audioQueue[1].played then
        M.audioQueue = {M.audioQueue[1]}
    end
end

local function playMicSound(soundName)
    if M.micId == nil then return end
    -- Search for all files in the folder
    local files = FS:findFiles('pacenotes_sp/global/' .. M.micId .. '/' .. soundName, '*.*', -1, true, false)
    local soundPath = ''

    -- Pick one file at random
    if #files > 0 then
        soundPath = files[math.random(#files)]
    else
        log('W', M.logTag, 'No sound files found in the directory: ' .. 'pacenotes_sp/global/' .. M.micId .. '/' .. soundName)
        return
    end

    -- Play the sound
    local new_sound = {
        played = false,
        path = soundPath
    }
    table.insert(M.audioQueue, new_sound)
    log('I', M.logTag, 'Playing mic sound: ' .. soundPath)
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
    M.distance_of_last_queued_note = M.last_distance - 1
    M.is_going_forwards = true
    M.furthest_distance = M.last_distance
    M.backtrack_distance = M.last_distance

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

    M.serverUpdateMission()

    M.guiSendPacenoteData()
    M.guiSendMissionData()
end

local function loadOrNewRally(rallyId)
    rallyId = rallyId or M.rallyId
    local result = M.loadRally(rallyId)

    -- adjust beamng audio pacenotes setting based on user preference
    if result and M.isAipacenotesRally then
        if M.settings.muteOnAiPacenotes then
            -- let BeamNG's own pacenotes play; silence custom ones in updateAudioQueue
            settings.setValue('rallyAudioPacenotes', true)
        else
            -- disable BeamNG's pacenotes for this stage
            settings.setValue('rallyAudioPacenotes', false)
        end
    end

    if not result then
        M.newRally(rallyId)
    end
end

local function loadRally(rallyId)
    M.levelId = getCurrentLevelIdentifier()

    local file = jsonReadFile('pacenotes_sp/' .. M.levelId .. '/' .. rallyId .. '/pacenotes.json')

    if not file then
        log('E', M.logTag, 'failed to load pacenote data')
        return false
    end

    -- temporary adaptation step
    if file[1] and file[1][1] and file[1][1].x == nil then
        print(' >>>>>>>>> adapting checkpoints array')
        file[1] = adaptCheckpointsArray(file[1])

        file[2] = adaptPacenotesData(file[2])
    end

    M.rallyId = rallyId
    M.mode = "rally"

    M.checkpoints_array = file[1]
    M.pacenotes_data = file[2]

    if file[3] then
        M.rally_metadata = file[3]

        if M.rally_metadata.playbackVolumeMultiplier then
            log('I', M.logTag, 'loading temporary playback volume multiplier: ' .. M.rally_metadata.playbackVolumeMultiplier)
            M.tempPlaybackVolumeMultiplier = M.rally_metadata.playbackVolumeMultiplier
        end

        if M.rally_metadata.micId then
            M.micId = M.rally_metadata.micId
        end
    end

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

    local oldPath = 'pacenotes_sp/' .. M.levelId .. '/' .. oldId
    local newPath = 'pacenotes_sp/' .. M.levelId .. '/' .. newId

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
    if M.rallyId == nil then return end

    log('I', M.logTag, 'Deleting rally')

    local rallyId = M.rallyId
    local levelId = M.levelId

    M.cleanup()

    local path = 'pacenotes_sp/' .. levelId .. '/'.. rallyId
    if FS:directoryExists(path) and FS:fileExists(path .. '/pacenotes.json') then
        FS:removeFile(path .. '/pacenotes.json')

        -- Remove all files in /pacenotes/ directory
        local files = FS:findFiles(path .. '/pacenotes', '*.*', -1, true, false)
        for _, file in ipairs(files) do
            FS:removeFile(file)
        end
    end
end

local function cleanup()
    if M.rallyId == nil then return end

    log('I', M.logTag, 'rally / recce: cleanup called')

    if M.savingRecce then
        M.savePacenoteData()
    end

    -- restore beamng audio pacenotes
    if M.isAipacenotesRally and not M.settings.muteOnAiPacenotes then
        settings.setValue('rallyAudioPacenotes', true)
    end

    if M.guiConfig.isRallyChanged then
        jsonWriteFile('pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes_autosave.json', M.pacenotes_data)
    end
    M.mode = "none"
    M.rallyId = nil
    M.scenarioHandle = nil
    M.pacenotes_data = nil
    M.rally_metadata = nil
    M.isAipacenotesRally = false

    M.isRecordingNewPositions = false

    M.tempPlaybackVolumeMultiplier = 1
    M.micId = nil

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

local function setup(scenarioOrMission, isReversed)
    isReversed = isReversed or false

    if M.mode ~= 'none' then
        cleanup()
    end

    if scenarioOrMission then
        local newPath = getPath(scenarioOrMission)

        -- Extract the first part of the path (before the first '/')
        local level, remainingPath = newPath:match("([^/]+)/(.+)")

        -- if this is a rally stage we need to track it as aipacenotes rally for muting
        local path1Exists = FS:directoryExists('gameplay/missions/' .. newPath .. '/rally/notebooks')
        local path2Exists = FS:directoryExists(remainingPath .. '/rally/notebooks')
        if path1Exists or path2Exists then
            log('I', M.logTag, 'Custom Rally Pacenotes detected an aipacenotes rally')
            M.isAipacenotesRally = true
        end

        if isReversed then
            remainingPath = remainingPath .. '_reverse'
        end

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
        local isReversed = false;
        if userSettings and userSettings.reverse then
            isReversed = userSettings.reverse or false
        end
        setup(mission, isReversed)
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
    -- unknown does not update state - keep the last state
    if curUIState == 'unknown' then
        return;
    end

    log('I', M.logTag, 'ui changed state: ' .. curUIState .. ', ' .. prevUIState)
    M.uiState = curUIState

    M.saveSettings()

    M.guiSendGuiData()
end

local function saveSettings()
    jsonWriteFile('settings/sopo_pacenotes/settings.json', M.settings)
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

        -- check if we are going the wrong way
        M.furthest_distance = math.max(M.furthest_distance, M.last_distance)
        M.backtrack_distance = math.min(M.backtrack_distance, M.last_distance)

        local distanceThreshold = M.is_going_forwards and M.settings.wrong_way_threshold or M.settings.wrong_way_repeat_distance
        if (M.furthest_distance - M.last_distance) >= distanceThreshold then
            log('I', M.logTag, 'wrong way detected')
            M.furthest_distance = M.last_distance
            M.backtrack_distance = M.last_distance
            clearQueue()
            M.is_going_forwards = false

            M.playMicSound('wrong_way')
        end

        if not M.is_going_forwards and (M.last_distance - M.backtrack_distance) >= M.settings.wrong_way_threshold then
            log('I', M.logTag, 'back on track')
            M.is_going_forwards = true
            resetRally(math.min(M.checkpoint_index + 2, #M.checkpoints_array))
            reset_this_tick = true
        end
    end

    M.last_position = position

    if M.is_going_forwards then
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
    end

    M.guiSendRallyData()
end

local function updateAudioQueue(dt)
    -- heavily inspired by pacenotes core mod: https://www.beamng.com/resources/pacenotes-core.10349/

    -- if empty, do nothing
    if #M.audioQueue == 0 then return end

    local currentSound = M.audioQueue[1]

    -- play the sound
    if not currentSound.played and M.rallyId then
        local path = ''
        if currentSound.pacenote then
            path = 'pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes/' .. currentSound.pacenote.wave_name
        else
            path = currentSound.path
        end

        local result = nil
        if not (M.settings.muteOnAiPacenotes and M.isAipacenotesRally) then
            result = Engine.Audio.playOnce('AudioGui', path, {volume=M.settings.sound_data.volume * M.tempPlaybackVolumeMultiplier})
        end

        if result ~= nil then
            currentSound.time = result.len
        else
            currentSound.time = 0
        end
        currentSound.played = true

        if currentSound.pacenote and currentSound.pacenote.analysis then
            currentSound.pacenote.analysis.playStartDistance = M.last_distance
            currentSound.pacenote.analysis.playbackTime = roundNear(currentSound.time, 0.001)
        end

        M.audioQueueClearing = false

    -- track the time of the sound
    else
        currentSound.time = currentSound.time - dt

        local finishedPlaying = currentSound.time <= 0
        local continueCondition = currentSound.pacenote == nil or currentSound.pacenote.continueDistance == nil or currentSound.pacenote.d - currentSound.pacenote.continueDistance <= M.last_distance

        if finishedPlaying and currentSound.pacenote and currentSound.pacenote.analysis and not currentSound.pacenote.analysis.playEndDistance then
            currentSound.pacenote.analysis.playEndDistance = M.last_distance
            M.guiSendPacenoteData()
        end

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
            -- Strip the extension from wave_name to get the base filename
            local baseName = M.pacenotes_data[i].wave_name:match("(.+)%.%w+$")

            -- Construct the paths for both .wav and .ogg extensions
            local wavPath = 'pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes/' .. baseName .. '.wav'
            local oggPath = 'pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes/' .. baseName .. '.ogg'

            -- Check if either file exists and delete it
            if FS:fileExists(wavPath) then
                FS:removeFile(wavPath)
                log('I', M.logTag, 'Deleting pacenote file: ' .. wavPath)
            elseif FS:fileExists(oggPath) then
                FS:removeFile(oggPath)
                log('I', M.logTag, 'Deleting pacenote file: ' .. oggPath)
            end

            -- Delete the pacenote from the list
            table.remove(M.pacenotes_data, i)
        end
    end
    M.guiSendPacenoteData()
end

local function deleteUnusedSounds()
    local files = FS:findFiles('pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes', '*.*', -1, true, false)
    local usedFiles = {}

    -- Collect the names of used files (excluding file extensions)
    for _, pacenote in ipairs(M.pacenotes_data) do
        local fileBaseName = pacenote.wave_name:match("(.+)%..+$") -- Remove extension
        table.insert(usedFiles, fileBaseName)
    end

    for _, file in ipairs(files) do
        local filename = file:match(".+/(.+)$")
        local fileBaseName, fileExtension = filename:match("(.+)%.(%w+)$")  -- Get base name and extension

        -- If the file is unused, delete it
        if not tableContains(usedFiles, fileBaseName) then
            FS:removeFile('pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes/' .. filename)
        else
            log('I', M.logTag, 'Deleting unused sound: ' .. filename)
        end
    end
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

    local new_data = {M.checkpoints_array, M.pacenotes_data}

    if M.rally_metadata ~= nil then
        new_data[3] = M.rally_metadata
    end

    if M.tempPlaybackVolumeMultiplier ~= 1 then
        new_data[3] = new_data[3] or {}
        new_data[3].playbackVolumeMultiplier = M.tempPlaybackVolumeMultiplier
    end

    if M.micId then
        new_data[3] = new_data[3] or {}
        new_data[3].micId = M.micId
    end

    local file = jsonWriteFile('pacenotes_sp/' .. M.levelId .. '/' .. M.rallyId .. '/pacenotes.json', new_data)
    if file then
        log('I', M.logTag, 'saved pacenote data')
        M.guiConfig.isRallyChanged = false
        M.guiSendGuiData()
    else
        log('E', M.logTag, 'failed to save pacenote data')
        guihooks.trigger('toastrMsg', {type = "error", title = "Failed to Save Pacenotes", msg = "", config = {timeOut = 7000}})
    end
end

local function resetAnalysis()
    if M.rallyId == nil then return end

    for _, pacenote in ipairs(M.pacenotes_data) do
        pacenote.analysis = nil
    end
    M.guiSendPacenoteData()
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
        guihooks.trigger('toastrMsg', {type = "warning", title = "Couldn't Connect", msg = "Check that the mic server is running.", config = {timeOut = 7000}})
        M.guiSendMicData()
        return
    end
    log('I', M.logTag, 'connected to server')

    M.guiSendMicData()

    M.serverUpdateDataPath()

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
        -- Get the root path
        local fullPath = FS:getFileRealPath('/')
        fullPath = fullPath:gsub('\\', '/')
        log('I', M.logTag, 'Full path: ' .. fullPath)

        -- Pre 0.37, find the version number.
        -- In all cases, append '/pacenotes_sp' to the path
        local trimmedPath = (fullPath:match("(.-/%d+%.%d+)/") or fullPath:match("(.-/current)/") or fullPath:gsub("/*$", "")) .. '/pacenotes_sp'

        log('I', M.logTag, 'SP Pacenote Path: ' .. trimmedPath)
        M.micServer:send('data_path ' .. trimmedPath .. '\n')
    end
end

local function serverUpdateMission()
    if M.micServer ~= nil then
        M.micServer:send('mission ' .. M.levelId .. '/' .. M.rallyId .. '\n')

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

            M.serverResetCount(maxNumber + 1)
        end
    end
end

local function serverCloseMission()
    if M.micServer ~= nil then
        M.micServer:send('mission_end\n')
    end
end

local function serverDeleteLastPacenote()
    if M.micServer ~= nil then
        M.micServer:send('delete_last_pacenote\n')
    end
end

local function serverResetCount(i)
    if M.micServer ~= nil then
        i = i or 0
        M.micServer:send('reset_count ' .. i .. '\n')
        M.recordingIndex = i
    end
end

-- keybind functions

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
        M.micServer:send('record_start\n')

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
        M.isRecording = false
        M.guiSendMicData()
        return
    end

    if not (M.mode == "rally" or M.mode == "recce") then
        return
    end

    M.micServer:send('record_stop\n')

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

local handleVolumeChange = function(diff)
    M.settings.sound_data.volume = math.min(100, math.max(0, M.settings.sound_data.volume + diff))
    guihooks.trigger('Message', {
        ttl = 3,
        msg = 'Pacenotes volume: ' .. M.settings.sound_data.volume,
        category = 'sopo_pacenotes_volume'
    })
    M.guiSendGuiData()
    M.saveSettings()
end

local handlePacenoteTimingChange = function(diff)
    M.settings.pacenote_playback.lookahead_distance_base = math.min(1000, math.max(0, M.settings.pacenote_playback.lookahead_distance_base + diff))
    guihooks.trigger('Message', {
        ttl = 3,
        msg = 'Pacenotes call distance: ' .. M.settings.pacenote_playback.lookahead_distance_base,
        category = 'sopo_pacenotes_distance'
    })
    M.guiSendMissionData()
    M.saveSettings()
end

local handlePacenoteCarSpeedChange = function(diff)
    M.settings.pacenote_playback.speed_multiplier = math.min(10, math.max(0, M.settings.pacenote_playback.speed_multiplier + diff))
    guihooks.trigger('Message', {
        ttl = 3,
        msg = 'Pacenotes speed sensitivity: ' .. M.settings.pacenote_playback.speed_multiplier,
        category = 'sopo_pacenotes_speed'
    })
    M.guiSendMissionData()
    M.saveSettings()
end

M.handleAipacenotesToggle = function()
    M.settings.muteOnAiPacenotes = not M.settings.muteOnAiPacenotes
    if M.isAipacenotesRally and M.mode == "rally" then
        settings.setValue('rallyAudioPacenotes', M.settings.muteOnAiPacenotes)
    end

    local message = M.settings.muteOnAiPacenotes and 'Pacenotes: BeamNG' or 'Pacenotes: Custom Rally Pacenotes'
    guihooks.trigger('Message', {
        ttl = 3,
        msg = message,
        category = 'sopo_pacenotes_aipacenotes_mute'
    })
    M.saveSettings()
end

local handlePanelToggle = function()
    M.settings.guiPanelStates['main-panel'] = not M.settings.guiPanelStates['main-panel']
    M.guiSendGuiData()
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
    M.guiConfig.guiPanelStates = M.settings.guiPanelStates
    M.guiConfig.guiTableHeight = M.settings.guiTableHeight
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
    guihooks.trigger('PacenoteDataUpdate', {pacenotes_data = M.pacenotes_data, recordAtNote = M.recordAtNote, isAnalyzing = M.isAnalyzing})
end

local function guiSendSelectedPacenote(index)
    guihooks.trigger('PacenoteSelected', {index=index-1})
end

local function guiInit()
    M.guiSendMissionData()
    M.guiSendMicData()
    M.guiSendGuiData()
end

M.playMicSound = playMicSound
M.loadRally = loadRally
M.newRally = newRally
M.loadOrNewRally = loadOrNewRally
M.copyRally = copyRally
M.deleteRally = deleteRally
M.cleanup = cleanup
M.switchRallyFromRecce = switchRallyFromRecce
M.onAnyMissionChanged = onAnyMissionChanged
M.onUiChangedState = onUiChangedState
M.saveSettings = saveSettings
M.onClientPostStartMission = onClientPostStartMission
M.onUpdate = onUpdate
M.deletePacenote = deletePacenote
M.deleteDisabledPacenotes = deleteDisabledPacenotes
M.deleteUnusedSounds = deleteUnusedSounds
M.sortPacenotes = sortPacenotes
M.savePacenoteData = savePacenoteData
M.resetAnalysis = resetAnalysis
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
M.handleVolumeChange = handleVolumeChange
M.handlePacenoteTimingChange = handlePacenoteTimingChange
M.handlePacenoteCarSpeedChange = handlePacenoteCarSpeedChange
M.handlePanelToggle = handlePanelToggle
M.guiSendMissionData = guiSendMissionData
M.guiSendGuiData = guiSendGuiData
M.guiSendMicData = guiSendMicData
M.guiSendRallyData = guiSendRallyData
M.guiSendPacenoteData = guiSendPacenoteData
M.guiSendSelectedPacenote = guiSendSelectedPacenote
M.guiInit = guiInit

return M
