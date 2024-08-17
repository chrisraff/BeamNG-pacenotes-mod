angular.module('beamng.apps')
.controller('DropdownController', ['$scope', function(scope) {
  scope.filteredOptions = [];

  scope.filterOptions = function() {
    if (scope.newRallyId !== undefined) {
      scope.filteredOptions = scope.rallyPaths.filter(function(option) {
        return option.toLowerCase().includes(scope.newRallyId.toLowerCase());
      });
    } else {
      scope.filteredOptions = [];
    }
  };

  scope.selectOption = function(option) {
    scope.newRallyId = option;
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
}])
.directive('pacenotesEditor', ['$timeout', function ($timeout) {
  return {
    templateUrl: '/ui/modules/apps/pacenotesEditor/app.html',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

      scope.pacenotes_data = {};
      scope.level = '';
      scope.rallyId = '';
      scope.rallyPaths = [];
      scope.mode = 'none';
      scope.isMicServerConnected = false;

      scope.followNote = true;

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
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.loadRally('${scope.newRallyId}')`);
      }

      scope.saveAsRally = function () {
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.copyRally('${scope.newRallyId}')`);
      }

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

      scope.selectRow = function (index) {
        if (scope.selectedRowIndex === index) {
          return;
        }
        scope.selectedRowIndex = index;
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
        scope.rallyPaths = args.rallyPaths;
        scope.mode = args.mode;

        document.querySelector('#playback-lookahead').value = args.playback_lookahead;
        document.querySelector('#speed-multiplier').value = args.speed_multiplier;

        document.querySelector('#recce-save').disabled = false;
        document.querySelector('#recce-save').textContent = 'Save Recce';
      });

      scope.$on('GuiDataUpdate', function(event, args) {
        document.querySelector('.pacenotes-editor #main-panel').open = args.panelOpen;
        scope.isRallyChanged = args.isRallyChanged;
      });

      scope.$on('MicDataUpdate', function(event, args) {
        scope.isMicServerConnected = args.connected;
      });

      scope.$on('RallyDataUpdate', function(event, args) {
        scope.distance = args.distance;
      });

      scope.$on('PacenoteDataUpdate', function(event, args) {
        watchEnabled = false;
        scope.pacenotes_data = args.pacenotes_data;
        watchEnabled = true;
      });

      scope.$on('PacenoteSelected', function(event, args) {
        if (!scope.followNote)
          return;

        scope.selectedRowIndex = args.index;
        document.querySelector('#pacenotes-list tbody').children[args.index].scrollIntoViewIfNeeded();
      });

      scope.$on('$destroy', function() {
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.guiConfig.panelOpen = ${document.querySelector('#main-panel').open};`);
      });

      element.ready(function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiInit()');
      });
    }
  };
}]);
