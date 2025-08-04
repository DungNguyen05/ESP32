import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

class ESP32Handler {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _wifiListChar; // CE01 - Read WiFi list
  BluetoothCharacteristic? _wifiConfigChar; // CE02 - Write WiFi config & receive notifications
  
  StreamSubscription? _connectionSubscription;
  List<StreamSubscription> _notificationSubscriptions = []; // Multiple notification subscriptions
  final StreamController<String> _notificationController = 
      StreamController<String>.broadcast();
  
  bool _isConnected = false;
  
  // Verify notifications are ready
  Future<bool> areNotificationsReady() async {
    if (_notificationSubscriptions.isEmpty) {
      if (kDebugMode) {
        print('⚠ No notification subscriptions active');
      }
      return false;
    }
    
    if (kDebugMode) {
      print('✓ Notifications ready: ${_notificationSubscriptions.length} subscriptions active');
    }
    
    return true;
  }
  
  // Get count of active notification subscriptions
  int get activeNotificationCount => _notificationSubscriptions.length;
  Future<void> debugNotifications() async {
    if (_connectedDevice == null) return;
    
    if (kDebugMode) {
      print('=== DEBUG: Testing all notification characteristics ===');
    }
    
    try {
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            String charUuid = char.uuid.toString().toUpperCase();
            
            try {
              if (kDebugMode) {
                print('Testing notifications on $charUuid...');
              }
              
              await char.setNotifyValue(true);
              
              // Test subscription
              StreamSubscription testSub = char.onValueReceived.listen(
                (value) {
                  String message = String.fromCharCodes(value);
                  if (kDebugMode) {
                    print('🔔 TEST NOTIFICATION from $charUuid: "$message"');
                  }
                  _notificationController.add(message);
                },
              );
              
              _notificationSubscriptions.add(testSub);
              
              if (kDebugMode) {
                print('✓ Successfully enabled TEST notifications on $charUuid');
              }
              
            } catch (e) {
              if (kDebugMode) {
                print('✗ Failed to enable notifications on $charUuid: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('✗ Debug notifications error: $e');
      }
    }
  }
  
  // Stream for notifications from ESP32
  Stream<String> get notificationStream => _notificationController.stream;
  
  // Check if connected to device
  bool get isConnected => _isConnected;
  
  // Connect to ESP32 device
  Future<bool> connectToDevice(String deviceId) async {
    try {
      if (kDebugMode) {
        print('=== ESP32Handler: Connecting to device: $deviceId ===');
      }
      
      // Get device instance
      BluetoothDevice device = BluetoothDevice.fromId(deviceId);
      
      // Connect with timeout
      await device.connect(timeout: Duration(seconds: 15));
      _connectedDevice = device;
      
      if (kDebugMode) {
        print('✓ Connected to device successfully');
      }
      
      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        _isConnected = state == BluetoothConnectionState.connected;
        if (kDebugMode) {
          print('Connection state: $state');
        }
        
        if (!_isConnected) {
          _cleanup();
        }
      });
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      if (kDebugMode) {
        print('Discovered ${services.length} services:');
        for (var service in services) {
          print('  Service: ${service.uuid}');
          for (var char in service.characteristics) {
            print('    Char: ${char.uuid} - Props: R:${char.properties.read} W:${char.properties.write} N:${char.properties.notify}');
          }
        }
      }
      
      // Find the characteristics we need
      bool foundChars = await _findCharacteristics(services);
      
      if (foundChars) {
        _isConnected = true;
        if (kDebugMode) {
          print('✓ Successfully connected and found characteristics');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('✗ Could not find required characteristics');
        }
        await disconnect();
        return false;
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Connection error: $e');
      }
      await disconnect();
      return false;
    }
  }
  
  // Find required characteristics
  Future<bool> _findCharacteristics(List<BluetoothService> services) async {
    try {
      List<BluetoothCharacteristic> notifyChars = [];
      List<StreamSubscription> notificationSubscriptions = [];
      
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toUpperCase();
        
        if (kDebugMode) {
          print('=== Service: $serviceUuid ===');
        }
        
        for (BluetoothCharacteristic char in service.characteristics) {
          String charUuid = char.uuid.toString().toUpperCase();
          
          if (kDebugMode) {
            print('Characteristic: $charUuid');
            print('  Properties: R:${char.properties.read} W:${char.properties.write} WR:${char.properties.writeWithoutResponse} N:${char.properties.notify} I:${char.properties.indicate}');
          }
          
          // Look for CE01 (WiFi list reading)
          if (charUuid.contains('CE01') && char.properties.read) {
            _wifiListChar = char;
            if (kDebugMode) {
              print('✓ CE01 found - WiFi list characteristic');
            }
          }
          
          // Look for CE02 (WiFi config writing)
          if (charUuid.contains('CE02')) {
            _wifiConfigChar = char;
            if (kDebugMode) {
              print('✓ CE02 found - WiFi config characteristic');
            }
          }
          
          // Collect ALL characteristics that support notifications
          if (char.properties.notify || char.properties.indicate) {
            notifyChars.add(char);
            if (kDebugMode) {
              print('📡 Notification capable: $charUuid');
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('=== Setting up notifications ===');
        print('Found ${notifyChars.length} notification-capable characteristics');
      }
      
      // Enable notifications on ALL possible characteristics
      int successfulNotifications = 0;
      
      for (int i = 0; i < notifyChars.length; i++) {
        BluetoothCharacteristic char = notifyChars[i];
        String charUuid = char.uuid.toString().toUpperCase();
        
        try {
          if (kDebugMode) {
            print('Enabling notifications on $charUuid...');
          }
          
          await char.setNotifyValue(true);
          
          // Create separate subscription for each characteristic
          StreamSubscription subscription = char.onValueReceived.listen(
            (value) {
              String message = String.fromCharCodes(value);
              if (kDebugMode) {
                print('🔔 NOTIFICATION from $charUuid: "$message"');
                print('   Raw bytes: ${value.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                print('   Length: ${value.length} bytes');
              }
              
              // Forward to main notification stream
              _notificationController.add(message);
            },
            onError: (error) {
              if (kDebugMode) {
                print('✗ Notification error from $charUuid: $error');
              }
            },
          );
          
          notificationSubscriptions.add(subscription);
          successfulNotifications++;
          
          if (kDebugMode) {
            print('✓ Notifications enabled on $charUuid (${successfulNotifications}/${notifyChars.length})');
          }
          
        } catch (e) {
          if (kDebugMode) {
            print('⚠ Failed to enable notifications on $charUuid: $e');
          }
        }
      }
      
      // Store all subscriptions for cleanup
      _notificationSubscriptions = notificationSubscriptions;
      
      if (kDebugMode) {
        print('=== Summary ===');
        print('WiFi list char (CE01): ${_wifiListChar?.uuid ?? "Not found"}');
        print('WiFi config char (CE02): ${_wifiConfigChar?.uuid ?? "Not found"}');
        print('Notifications enabled: $successfulNotifications/${notifyChars.length}');
        
        if (successfulNotifications > 0) {
          print('✓ Ready to receive "Wifi_OK" notifications!');
        } else {
          print('⚠ No notifications enabled - may not receive "Wifi_OK"');
        }
      }
      
      // We need at least CE02 for WiFi configuration
      return _wifiConfigChar != null;
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Error finding characteristics: $e');
      }
      return false;
    }
  }
  
  // Read WiFi list from CE01 - Simplified
  Future<List<String>> readWiFiList() async {
    if (_wifiListChar == null) {
      if (kDebugMode) {
        print('⚠ No CE01 characteristic for WiFi list');
      }
      // Return mock data for testing if CE01 not available
      return ['TestWiFi_1', 'TestWiFi_2', 'MyRouter'];
    }
    
    try {
      if (kDebugMode) {
        print('Reading WiFi list from CE01...');
      }
      
      List<int> value = await _wifiListChar!.read();
      String data = String.fromCharCodes(value);
      
      if (kDebugMode) {
        print('WiFi list raw: "$data"');
        print('WiFi list bytes: ${value.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      }
      
      // Simple parsing - try different separators
      List<String> networks = [];
      
      if (value.contains(0x06)) {
        // Split by 0x06
        List<List<int>> parts = [];
        List<int> current = [];
        
        for (int byte in value) {
          if (byte == 0x06) {
            if (current.isNotEmpty) {
              parts.add(List.from(current));
              current.clear();
            }
          } else if (byte != 0x00) { // Skip null bytes
            current.add(byte);
          }
        }
        if (current.isNotEmpty) {
          parts.add(current);
        }
        
        networks = parts
            .map((bytes) => String.fromCharCodes(bytes).trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data.contains(',')) {
        networks = data.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      } else if (data.contains('\n')) {
        networks = data.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      } else if (data.trim().isNotEmpty) {
        networks = [data.trim()];
      }
      
      if (kDebugMode) {
        print('✓ Parsed ${networks.length} networks: $networks');
      }
      
      return networks;
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Error reading WiFi list: $e');
      }
      // Return mock data on error
      return ['ErrorNetwork_1', 'ErrorNetwork_2'];
    }
  }
  
  // Send WiFi credentials - Try multiple write methods
  Future<bool> sendWiFiCredentials(String ssid, String password) async {
    if (_wifiConfigChar == null) {
      if (kDebugMode) {
        print('✗ No CE02 characteristic for WiFi config');
      }
      return false;
    }
    
    try {
      if (kDebugMode) {
        print('=== Sending WiFi Credentials ===');
        print('SSID: "$ssid"');
        print('Password: "${password.replaceAll(RegExp(r'.'), '*')}"');
        print('Characteristic properties:');
        print('  Read: ${_wifiConfigChar!.properties.read}');
        print('  Write: ${_wifiConfigChar!.properties.write}');
        print('  WriteWithoutResponse: ${_wifiConfigChar!.properties.writeWithoutResponse}');
        print('  Notify: ${_wifiConfigChar!.properties.notify}');
        print('  Indicate: ${_wifiConfigChar!.properties.indicate}');
      }
      
      // Format exactly as in your nRF Connect log: "_UWF:<ssid>0x06<password>0x04"
      List<int> data = <int>[]; // Create mutable list
      
      // Add prefix
      data.addAll(utf8.encode('_UWF:'));
      
      // Add SSID
      data.addAll(utf8.encode(ssid));
      
      // Add separator 0x06
      data.add(0x06);
      
      // Add password
      data.addAll(utf8.encode(password));
      
      // Add end byte 0x04
      data.add(0x04);
      
      if (kDebugMode) {
        print('Data to send:');
        print('  String representation: "_UWF:$ssid\x06$password\x04"');
        print('  Hex bytes: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        print('  Length: ${data.length} bytes');
        print('  Writing to characteristic: ${_wifiConfigChar!.uuid}');
      }
      
      // Try different write methods
      bool success = false;
      
      // Method 1: Write without response (most common for ESP32)
      if (_wifiConfigChar!.properties.writeWithoutResponse && !success) {
        try {
          if (kDebugMode) {
            print('Trying Method 1: writeWithoutResponse = true');
          }
          await _wifiConfigChar!.write(data, withoutResponse: true);
          success = true;
          if (kDebugMode) {
            print('✓ Method 1 SUCCESS: Write without response');
          }
        } catch (e) {
          if (kDebugMode) {
            print('✗ Method 1 FAILED: $e');
          }
        }
      }
      
      // Method 2: Normal write with response
      if (_wifiConfigChar!.properties.write && !success) {
        try {
          if (kDebugMode) {
            print('Trying Method 2: withoutResponse = false');
          }
          await _wifiConfigChar!.write(data, withoutResponse: false);
          success = true;
          if (kDebugMode) {
            print('✓ Method 2 SUCCESS: Write with response');
          }
        } catch (e) {
          if (kDebugMode) {
            print('✗ Method 2 FAILED: $e');
          }
        }
      }
      
      // Method 3: Split data into smaller chunks (some devices have MTU limits)
      if (!success) {
        try {
          if (kDebugMode) {
            print('Trying Method 3: Split into chunks');
          }
          
          // Split into 20-byte chunks (common BLE MTU limit)
          int chunkSize = 20;
          for (int i = 0; i < data.length; i += chunkSize) {
            int end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
            List<int> chunk = data.sublist(i, end);
            
            if (kDebugMode) {
              print('  Sending chunk ${(i / chunkSize).floor() + 1}: ${chunk.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
            }
            
            if (_wifiConfigChar!.properties.writeWithoutResponse) {
              await _wifiConfigChar!.write(chunk, withoutResponse: true);
            } else if (_wifiConfigChar!.properties.write) {
              await _wifiConfigChar!.write(chunk, withoutResponse: false);
            }
            
            // Small delay between chunks
            await Future.delayed(Duration(milliseconds: 50));
          }
          
          success = true;
          if (kDebugMode) {
            print('✓ Method 3 SUCCESS: Chunked write');
          }
        } catch (e) {
          if (kDebugMode) {
            print('✗ Method 3 FAILED: $e');
          }
        }
      }
      
      // Method 4: Try to find another characteristic that supports write
      if (!success) {
        if (kDebugMode) {
          print('Trying Method 4: Find alternative write characteristic');
        }
        
        if (_connectedDevice != null) {
          List<BluetoothService> services = await _connectedDevice!.discoverServices();
          
          for (BluetoothService service in services) {
            for (BluetoothCharacteristic char in service.characteristics) {
              String charUuid = char.uuid.toString().toUpperCase();
              
              // Look for any characteristic with write capability
              if ((char.properties.write || char.properties.writeWithoutResponse) && 
                  char.uuid != _wifiConfigChar!.uuid) {
                
                if (kDebugMode) {
                  print('  Found alternative write char: $charUuid');
                  print('    Write: ${char.properties.write}');
                  print('    WriteWithoutResponse: ${char.properties.writeWithoutResponse}');
                }
                
                try {
                  if (char.properties.writeWithoutResponse) {
                    await char.write(data, withoutResponse: true);
                  } else {
                    await char.write(data, withoutResponse: false);
                  }
                  
                  success = true;
                  if (kDebugMode) {
                    print('✓ Method 4 SUCCESS: Alternative characteristic $charUuid');
                  }
                  
                  // Update our config char reference
                  _wifiConfigChar = char;
                  break;
                } catch (e) {
                  if (kDebugMode) {
                    print('✗ Alternative char $charUuid failed: $e');
                  }
                }
              }
            }
            if (success) break;
          }
        }
      }
      
      if (success) {
        if (kDebugMode) {
          print('✓ WiFi credentials sent successfully!');
          print('Now waiting for "Wifi_OK" notification...');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('✗ All write methods failed');
        }
        return false;
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Error sending WiFi credentials: $e');
      }
      return false;
    }
  }
  
  // Send END command - Fixed list issue
  Future<bool> sendEndCommand() async {
    if (_wifiConfigChar == null) {
      if (kDebugMode) {
        print('✗ No CE02 characteristic for END command');
      }
      return false;
    }
    
    try {
      if (kDebugMode) {
        print('=== Sending END Command ===');
      }
      
      // Create new mutable list for END command: "_END.*" + 0x04
      List<int> data = <int>[];
      data.addAll(utf8.encode('_END.*'));
      data.add(0x04);
      
      if (kDebugMode) {
        print('END command data:');
        print('  String: "_END.*\\x04"');
        print('  Hex: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        print('  Length: ${data.length} bytes');
      }
      
      // Try writeWithoutResponse first
      bool success = false;
      
      if (_wifiConfigChar!.properties.writeWithoutResponse && !success) {
        try {
          await _wifiConfigChar!.write(data, withoutResponse: true);
          success = true;
          if (kDebugMode) {
            print('✓ END command sent via writeWithoutResponse');
          }
        } catch (e) {
          if (kDebugMode) {
            print('✗ writeWithoutResponse failed: $e');
          }
        }
      }
      
      if (_wifiConfigChar!.properties.write && !success) {
        try {
          await _wifiConfigChar!.write(data, withoutResponse: false);
          success = true;
          if (kDebugMode) {
            print('✓ END command sent via write');
          }
        } catch (e) {
          if (kDebugMode) {
            print('✗ write failed: $e');
          }
        }
      }
      
      return success;
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Error sending END command: $e');
      }
      return false;
    }
  }
  
  // Disconnect from device
  Future<void> disconnect() async {
    try {
      if (kDebugMode) {
        print('=== Disconnecting from ESP32 ===');
      }
      
      await _cleanup();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        if (kDebugMode) {
          print('✓ Disconnected successfully');
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('✗ Error during disconnect: $e');
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
    
    // Cancel all notification subscriptions
    for (StreamSubscription subscription in _notificationSubscriptions) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();
    
    _connectionSubscription = null;
  }
  
  // Dispose resources
  void dispose() {
    _cleanup();
    _notificationController.close();
    disconnect();
  }
}