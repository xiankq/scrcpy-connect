import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';

void main() {
  test('设备记录直接构造与更新共享校验，保留未修改字段并区分明确清空', () {
    final record = DeviceRecord(
      id: '00000000-0000-4000-8000-000000000001',
      name: '  手机  ',
      address: '192.168.1.2',
      port: 5555,
      transport: .tcp,
      battery: 50,
      model: 'model',
      charging: true,
    );
    expect(record.name, '手机');
    final renamed = record.copyWith(name: ' 平板 ', model: null);
    expect(renamed.name, '平板');
    expect(renamed.model, isNull);
    expect(renamed.battery, 50);
    expect(renamed.charging, isTrue);
    expect(record.model, 'model');
    expect(
      () => renamed.copyWith(port: 0),
      throwsA(isA<DeviceRecordsFailure>()),
    );
    expect(
      () => renamed.copyWith(battery: 101),
      throwsA(isA<DeviceRecordsFailure>()),
    );
    expect(
      () => renamed.copyWith(status: 'unknown'),
      throwsA(isA<DeviceRecordsFailure>()),
    );
    expect(DeviceRecord.fromJson(renamed.toJson()).toJson(), renamed.toJson());
  });
}
