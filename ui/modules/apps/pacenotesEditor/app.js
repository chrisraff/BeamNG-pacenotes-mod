angular.module('beamng.apps')
.directive('pacenotesEditor', ['$timeout', function ($timeout) {
  return {
    templateUrl: '/ui/modules/apps/pacenotesEditor/app.html',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

      scope.pacenotes_data = {};

      // editor table:
      scope.selectedRowIndex = null;

      let watchEnabled = true;

      scope.updateMicConnection = function (connected) {
        const button = document.querySelector('#connect-to-mic-server');
        button.disabled = connected;
        button.textContent = connected ? 'Connected' : 'Connect to Mic Server';
      }

      scope.connectToMicServer = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.connectToMicServer()');
      }

      scope.deleteLastPacenote = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.serverDeleteLastPacenote()');
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
          if (pacenote.name !== undefined)
          {
            bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.pacenotes_data[${scope.selectedRowIndex+1}].name = "${pacenote.name}"`);
          }

          bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.sortPacenotes()');
        }
      }, true); // deep watch: true

      scope.selectRow = function (index) {
        scope.selectedRowIndex = index;
      }

      scope.deletePacenote = function () {
        bngApi.engineLua(`extensions.scripts_sopo__pacenotes_extension.deletePacenote(${scope.selectedRowIndex + 1})`);
      }

      scope.setSaveRecce = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.savingRecce = true');
        document.querySelector('#recce-save').disabled = true;
        document.querySelector('#recce-save').textContent = 'Auto-saving...';

        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.saveRecce()');
      }

      // gui hooks

      scope.$on('MissionDataUpdate', function(event, args) {
        document.querySelector('#rally-id').innerHTML = args.mission_id;
        document.querySelector('#rally-mode').innerHTML = args.mode;

        document.querySelector('#playback-lookahead').value = args.playback_lookahead;
        document.querySelector('#speed-multiplier').value = args.speed_multiplier;

        document.querySelector('#recce-content').classList.toggle('hide', args.mode !== 'recce');
        document.querySelector('#recce-save').disabled = false;
        document.querySelector('#recce-save').textContent = 'Save Recce';
      });

      scope.$on('MicDataUpdate', function(event, args) {
        scope.updateMicConnection(args.connected);
      });

      scope.$on('RecceDataUpdate', function(event, args) {
        document.querySelector('#distance').innerHTML = args.distance;
        document.querySelector('#pacenotes-count').innerHTML = args.pacenoteNumber;
      });

      scope.$on('PacenoteDataUpdate', function(event, args) {
        watchEnabled = false;
        scope.pacenotes_data = args.pacenotes_data;
        watchEnabled = true;
      });

      scope.$on('PacenoteSelected', function(event, args) {
        scope.selectedRowIndex = args.index;
        document.querySelector('#pacenotes-list tbody').children[args.index].scrollIntoViewIfNeeded();
      });

      element.ready(function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiInit()');
      });
    }
  };
}]);
