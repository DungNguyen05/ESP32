import '../services/api_service.dart';

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
      isRegistered: true, // Sẽ được validate async sau này
      rssi: rssi,
    );
  }
  
  // Kiểm tra device có được đăng ký trong hệ thống không
  static Future<bool> checkDeviceRegistration(String serialNumber) async {
    try {
      // Gọi API thực tế để kiểm tra registration
      return await ApiService.checkDeviceRegistration(serialNumber);
    } catch (e) {
      print('Error checking device registration: $e');
      return false; // Không cho phép nếu không kiểm tra được
    }
  }
  
  // Validate device async
  Future<bool> validateRegistration() async {
    return await checkDeviceRegistration(serialNumber);
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