angular.module('pacenotesEditor', [])
.factory('SharedDataService', function() {
  return {
    rallyPaths: [],
    newRallyId: ''
  };
})
.controller('DropdownController', ['$scope', 'SharedDataService', function(scope, SharedDataService) {
  scope.filteredOptions = [];
  scope.SharedDataService = SharedDataService;

  scope.filterOptions = function() {
    if (SharedDataService.newRallyId !== undefined && SharedDataService.rallyPaths !== undefined) {
      scope.filteredOptions = SharedDataService.rallyPaths.filter(function(option) {
        return option.toLowerCase().includes(SharedDataService.newRallyId.toLowerCase());
      });
    } else {
      scope.filteredOptions = [];
    }
  };

  scope.selectOption = function(option) {
    SharedDataService.newRallyId = option;
    scope.filteredOptions = [];
  };

  scope.onFocus = function() {
    scope.filterOptions();
  };

  scope.onBlur = function() {
    setTimeout(function() {
      scope.$apply(function() {
        scope.filteredOptions = [];
      });
    }, 200);
  };
}]);

angular.module('beamng.apps')
.directive('pacenotesEditor', ['$timeout', 'SharedDataService', function ($timeout, SharedDataService) {
  return {
    templateUrl: '/ui/modules/apps/pacenotesEditor/app.html',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

      scope.panelStates = {};
      scope.pacenotes_data = [];
      scope.level = '';
      scope.rallyId = '';
      scope.mode = 'none';
      scope.isMicServerConnected = false;
      scope.isRecording = false;
      scope.playbackVolume = 10;
      scope.closeIgnoreUnsavedRallyChanges = false;
      scope.SharedDataService = SharedDataService;
      scope.viewMode = 'edit';

      scope.followNote = true;
      scope.recordAtNote = false;
      scope.isAnalyzing = true;

      // editor table:
      scope.selectedRowIndex = null;
      scope.isRallyChanged = false;

      // track table size
      const resizeObserver = new ResizeObserver(entries => {
        // don't update if the panel is collapsed
        if (!document.querySelector('#main-panel').hasAttribute('open')) {
          return;
        }
        for (let entry of entries) {
          const height = entry.contentRect.height;

          // during UI transitions, height can be set to 0 - ignore it
          if (height == 0)
            continue;

          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.guiTableHeight = ${height}`);
        }
      });
      resizeObserver.observe(document.querySelector('#pacenotes-list'));

      let watchEnabled = true;
      let luaUpdatedPacenotes = false;

      scope.toggleMicServerConnection = function () {
        if (scope.isMicServerConnected) {
          bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.disconnectFromMicServer()');
        } else {
          bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.connectToMicServer()');
        }
      }

      scope.deleteLastPacenote = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.serverDeleteLastPacenote()');
      }

      scope.loadRally = function () {
        bngApi.engineLua(`local result = extensions.scripts_sopo__pacenotes_extension.loadRally('${SharedDataService.newRallyId}');
                          if not result then
                            guihooks.trigger('toastrMsg', {type = "error", title = "Couldn't Load Rally", msg = "Check that the file exists, or record a new one.", config = {timeOut = 7000}});
                          end`);
      }

      scope.saveAsRally = function () {
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.copyRally('${SharedDataService.newRallyId}')`);
      }

      scope.newRally = function() {
        // first, check if there's an existing file at 'pacenotes_sp/' .. getCurrentLevelIdentifier() .. '/' .. newRallyId .. '/pacenotes.json' using the lua file system
        bngApi.engineLua(`FS:fileExists('pacenotes_sp/' .. getCurrentLevelIdentifier() .. '/' .. '${SharedDataService.newRallyId}' .. '/pacenotes.json')`, (fileExists) => {
          if (fileExists)
          {
            // file exists, tell the user and don't make new project
            bngApi.engineLua(`guihooks.trigger('toastrMsg', {type = "error", title = "Rally Already Exists", msg = "A new project was not created.", config = {timeOut = 7000}})`);
          }
          else
          {
            // make new project
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.loadOrNewRally('${SharedDataService.newRallyId}')`);
          }
        });
      }

      scope.closeRally = function() {
        if (scope.isRallyChanged && !scope.closeIgnoreUnsavedRallyChanges) {
          bngApi.engineLua(`guihooks.trigger('toastrMsg', {type = "error", title = "Unsaved Changes", msg = "Closing this rally will cause loss of unsaved work.", config = {timeOut = 7000}})`);
          return;
        }

        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.cleanup()`);
      }

      scope.hideCloseCheckbox = function() {
        $timeout(function() {
            const focusedElement = document.activeElement;

            if (focusedElement.id == 'close-rally-button' ||
                focusedElement.id == 'close-changed-rally-toggle' ||
                focusedElement.id == 'close-changed-rally-box-label'
            ) {
              return;
            }

            scope.showCloseCheckbox = false;
            scope.closeIgnoreUnsavedRallyChanges = false;
        }, 200); // Slight delay to allow blur event processing
    };

      scope.saveRally = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.deleteDisabledPacenotes()');
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savePacenoteData()');
      }

      scope.deleteRally = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.deleteRally()');
        scope.deleteConfirmationInput = '';
      }

      scope.clearFilenameInput = function () {
        scope.SharedDataService.newRallyId = '';
      }

      scope.setRallyChanged = function (isRallyChanged) {
        scope.isRallyChanged = isRallyChanged;
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.guiConfig.isRallyChanged = ${isRallyChanged}`);
      }

      scope.toggleViewMode = function () {
        if (scope.viewMode != 'edit') {
          scope.viewMode = 'edit';
        } else {
          scope.viewMode = 'analyze';
        }

        // jump to the selected row
        // new section won't be visible immediately - wait a bit
        // TODO improve
        $timeout(function() {
          if (scope.selectedRowIndex !== null) {
            scope.selectRow(scope.selectedRowIndex, false); 
          }
        }, 100);
      }

      scope.jumpToDistance = function () {
        // find the closest pacenote to the given distance
        let closestIndex = 0;
        let closestDistance = Infinity;
        scope.pacenotes_data.forEach((pacenote, index) => {
          let currentDistance = Math.abs(pacenote.d - scope.distance);
          if (currentDistance < closestDistance) {
            closestDistance = currentDistance;
            closestIndex = index;
          }
        });

        // select the closest row
        scope.selectRow(closestIndex, false);
      }

      scope.handleDelete = function(index) {
        let pacenote = scope.pacenotes_data[index];
        if (pacenote == undefined)
          return;

        if (pacenote.disabled !== undefined)
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${index+1}].disabled = true`);
        else
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${index+1}].disabled = nil`);
      }

      scope.resetAnalysis = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.resetAnalysis()');
      }

      scope.playSound = function(filename) {
        bngApi.engineLua(`Engine.Audio.playOnce('AudioGui', 'pacenotes_sp/' .. getCurrentLevelIdentifier() .. '/' .. extensions.scripts_sopo__pacenotes_extension.rallyId .. '/pacenotes/${filename}', {volume=extensions.scripts_sopo__pacenotes_extension.settings.sound_data.volume * extensions.scripts_sopo__pacenotes_extension.tempPlaybackVolumeMultiplier})`);
      }

      // Watched variables
      scope.$watch('playbackLookahead', function(newVal, oldVal) {
        if (newVal !== oldVal) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.pacenote_playback.lookahead_distance_base = ${newVal}`);
        }
      });

      scope.$watch('speedMultiplier', function(newVal, oldVal) {
        if (newVal !== oldVal) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.pacenote_playback.speed_multiplier = ${newVal}`);
        }
      });

      scope.$watch('playbackVolume', function(newVal, oldVal) {
        if (newVal !== oldVal && newVal !== undefined) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.sound_data.volume = ${newVal}`);
        }
      });

      scope.$watch('recordAtNote', function(newVal, oldVal) {
        if (newVal !== oldVal && watchEnabled) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordAtNote = ${newVal}`);

          if (newVal) {
            const distance = scope.pacenotes_data[scope.selectedRowIndex].d;
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordingDistance = ${distance}`);
          }
        }
      });

      scope.$watch('isAnalyzing', function(newVal, oldVal) {
        if (newVal !== oldVal && watchEnabled) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.isAnalyzing = ${newVal}`);
        }
      });

      scope.$watch('pacenotes_data[selectedRowIndex].d', function (newVal, oldVal) {
        if (newVal !== oldVal && scope.recordAtNote) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordingDistance = ${newVal}`);
        }
      });

      scope.$watch('pacenotes_data', function(newVal, oldVal) {

        let userChanged = true;
        if (luaUpdatedPacenotes) {
          luaUpdatedPacenotes = false;
          userChanged = false;
        }

        if (!newVal)
          return;
        if (!watchEnabled)
          return;
        if (scope.selectedRowIndex === null)
          return;

        // assume that only the current row is being edited
        let pacenote = newVal[scope.selectedRowIndex];

        if (pacenote === undefined)
          return;

        // only update the appropriate values
        if (pacenote.name == '' || pacenote.name === undefined)
        {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].name = nil`);
        }
        else
        {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].name = "${pacenote.name}"`);
        }

        if (pacenote.continueDistance !== undefined)
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].continueDistance = ${pacenote.continueDistance}`);
        else
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].continueDistance = nil`);

        scope.handleDelete(scope.selectedRowIndex);
        if (oldVal && oldVal[scope.selectedRowIndex] && pacenote.d !== oldVal[scope.selectedRowIndex].d)
        {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].d = ${pacenote.d}`);
          bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.sortPacenotes()');
        }

        if (userChanged)
          scope.setRallyChanged(true);
      }, true); // deep watch: true

      scope.selectRow = function (index, playSound = true) {
        if (scope.selectedRowIndex === index && playSound) {
          return;
        }

        // check if the current continue distance field is focused
        if (document.querySelector('#continue-distance').contains(document.activeElement) && document.querySelector('#continue-distance').value !== '') {
          // set the value and clear the input
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].continueDistance = ${document.querySelector('#continue-distance').value}`);

          document.querySelector('#continue-distance').value = '';
        }

        if (scope.pacenotes_data.length > index) {
          scope.selectedRowIndex = index;

          // after angular updates, scroll the selected row into view
          $timeout(() => {
            const selectedItem = document.querySelectorAll(`.pacenote-data-representation[data-index="${index}"]`);
            // for all, scroll into view if visible
            for (let i = 0; i < selectedItem.length; i++) {
              const element = selectedItem[i];
              if (element.offsetParent !== null) {
                element.scrollIntoViewIfNeeded();
              }
            }
          }, 100);

          if (playSound && index !== null)
            scope.playSound(scope.pacenotes_data[index].wave_name);
          }
        }

      scope.deleteContinueDistance = function () {
        if (scope.selectedRowIndex === null) { return }

        delete scope.pacenotes_data[scope.selectedRowIndex].continueDistance;
        scope.setRallyChanged(true);
      }

      scope.deletePacenote = function (index) {
        index = index !== undefined ? index : scope.selectedRowIndex;
        if (index === null) { return }

        // toggle the disabled flag
        if (scope.pacenotes_data[index].disabled === undefined) {
          scope.pacenotes_data[index].disabled = true;
        } else {
          delete scope.pacenotes_data[index].disabled;
        }

        // if the pacenote isn't the selected one, play the sound
        if (index !== scope.selectedRowIndex) {
          scope.playSound(scope.pacenotes_data[index].wave_name);
        }

        scope.handleDelete(index);

        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiSendPacenoteData()');

        scope.setRallyChanged(true);
      }

      scope.setSaveRecce = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savingRecce = true');
        document.querySelector('#recce-save').disabled = true;
        document.querySelector('#recce-save').textContent = 'Auto-saving...';

        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savePacenoteData()');
      }

      scope.recceFinalize = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.switchRallyFromRecce()');
      }

      // gui hooks

      scope.$on('MissionDataUpdate', function(event, args) {
        scope.level = args.level;
        scope.rallyId = args.rallyId;
        SharedDataService.rallyPaths = args.rallyPaths;
        scope.mode = args.mode;

        if (scope.mode === 'recce' && scope.viewMode === 'analyze') {
          scope.toggleViewMode();
        }

        document.querySelector('#playback-lookahead').value = args.playback_lookahead;
        document.querySelector('#speed-multiplier').value = args.speed_multiplier;

        document.querySelector('#recce-save').disabled = false;
        document.querySelector('#recce-save').textContent = 'Save Recce';
      });

      scope.$on('GuiDataUpdate', function(event, args) {
        watchEnabled = false;

        scope.panelStates = args.guiPanelStates;
        scope.isRallyChanged = args.isRallyChanged;
        scope.playbackVolume = args.playbackVolume;

        // apply guiPanelStates
        for (const panel in scope.panelStates) {
          const panelElement = document.querySelector(`#${panel}`);
          if (panelElement) {
            if (scope.panelStates[panel]) {
              panelElement.setAttribute('open', '');
            } else {
              panelElement.removeAttribute('open');
            }
          }
        }

        document.querySelector('#pacenotes-list').style.height = args.guiTableHeight + 'px';

        watchEnabled = true;
      });

      scope.$on('MicDataUpdate', function(event, args) {
        scope.isMicServerConnected = args.connected;
        scope.isRecording = args.isRecording;
        const recordingLamp = document.querySelector('.recording-lamp');
        recordingLamp.classList.toggle('is-recording', args.isRecording);
      });

      scope.$on('RallyDataUpdate', function(event, args) {
        scope.distance = args.distance;
      });

      scope.$on('PacenoteDataUpdate', function(event, args) {
        watchEnabled = false;
        luaUpdatedPacenotes = true;

        scope.recordAtNote = args.recordAtNote;
        scope.isAnalyzing = args.isAnalyzing;
        scope.pacenotes_data = args.pacenotes_data;
        if (scope.pacenotes_data !== undefined && scope.selectedRowIndex == scope.pacenotes_data.length - 1)
          scope.selectRow(scope.selectedRowIndex, false);

        watchEnabled = true;
      });

      scope.$on('PacenoteSelected', function(event, args) {
        if (!scope.followNote)
          return;

        if (scope.pacenotes_data.length > args.index) {
          scope.selectRow(args.index, false);
        }
      });

      // Cleanup on destroy
      scope.$on('$destroy', () => {
        resizeObserver.disconnect();
      });

      element.ready(function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiInit()');

        document.querySelectorAll('details[id]').forEach(panel => {
              panel.addEventListener('toggle', (event) => {
              scope.panelStates[panel.id] = event.target.hasAttribute('open');
              bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.guiPanelStates['${panel.id}'] = ${scope.panelStates[panel.id]}`);

              // if the main panel was opened, jump to the selected row
              if (panel.id === 'main-panel' && event.target.hasAttribute('open') && scope.selectedRowIndex !== null) {
                scope.selectRow(scope.selectedRowIndex, false);
              }
            });
        });
      });
    }
  };
}]);
