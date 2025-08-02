import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  // Mock version - không cần backend server
  static const String baseUrl = 'mock://localhost';
  
  // Lấy auth token từ SharedPreferences
  static Future<String?> getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Mock token cho testing
      String? token = prefs.getString('auth_token');
      if (token == null) {
        token = 'mock_token_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('auth_token', token);
      }
      return token;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting auth token: $e');
      }
      return 'mock_token_default';
    }
  }
  
  // Set auth token
  static Future<void> setAuthToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (e) {
      if (kDebugMode) {
        print('Error setting auth token: $e');
      }
    }
  }
  
  // Mock: Kiểm tra device registration - luôn return true
  static Future<bool> checkDeviceRegistration(String serialNumber) async {
    try {
      if (kDebugMode) {
        print('Mock: Checking device registration for $serialNumber');
      }
      
      // Simulate network delay
      await Future.delayed(Duration(milliseconds: 500));
      
      // Mock logic: Accept all devices with pattern ABC123, DEF456, etc.
      // Bạn có thể thêm logic mock phức tạp hơn nếu cần
      bool isValid = serialNumber.length >= 3 && 
                     RegExp(r'^[A-Z0-9]+$').hasMatch(serialNumber);
      
      if (kDebugMode) {
        print('Mock: Device $serialNumber validation result: $isValid');
      }
      
      return isValid;
    } catch (e) {
      if (kDebugMode) {
        print('Mock: Error checking device registration for $serialNumber: $e');
      }
      // Mock: Khi có lỗi, vẫn cho phép để testing
      return true;
    }
  }
  
  // Mock: Thêm device vào hệ thống - luôn return true
  static Future<bool> addDeviceToSystem({
    required String serialNumber,
    required String deviceId,
    required String name,
  }) async {
    try {
      if (kDebugMode) {
        print('Mock: Adding device to system:');
        print('  - Serial Number: $serialNumber');
        print('  - Device ID: $deviceId');
        print('  - Name: $name');
      }
      
      // Simulate network delay
      await Future.delayed(Duration(milliseconds: 800));
      
      // Mock: Lưu device info vào local storage
      final prefs = await SharedPreferences.getInstance();
      List<String> devices = prefs.getStringList('added_devices') ?? [];
      
      // Create device info
      Map<String, dynamic> deviceInfo = {
        'serialNumber': serialNumber,
        'deviceId': deviceId,
        'name': name,
        'addedAt': DateTime.now().toIso8601String(),
      };
      
      // Add to list if not exists
      String deviceJson = json.encode(deviceInfo);
      if (!devices.contains(deviceJson)) {
        devices.add(deviceJson);
        await prefs.setStringList('added_devices', devices);
      }
      
      if (kDebugMode) {
        print('Mock: Device $serialNumber added to local storage successfully');
        print('Mock: Total devices in storage: ${devices.length}');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Mock: Error adding device $serialNumber to system: $e');
      }
      return false;
    }
  }
  
  // Mock: Server connection check - luôn return true
  static Future<bool> checkServerConnection() async {
    try {
      if (kDebugMode) {
        print('Mock: Checking server connection...');
      }
      
      // Simulate network check delay
      await Future.delayed(Duration(milliseconds: 300));
      
      if (kDebugMode) {
        print('Mock: Server connection OK (simulated)');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Mock: Server connection check failed: $e');
      }
      return true; // Mock: luôn OK để testing
    }
  }
  
  // Mock: Lấy danh sách devices đã thêm
  static Future<List<Map<String, dynamic>>> getAddedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> devices = prefs.getStringList('added_devices') ?? [];
      
      return devices.map((deviceStr) {
        return json.decode(deviceStr) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Mock: Error getting added devices: $e');
      }
      return [];
    }
  }
  
  // Mock: Xóa device khỏi storage
  static Future<bool> removeDevice(String serialNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> devices = prefs.getStringList('added_devices') ?? [];
      
      devices.removeWhere((deviceStr) {
        Map<String, dynamic> device = json.decode(deviceStr);
        return device['serialNumber'] == serialNumber;
      });
      
      await prefs.setStringList('added_devices', devices);
      
      if (kDebugMode) {
        print('Mock: Device $serialNumber removed from storage');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Mock: Error removing device $serialNumber: $e');
      }
      return false;
    }
  }
}