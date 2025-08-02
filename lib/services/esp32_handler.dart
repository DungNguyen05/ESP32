import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

class ESP32Handler {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _wifiListChar; // CE01 - Read WiFi list
  BluetoothCharacteristic? _wifiConfigChar; // CE02 - Write WiFi config & receive notifications
  
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _notificationSubscription;
  final StreamController<String> _notificationController = 
      StreamController<String>.broadcast();
  
  bool _isConnected = false;
  
  // Stream for notifications from ESP32
  Stream<String> get notificationStream => _notificationController.stream;
  
  // Check if connected to device
  bool get isConnected => _isConnected;
  
  // Connect to ESP32 device
  Future<bool> connectToDevice(String deviceId) async {
    try {
      if (kDebugMode) {
        print('Attempting to connect to device: $deviceId');
      }
      
      // Get device instance
      BluetoothDevice device = BluetoothDevice.fromId(deviceId);
      
      // Connect with timeout
      await device.connect(timeout: Duration(seconds: 15));
      _connectedDevice = device;
      
      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        _isConnected = state == BluetoothConnectionState.connected;
        if (kDebugMode) {
          print('Connection state changed: $state');
        }
        
        if (!_isConnected) {
          _cleanup();
        }
      });
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      if (kDebugMode) {
        print('Discovered ${services.length} services');
        for (var service in services) {
          print('Service UUID: ${service.uuid}');
        }
      }
      
      // Find services 12CE and 12CF
      BluetoothService? serviceForRead;
      BluetoothService? serviceForWrite;
      
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toUpperCase();
        if (kDebugMode) {
          print('Checking service: $serviceUuid');
        }
        
        if (serviceUuid.contains('12CE')) {
          serviceForRead = service;
          if (kDebugMode) {
            print('Found service 12CE for reading WiFi list');
          }
        } else if (serviceUuid.contains('12CF')) {
          serviceForWrite = service;
          if (kDebugMode) {
            print('Found service 12CF for WiFi configuration');
          }
        }
      }
      
      if (serviceForRead == null && serviceForWrite == null) {
        if (kDebugMode) {
          print('No target services 12CE or 12CF found');
        }
        await disconnect();
        return false;
      }
      
      // Find characteristics CE01 in service 12CE (for reading WiFi list)
      if (serviceForRead != null) {
        for (BluetoothCharacteristic char in serviceForRead.characteristics) {
          String charUuid = char.uuid.toString().toUpperCase();
          
          if (charUuid.contains('CE01') && char.properties.read) {
            _wifiListChar = char;
            if (kDebugMode) {
              print('Found CE01 (WiFi list) characteristic: $charUuid');
            }
            break;
          }
        }
      }
      
      // Find characteristics CE02 in service 12CF (for writing WiFi config and notifications)
      if (serviceForWrite != null) {
        for (BluetoothCharacteristic char in serviceForWrite.characteristics) {
          String charUuid = char.uuid.toString().toUpperCase();
          
          if (charUuid.contains('CE02')) {
            _wifiConfigChar = char;
            
            // Enable notifications on CE02
            if (char.properties.notify || char.properties.indicate) {
              try {
                await char.setNotifyValue(true);
                
                _notificationSubscription = char.onValueReceived.listen(
                  (value) {
                    String message = String.fromCharCodes(value);
                    if (kDebugMode) {
                      print('Received notification from CE02: $message');
                    }
                    _notificationController.add(message);
                  },
                  onError: (error) {
                    if (kDebugMode) {
                      print('CE02 notification error: $error');
                    }
                  },
                );
                
                if (kDebugMode) {
                  print('Found CE02 (WiFi config + notification) characteristic: $charUuid');
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Could not enable notifications on CE02: $e');
                }
              }
            }
            break;
          }
        }
      }
      
      // Check if we found required characteristics
      bool success = _wifiConfigChar != null;
      
      if (success) {
        _isConnected = true;
        if (kDebugMode) {
          print('Successfully connected to ESP32');
          print('WiFi list char (CE01): ${_wifiListChar?.uuid ?? "Not found"}');
          print('WiFi config char (CE02): ${_wifiConfigChar?.uuid ?? "Not found"}');
        }
      } else {
        if (kDebugMode) {
          print('No suitable characteristics found for WiFi configuration');
        }
        await disconnect();
      }
      
      return success;
      
    } catch (e) {
      if (kDebugMode) {
        print('Connection error: $e');
      }
      await disconnect();
      return false;
    }
  }
  
  // Read WiFi list from CE01
  Future<List<String>> readWiFiList() async {
    if (_wifiListChar == null) {
      if (kDebugMode) {
        print('No characteristic available for reading WiFi list');
      }
      return [];
    }
    
    try {
      if (kDebugMode) {
        print('Reading WiFi list from ${_wifiListChar!.uuid}...');
      }
      
      List<int> value = await _wifiListChar!.read();
      String data = String.fromCharCodes(value);
      
      if (kDebugMode) {
        print('WiFi list raw data: $data');
        print('WiFi list bytes: ${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }
      
      // Parse WiFi list - handle 0x06 separator correctly
      List<String> networks = [];
      
      // The data uses 0x06 as separator
      if (value.contains(0x06)) {
        // Split by 0x06 byte
        List<List<int>> networkBytes = [];
        List<int> currentNetwork = [];
        
        for (int byte in value) {
          if (byte == 0x06) {
            if (currentNetwork.isNotEmpty) {
              networkBytes.add(List.from(currentNetwork));
              currentNetwork.clear();
            }
          } else {
            currentNetwork.add(byte);
          }
        }
        
        // Add the last network if any
        if (currentNetwork.isNotEmpty) {
          networkBytes.add(currentNetwork);
        }
        
        // Convert byte arrays to strings
        networks = networkBytes
            .map((bytes) => String.fromCharCodes(bytes).trim())
            .where((s) => s.isNotEmpty)
            .toList();
        
        if (kDebugMode) {
          print('Parsed ${networks.length} WiFi networks using 0x06 separator: $networks');
        }
      }
      // Fallback parsing methods
      else if (data.contains(',')) {
        networks = data.split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.contains('\x00'))
            .toList();
        if (kDebugMode) {
          print('Parsed ${networks.length} WiFi networks using comma separator: $networks');
        }
      }
      else if (data.contains('\n')) {
        networks = data.split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.contains('\x00'))
            .toList();
        if (kDebugMode) {
          print('Parsed ${networks.length} WiFi networks using newline separator: $networks');
        }
      }
      else if (data.trim().isNotEmpty) {
        networks = [data.trim()];
        if (kDebugMode) {
          print('Parsed single WiFi network: $networks');
        }
      }
      
      return networks;
      
    } catch (e) {
      if (kDebugMode) {
        print('Error reading WiFi list: $e');
      }
      return [];
    }
  }
  
  // Send WiFi credentials using format: "_UWF:<ssid>0x06<password>0x04"
  Future<bool> sendWiFiCredentials(String ssid, String password) async {
    if (_wifiConfigChar == null) {
      if (kDebugMode) {
        print('WiFi config characteristic not available');
      }
      return false;
    }
    
    try {
      if (kDebugMode) {
        print('Sending WiFi credentials - SSID: $ssid, Password: ${password.replaceAll(RegExp(r'.'), '*')}');
      }
      
      // Format: "_UWF:<ssid>0x06<password>0x04"
      List<int> data = [];
      data.addAll('_UWF:'.codeUnits);   // Command prefix
      data.addAll(ssid.codeUnits);      // WiFi SSID
      data.add(0x06);                   // Separator byte
      data.addAll(password.codeUnits);  // WiFi password
      data.add(0x04);                   // End command byte
      
      if (kDebugMode) {
        print('Sending WiFi config data to ${_wifiConfigChar!.uuid}:');
        print('Format: "_UWF:<ssid>0x06<password>0x04"');
        print('Hex: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('Data length: ${data.length} bytes');
      }
      
      await _wifiConfigChar!.write(data, withoutResponse: false);
      
      if (kDebugMode) {
        print('WiFi credentials sent successfully to ESP32');
        print('ESP32 should now attempt to connect to WiFi and send "Wifi_OK" notification within 40 seconds');
      }
      
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('Error sending WiFi credentials: $e');
      }
      return false;
    }
  }
  
  // Send END command using format: "_END.*0x04"
  Future<bool> sendEndCommand() async {
    if (_wifiConfigChar == null) {
      if (kDebugMode) {
        print('WiFi config characteristic not available for END command');
      }
      return false;
    }
    
    try {
      if (kDebugMode) {
        print('Sending END command to complete WiFi setup process...');
      }
      
      // Format: "_END.*" with 0x04 end byte
      List<int> data = '_END.*'.codeUnits;
      data.add(0x04); // End command byte
      
      if (kDebugMode) {
        print('Sending END command data to ${_wifiConfigChar!.uuid}:');
        print('Format: "_END.*0x04"');
        print('Hex: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('Data length: ${data.length} bytes');
      }
      
      await _wifiConfigChar!.write(data, withoutResponse: false);
      
      if (kDebugMode) {
        print('END command sent successfully to ESP32');
        print('WiFi setup process should now be complete');
      }
      
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('Error sending END command: $e');
      }
      return false;
    }
  }
  
  // Disconnect from device
  Future<void> disconnect() async {
    try {
      if (kDebugMode) {
        print('Disconnecting from ESP32 device...');
      }
      
      await _cleanup();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      
      if (kDebugMode) {
        print('Successfully disconnected from ESP32');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('Error during ESP32 disconnect: $e');
      }
    } finally {
      _connectedDevice = null;
      _wifiListChar = null;
      _wifiConfigChar = null;
      _isConnected = false;
    }
  }
  
  // Cleanup subscriptions
  Future<void> _cleanup() async {
    await _connectionSubscription?.cancel();
    await _notificationSubscription?.cancel();
    
    _connectionSubscription = null;
    _notificationSubscription = null;
  }
  
  // Dispose resources
  void dispose() {
    _cleanup();
    _notificationController.close();
    disconnect();
  }
}