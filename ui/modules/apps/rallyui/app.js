angular.module('beamng.apps')
.directive('pacenotesEditor', ['$timeout', function ($timeout) {
  return {
    templateUrl: '/ui/modules/apps/pacenotesEditor/app.html',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

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

      scope.saveRecce = function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.saveRecce()');
      }

      scope.$on('MissionDataUpdate', function(event, args) {
        document.querySelector('#rally-id').innerHTML = args.mission_id;
        document.querySelector('#rally-mode').innerHTML = args.mode;

        document.querySelector('#recce-content').classList.toggle('hide', args.mode !== 'recce');
      });
      scope.$on('MicDataUpdate', function(event, args) {
        scope.updateMicConnection(args.connected);
      });

      $timeout(function () {
        bngApi.engineLua('extensions.scripts_sopo__pacenotes_extension.guiInit()');
      }, 0);
    }
  };
}]);
