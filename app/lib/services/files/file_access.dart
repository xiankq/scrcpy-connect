import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

bool fileCanOpen(Json file) =>
    file['path'] is String &&
    value(file, 'path').isNotEmpty &&
    file['canOpen'] != false;
bool fileCanManage(Json file) =>
    file['path'] is String &&
    value(file, 'path').isNotEmpty &&
    file['canManage'] != false;
String fileUnavailableReason(Json file) =>
    value(file, 'reason', '文件名无法解析为有效路径，暂时无法操作。');
