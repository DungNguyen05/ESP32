class ESP32Device {
  final String name;
  final String serialNumber;
  final String deviceId;
  final bool isRegistered;
  final String? rssi;
  
  ESP32Device({
    required this.name,
    required this.serialNumber,
    required this.deviceId,
    required this.isRegistered,
    this.rssi,
  });
  
  // Tạo ESP32Device từ BLE scan result
  factory ESP32Device.fromBLEDevice(String name, String deviceId, {String? rssi}) {
    // Extract SN from "GC-<SN>"
    String sn = name.replaceFirst('GC-', '');
    
    return ESP32Device(
      name: name,
      serialNumber: sn,
      deviceId: deviceId,
      isRegistered: _checkDeviceRegistration(sn), // TODO: Implement server check
      rssi: rssi,
    );
  }
  
  // Kiểm tra device có được đăng ký trong hệ thống không
  static bool _checkDeviceRegistration(String serialNumber) {
    // TODO: Implement actual registration check with server/database
    // For now, return true for all devices
    // In production, this should check against your backend API
    return true;
  }
  
  @override
  String toString() {
    return 'ESP32Device{name: $name, sn: $serialNumber, id: $deviceId, registered: $isRegistered}';
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ESP32Device &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}