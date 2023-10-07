angular.module('beamng.apps')
.directive('pacenotesEditor', ['$timeout', function ($timeout) {
  return {
    templateUrl: '/ui/modules/apps/pacenotesEditor/app.html',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

      scope.$on('RallyDataUpdate', function(event, args) {
        document.querySelector('#rally-id').innerHTML = args.mission_id;
        document.querySelector('#rally-mode').innerHTML = args.mode;
      });

      scope.connectToMicServer = function () {
        bngApi.engineLua('scripts_sopo__pacenotes_extension.connectToMicServer()')
      }

      $timeout(function () {
        bngApi.engineLua('scripts_sopo__pacenotes_extension.guiInit()');
      }, 0);
    }
  };
}]);
