import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

class ESP32Handler {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _wifiListChar; // CE01 - Read WiFi list
  BluetoothCharacteristic? _wifiConfigChar; // CF02 - Write WiFi config & receive notifications
  
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
      
      // Check BOTH services 12CE and 12CF
      List<BluetoothService> targetServices = [];
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toUpperCase();
        if (kDebugMode) {
          print('Checking service: $serviceUuid');
        }
        
        if (serviceUuid.contains('12CE') || serviceUuid.contains('12CF')) {
          targetServices.add(service);
          if (kDebugMode) {
            print('Found target service: $serviceUuid');
          }
        }
      }
      
      if (targetServices.isEmpty) {
        if (kDebugMode) {
          print('No target services found');
        }
        await disconnect();
        return false;
      }
      
      
      // List all available characteristics from ALL target services
      if (kDebugMode) {
        print('Scanning characteristics in all target services:');
        for (BluetoothService service in targetServices) {
          print('Service ${service.uuid}:');
          for (BluetoothCharacteristic char in service.characteristics) {
            print('  - UUID: ${char.uuid}');
            print('    Properties: Read=${char.properties.read}, Write=${char.properties.write}, Notify=${char.properties.notify}');
          }
        }
      }
      
      // Find characteristics CE01 and CF02 in ALL target services
      for (BluetoothService service in targetServices) {
        String serviceUuid = service.uuid.toString().toUpperCase();
        
        for (BluetoothCharacteristic char in service.characteristics) {
          String charUuid = char.uuid.toString().toUpperCase();
          
          if (charUuid.contains('CE01')) {
            // WiFi list characteristic (read WiFi networks) - in 12CE service
            _wifiListChar = char;
            if (kDebugMode) {
              print('Found CE01 (WiFi list) in service $serviceUuid: $charUuid');
            }
          } else if (charUuid.contains('CE02')) {
            // CE02 for notifications only (no write capability)
            if (char.properties.notify || char.properties.indicate) {
              try {
                await char.setNotifyValue(true);
                
                // Listen for notifications on CE02
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
                  print('Found CE02 (notification channel) in service $serviceUuid and enabled notifications: $charUuid');
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Could not enable notifications on CE02: $e');
                }
              }
            }
          }
          // Use CF02 for WiFi configuration writing (has write capability)
          else if (charUuid.contains('CE02')) {
            _wifiConfigChar = char;
            
            // Enable notifications on CF02 as backup notification channel
            if (char.properties.notify || char.properties.indicate) {
              try {
                await char.setNotifyValue(true);
                
                // Listen for notifications on CF02 (backup if CE02 fails)
                if (_notificationSubscription == null) { // Don't override CE02 subscription
                  _notificationSubscription = char.onValueReceived.listen(
                    (value) {
                      String message = String.fromCharCodes(value);
                      if (kDebugMode) {
                        print('Received notification from CF02: $message');
                      }
                      _notificationController.add(message);
                    },
                    onError: (error) {
                      if (kDebugMode) {
                        print('CF02 notification error: $error');
                      }
                    },
                  );
                }
                
                if (kDebugMode) {
                  print('Found CF02 (write + backup notify) in service $serviceUuid and enabled notifications: $charUuid');
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Could not enable notifications on CF02: $e');
                }
              }
            }
            
            if (kDebugMode) {
              print('Found CF02 (WiFi config - write capable) in service $serviceUuid: $charUuid');
            }
          }
          // Fallback characteristics
          else if (charUuid.contains('CF01') && _wifiListChar == null) {
            _wifiListChar = char;
            if (kDebugMode) {
              print('Found CF01 (fallback WiFi list) in service $serviceUuid: $charUuid');
            }
          }
        }
      }
      
      // Fallback: If only one characteristic found, use it for both read and write
      if (_wifiListChar == null && _wifiConfigChar != null) {
        if (kDebugMode) {
          print('Using CF02 for both read and write operations');
        }
        _wifiListChar = _wifiConfigChar;
      } else if (_wifiConfigChar == null && _wifiListChar != null) {
        if (kDebugMode) {
          print('Using CE01 for both read and write operations (fallback)');
        }
        _wifiConfigChar = _wifiListChar;
      }
      
      // Check if we found required characteristics
      bool success = _wifiConfigChar != null;
      
      if (success) {
        _isConnected = true;
        if (kDebugMode) {
          print('Successfully connected to ESP32');
          print('WiFi list char: ${_wifiListChar?.uuid ?? "Not found"}');
          print('WiFi config char: ${_wifiConfigChar?.uuid ?? "Not found"}');
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
  
  // Read WiFi list from CE01 (or CF02 if CE01 not available)
  Future<List<String>> readWiFiList() async {
    BluetoothCharacteristic? charToRead = _wifiListChar ?? _wifiConfigChar;
    
    if (charToRead == null) {
      if (kDebugMode) {
        print('No characteristic available for reading WiFi list');
      }
      return [];
    }
    
    try {
      if (kDebugMode) {
        print('Reading WiFi list from ${charToRead.uuid}...');
      }
      
      List<int> value = await charToRead.read();
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
  
  // Send WiFi credentials using CORRECT format: "_UWF:<ssid>0x06<password>0x04"
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
      
      // CORRECT format: "_UWF:<ssid>0x06<password>0x04"
      // Based on successful hex: 5F5557463A434849204B49454E06323931323230303504
      List<int> data = [];
      data.addAll('_UWF:'.codeUnits);  // Command prefix: 5F555746 3A
      data.addAll(ssid.codeUnits);     // WiFi SSID: 434849204B49454E (CHI KIEN)
      data.add(0x06);                  // Separator byte: 06
      data.addAll(password.codeUnits); // WiFi password: 323931323230303504 (29122005)
      data.add(0x04);                  // End command byte: 04
      
      if (kDebugMode) {
        print('Sending WiFi config data to ${_wifiConfigChar!.uuid}:');
        print('Format: "_UWF:<ssid>0x06<password>0x04"');
        print('Expected hex (reference): 5F5557463A434849204B49454E06323931323230303504');
        print('Actual hex: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
        print('Hex with spaces: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('String representation: ${String.fromCharCodes(data.where((b) => b >= 32 && b <= 126))}[special bytes: ${data.where((b) => b < 32 || b > 126).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]');
        print('Data length: ${data.length} bytes');
        
        // Verify hex matches the successful pattern
        String actualHex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
        String expectedHex = '5F5557463A434849204B49454E06323931323230303504';
        if (actualHex == expectedHex) {
          print('✅ Hex matches successful transmission pattern exactly!');
        } else {
          print('⚠️ Hex differs from successful pattern:');
          print('Expected: $expectedHex');
          print('Actual:   $actualHex');
        }
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
  
  // Remove the alternative methods since we have the correct format
  // Send END command using correct format: "_END.*0x04"
  
  // Send END command using correct format: "_END.*0x04"
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
      
      // Correct format: "_END.*" with 0x04 end byte
      List<int> data = '_END.*'.codeUnits;
      data.add(0x04); // End command byte
      
      if (kDebugMode) {
        print('Sending END command data to ${_wifiConfigChar!.uuid}:');
        print('Format: "_END.*0x04"');
        print('Hex: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('String representation: ${String.fromCharCodes(data.where((b) => b >= 32 && b <= 126))}[special bytes: ${data.where((b) => b < 32 || b > 126).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]');
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