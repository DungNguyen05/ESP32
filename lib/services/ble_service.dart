import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/device_model.dart';

class BLEService {
  static StreamSubscription? _scanSubscription;
  static final StreamController<List<ESP32Device>> _devicesController = 
      StreamController<List<ESP32Device>>.broadcast();
  
  static List<ESP32Device> _discoveredDevices = [];
  static bool _isScanning = false;
  
  // Stream of discovered ESP32 devices
  static Stream<List<ESP32Device>> get devicesStream => _devicesController.stream;
  
  // Check if Bluetooth is available and enabled
  static Future<bool> isBluetoothAvailable() async {
    try {
      // For web, return false since BLE is not supported
      if (kIsWeb) {
        if (kDebugMode) {
          print("Bluetooth not supported on web platform");
        }
        return false;
      }
      
      if (await FlutterBluePlus.isSupported == false) {
        if (kDebugMode) {
          print("Bluetooth not supported by this device");
        }
        return false;
      }
      
      // Check if Bluetooth is on
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking Bluetooth availability: $e');
      }
      return false;
    }
  }
  
  // Turn on Bluetooth (Android only)
  static Future<void> turnOnBluetooth() async {
    try {
      if (kIsWeb) return; // Not supported on web
      await FlutterBluePlus.turnOn();
    } catch (e) {
      if (kDebugMode) {
        print('Error turning on Bluetooth: $e');
      }
    }
  }
  
  // Scan for ESP32 devices with "GC-" prefix and correct service UUIDs
  static Future<void> startScan({int timeoutSeconds = 30}) async {
    try {
      // For web, simulate some devices for testing UI
      if (kIsWeb) {
        _simulateDevicesForWeb();
        return;
      }
      
      // Check Bluetooth availability
      if (!await isBluetoothAvailable()) {
        throw Exception('Bluetooth không khả dụng hoặc chưa được bật');
      }
      
      // Clear previous devices
      _discoveredDevices.clear();
      _devicesController.add([]);
      _isScanning = true;
      
      // Stop any existing scan
      await stopScan();
      
      if (kDebugMode) {
        print('Starting BLE scan for ESP32 devices...');
      }
      
      // Start scanning with service UUIDs filter
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: timeoutSeconds),
        withServices: [
          Guid('12CE'), // Service UUID 1
          Guid('12CF'), // Service UUID 2
        ],
      );
      
      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          _processScanResults(results);
        },
        onError: (error) {
          if (kDebugMode) {
            print('Scan error: $error');
          }
          _devicesController.addError(error);
          _isScanning = false;
        },
      );
      
      // Auto-stop scan after timeout
      Timer(Duration(seconds: timeoutSeconds), () {
        if (_isScanning) {
          stopScan();
        }
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('Error starting scan: $e');
      }
      _isScanning = false;
      _devicesController.addError(e);
    }
  }
  
  // Simulate devices for web testing
  static void _simulateDevicesForWeb() {
    if (kDebugMode) {
      print('Simulating ESP32 devices for web testing...');
    }
    
    List<ESP32Device> simulatedDevices = [
      ESP32Device(
        name: 'GC-ABC123',
        serialNumber: 'ABC123',
        deviceId: 'web-device-1',
        isRegistered: true,
        rssi: '-45',
      ),
      ESP32Device(
        name: 'GC-DEF456',
        serialNumber: 'DEF456',
        deviceId: 'web-device-2',
        isRegistered: true,
        rssi: '-60',
      ),
    ];
    
    _discoveredDevices = simulatedDevices;
    _devicesController.add(_discoveredDevices);
  }
  
  // Process scan results and filter ESP32 devices với validation async
  static void _processScanResults(List<ScanResult> results) async {
    List<ESP32Device> validDevices = [];
    
    for (ScanResult result in results) {
      String deviceName = result.device.platformName;
      
      // Filter devices with "GC-" prefix
      if (deviceName.isNotEmpty && deviceName.startsWith('GC-')) {
        // Check if device has the correct service UUIDs
        bool hasCorrectService = result.advertisementData.serviceUuids.any(
          (uuid) => uuid.toString().toUpperCase().contains('12CE') || 
                   uuid.toString().toUpperCase().contains('12CF')
        );
        
        if (hasCorrectService) {
          ESP32Device esp32Device = ESP32Device.fromBLEDevice(
            deviceName,
            result.device.remoteId.toString(),
            rssi: result.rssi.toString(),
          );
          
          // Validate device registration with backend
          bool isValidDevice = await esp32Device.validateRegistration();
          
          if (isValidDevice && !validDevices.any((d) => d.deviceId == esp32Device.deviceId)) {
            // Create new device object with correct registration status
            ESP32Device validatedDevice = ESP32Device(
              name: esp32Device.name,
              serialNumber: esp32Device.serialNumber,
              deviceId: esp32Device.deviceId,
              isRegistered: true,
              rssi: esp32Device.rssi,
            );
            
            validDevices.add(validatedDevice);
            
            if (kDebugMode) {
              print('Found and validated ESP32 device: ${validatedDevice.name} (${validatedDevice.serialNumber})');
            }
          } else if (!isValidDevice) {
            if (kDebugMode) {
              print('Device ${esp32Device.name} is not registered or does not belong to current user');
            }
          }
        }
      }
    }
    
    // Update discovered devices if changed
    if (!_listEquals(_discoveredDevices, validDevices)) {
      _discoveredDevices = List.from(validDevices);
      _devicesController.add(_discoveredDevices);
    }
  }
  
  // Helper method to compare device lists
  static bool _listEquals(List<ESP32Device> list1, List<ESP32Device> list2) {
    if (list1.length != list2.length) return false;
    
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].deviceId != list2[i].deviceId) return false;
    }
    
    return true;
  }
  
  // Stop BLE scan
  static Future<void> stopScan() async {
    try {
      _isScanning = false;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      
      if (kIsWeb) return; // No actual scanning on web
      
      // Check if scanning properly
      bool isCurrentlyScanning = await FlutterBluePlus.isScanning.first;
      if (isCurrentlyScanning) {
        await FlutterBluePlus.stopScan();
      }
      
      if (kDebugMode) {
        print('BLE scan stopped');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping scan: $e');
      }
    }
  }
  
  // Get currently discovered devices
  static List<ESP32Device> getDiscoveredDevices() {
    return List.from(_discoveredDevices);
  }
  
  // Check if currently scanning
  static Future<bool> isScanning() async {
    try {
      if (kIsWeb) return _isScanning;
      return await FlutterBluePlus.isScanning.first;
    } catch (e) {
      return false;
    }
  }
  
  // Dispose resources
  static void dispose() {
    _scanSubscription?.cancel();
    _devicesController.close();
    _isScanning = false;
  }
}