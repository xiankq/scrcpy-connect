import 'package:scrcpy_connect/services/app_controller.dart';

Json transferView(AppController controller, Json task) {
  final matches = controller.snapshot().devices.where(
    (d) => d['id'] == task['deviceId'],
  );
  final name = matches.isEmpty
      ? value(task, 'deviceName', '被控设备')
      : deviceName(matches.first);
  final pulling = task['direction'] == 'pull';
  return {
    ...task,
    if (task['kind'] == 'directory' &&
        task['status'] == 'completed' &&
        task['treeVerified'] != true)
      'status': 'finalizing',
    if (task['kind'] == 'directory' &&
        task['status'] == 'completed' &&
        task['treeVerified'] == true &&
        task['canExport'] == false)
      'status': 'partial',
    'totalBytes': task['totalBytes'] ?? task['total'],
    'completedBytes': task['completedBytes'] ?? task['transferred'],
    'sourceLabel': task['sourceLabel'] ?? (pulling ? name : '本机'),
    'destinationLabel':
        task['destinationLabel'] ??
        (pulling
            ? task['destinationScope'] == 'privateCache'
                  ? '本机暂存'
                  : value(task, 'destination')
            : name),
    'localPath':
        pulling && task['status'] == 'completed' && task['canExport'] == true
        ? task['localPath'] ?? task['destination']
        : null,
  };
}
