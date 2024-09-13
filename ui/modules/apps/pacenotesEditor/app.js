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
    if (SharedDataService.newRallyId !== undefined) {
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

      scope.panelOpen = true;
      scope.pacenotes_data = [];
      scope.level = '';
      scope.rallyId = '';
      scope.mode = 'none';
      scope.isMicServerConnected = false;
      scope.isRecording = false;
      scope.playbackVolume = 10;
      scope.closeIgnoreUnsavedRallyChanges = false;
      scope.SharedDataService = SharedDataService;

      scope.followNote = true;
      scope.recordAtNote = false;

      // editor table:
      scope.selectedRowIndex = null;
      scope.isRallyChanged = false;

      let watchEnabled = true;

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
        // first, check if there's an existing file at 'art/sounds/' .. getCurrentLevelIdentifier() .. '/' .. newRallyId .. '/pacenotes.json' using the lua file system
        bngApi.engineLua(`FS:fileExists('art/sounds/' .. getCurrentLevelIdentifier() .. '/' .. '${SharedDataService.newRallyId}' .. '/pacenotes.json')`, (fileExists) => {
          if (fileExists)
          {
            // file exists, tell the user and don't make new project
            bngApi.engineLua(`guihooks.trigger('toastrMsg', {type = "error", title = "Rally Already Exists", msg = "A new project was not created.", config = {timeOut = 7000}})`);
          }
          else
          {
            // make new project
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.newRally('${SharedDataService.newRallyId}')`);
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

      scope.setRallyChanged = function (isRallyChanged) {
        scope.isRallyChanged = isRallyChanged;
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.guiConfig.isRallyChanged = ${isRallyChanged}`);
      }

      scope.jumpToDistance = function () {
        // find the closest pacenote to the given distance
        let distances = document.querySelectorAll('.distance');
        let closestIndex = 0;
        let closestDistance = Math.abs(distances[0].querySelector('input').value - scope.distance);
        distances.forEach((distance, index) => {
          let currentDistance = Math.abs(distance.querySelector('input').value - scope.distance);
          if (currentDistance < closestDistance) {
            closestDistance = currentDistance;
            closestIndex = index;
          }
        });

        // scroll into view
        distances[closestIndex].scrollIntoViewIfNeeded();
      }

      // Watched variables
      scope.$watch('panelOpen', function(newVal, oldVal) {
        if (newVal !== oldVal) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.guiConfig.panelOpen = ${newVal}`);
        }
      })

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
        if (newVal !== oldVal) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.settings.sound_data.volume = ${newVal}`);
        }
      });

      scope.$watch('recordAtNote', function(newVal, oldVal) {
        if (newVal !== oldVal) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordAtNote = ${newVal}`);

          if (newVal) {
            const distance = scope.pacenotes_data[scope.selectedRowIndex].d;
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordingDistance = ${distance}`);
          }
        }
      });

      scope.$watch('pacenotes_data[selectedRowIndex].d', function (newVal, oldVal) {
        if (newVal !== oldVal && scope.recordAtNote) {
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.recordingDistance = ${newVal}`);
        }
      });

      scope.$watch('pacenotes_data', function(newVal) {
        if (newVal && watchEnabled && scope.selectedRowIndex !== null) {
          // assume that only the current row is being edited
          let pacenote = newVal[scope.selectedRowIndex];

          // only update the appropriate values
          bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].d = ${pacenote.d}`);
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

          if (pacenote.disabled !== undefined)
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].disabled = true`);
          else
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].disabled = nil`);

          bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.sortPacenotes()');

          scope.setRallyChanged(true);
        }
      }, true); // deep watch: true

      scope.selectRow = function (index, playSound = true) {
        if (scope.selectedRowIndex === index) {
          return;
        }
        scope.selectedRowIndex = index;

        if (playSound && index !== null && scope.pacenotes_data.length > index)
          bngApi.engineLua(`Engine.Audio.playOnce('AudioGui', 'art/sounds/' .. getCurrentLevelIdentifier() .. '/' .. extensions.scripts_sopo__pacenotes_extension.rallyId .. '/pacenotes/${scope.pacenotes_data[index].wave_name}', extensions.scripts_sopo__pacenotes_extension.settings.sound_data)`);
      }

      scope.deleteContinueDistance = function () {
        if (scope.selectedRowIndex === null) { return }

        delete scope.pacenotes_data[scope.selectedRowIndex].continueDistance;
        scope.setRallyChanged(true);
      }

      scope.deletePacenote = function () {
        if (scope.selectedRowIndex === null) { return }

        // toggle the disabled flag
        if (scope.pacenotes_data[scope.selectedRowIndex].disabled === undefined) {
          scope.pacenotes_data[scope.selectedRowIndex].disabled = true;
        } else {
          delete scope.pacenotes_data[scope.selectedRowIndex].disabled;
        }

        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiSendPacenoteData()');

        scope.setRallyChanged(true);
      }

      scope.setSaveRecce = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savingRecce = true');
        document.querySelector('#recce-save').disabled = true;
        document.querySelector('#recce-save').textContent = 'Auto-saving...';

        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savePacenoteData()');
      }

      // gui hooks

      scope.$on('MissionDataUpdate', function(event, args) {
        scope.level = args.level;
        scope.rallyId = args.rallyId;
        SharedDataService.rallyPaths = args.rallyPaths;
        scope.mode = args.mode;

        document.querySelector('#playback-lookahead').value = args.playback_lookahead;
        document.querySelector('#speed-multiplier').value = args.speed_multiplier;

        document.querySelector('#recce-save').disabled = false;
        document.querySelector('#recce-save').textContent = 'Save Recce';
      });

      scope.$on('GuiDataUpdate', function(event, args) {
        watchEnabled = false;
        scope.panelOpen = args.panelOpen;
        scope.isRallyChanged = args.isRallyChanged;
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
        scope.pacenotes_data = args.pacenotes_data;
        if (scope.selectedRowIndex == scope.pacenotes_data.length - 1)
          scope.selectRow(scope.selectedRowIndex, false);
        watchEnabled = true;
      });

      scope.$on('PacenoteSelected', function(event, args) {
        if (!scope.followNote)
          return;

        scope.selectedRowIndex = args.index;
        document.querySelector('#pacenotes-list tbody').children[args.index].scrollIntoViewIfNeeded();
      });

      element.ready(function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiInit()');

        document.querySelector('#main-panel').addEventListener('toggle', (event) => {
          scope.panelOpen = event.target.hasAttribute('open');
        });
      });
    }
  };
}]);
