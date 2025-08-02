import 'package:flutter/material.dart';
import 'dart:async';
import '../models/device_model.dart';
import '../services/ble_service.dart';
import '../services/api_service.dart';
import 'wifi_setup_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<ESP32Device> _discoveredDevices = [];
  bool _isScanning = false;
  StreamSubscription? _devicesSubscription;
  String _statusMessage = 'Nhấn nút quét để tìm thiết bị ESP32';
  bool _serverConnected = false;
  
  @override
  void initState() {
    super.initState();
    _checkServerConnection();
    _setupDevicesListener();
  }
  
  @override
  void dispose() {
    _devicesSubscription?.cancel();
    BLEService.stopScan();
    BLEService.dispose();
    super.dispose();
  }
  
  Future<void> _checkServerConnection() async {
    bool connected = await ApiService.checkServerConnection();
    setState(() {
      _serverConnected = connected;
    });
    
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể kết nối đến server. Một số tính năng có thể bị hạn chế.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
  
  void _setupDevicesListener() {
    _devicesSubscription = BLEService.devicesStream.listen(
      (devices) {
        if (mounted) {
          setState(() {
            _discoveredDevices = devices;
            if (devices.isNotEmpty) {
              _statusMessage = 'Tìm thấy ${devices.length} thiết bị ESP32 đã đăng ký';
            } else if (_isScanning) {
              _statusMessage = 'Đang tìm kiếm thiết bị...';
            } else {
              _statusMessage = 'Không tìm thấy thiết bị ESP32 nào đã đăng ký';
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _statusMessage = 'Lỗi: $error';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi scan BLE: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
  
  Future<void> _startScanning() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _statusMessage = 'Đang kiểm tra Bluetooth...';
    });
    
    try {
      // Check Bluetooth availability
      if (!await BLEService.isBluetoothAvailable()) {
        // Try to turn on Bluetooth
        await BLEService.turnOnBluetooth();
        
        // Wait a bit and check again
        await Future.delayed(Duration(seconds: 2));
        
        if (!await BLEService.isBluetoothAvailable()) {
          throw Exception('Bluetooth không khả dụng. Vui lòng bật Bluetooth trong cài đặt.');
        }
      }
      
      // Check server connection before scanning
      if (!_serverConnected) {
        await _checkServerConnection();
        if (!_serverConnected) {
          throw Exception('Không thể kết nối đến server để xác thực thiết bị.');
        }
      }
      
      setState(() {
        _statusMessage = 'Đang tìm kiếm thiết bị ESP32...';
      });
      
      await BLEService.startScan(timeoutSeconds: 30);
      
      // Auto stop scanning after timeout
      Timer(Duration(seconds: 30), () async {
        if (_isScanning && mounted) {
          await _stopScanning();
        }
      });
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'Lỗi: $e';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  Future<void> _stopScanning() async {
    if (!_isScanning) return;
    
    await BLEService.stopScan();
    
    if (mounted) {
      setState(() {
        _isScanning = false;
        _statusMessage = _discoveredDevices.isEmpty 
            ? 'Không tìm thấy thiết bị ESP32 nào đã đăng ký' 
            : 'Tìm thấy ${_discoveredDevices.length} thiết bị ESP32 đã đăng ký';
      });
    }
  }
  
  Future<void> _connectToDevice(ESP32Device device) async {
    // Stop scanning before connecting
    if (_isScanning) {
      await _stopScanning();
    }
    
    // Double check device registration before proceeding
    bool isValid = await device.validateRegistration();
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thiết bị không hợp lệ hoặc không thuộc về tài khoản này.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WiFiSetupScreen(device: device),
      ),
    ).then((result) {
      // Refresh the list when returning from setup screen
      if (mounted) {
        setState(() {
          _discoveredDevices = BLEService.getDiscoveredDevices();
        });
        
        // If setup was successful, show additional message
        if (result == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Thiết bị đã được thêm thành công vào hệ thống!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }
  
  void _showInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Hướng dẫn sử dụng'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '1. Chuẩn bị thiết bị ESP32:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• Đảm bảo thiết bị đã được cấp nguồn'),
                Text('• Nhấn giữ nút bất kỳ trong 5 giây để vào chế độ cấu hình WiFi'),
                Text('• Thiết bị sẽ timeout sau 3 phút nếu không cấu hình'),
                SizedBox(height: 16),
                Text(
                  '2. Quét thiết bị:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• Nhấn nút "Quét thiết bị" để tìm ESP32'),
                Text('• Thiết bị sẽ hiển thị với tên "GC-<SN>"'),
                Text('• Chỉ thiết bị đã đăng ký mới được hiển thị'),
                SizedBox(height: 16),
                Text(
                  '3. Cấu hình WiFi:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• Chọn thiết bị từ danh sách'),
                Text('• Nhập thông tin WiFi'),
                Text('• Chờ thiết bị kết nối (tối đa 40 giây)'),
                SizedBox(height: 16),
                Text(
                  '4. Hoàn tất cấu hình:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• Sau khi thiết bị kết nối WiFi thành công'),
                Text('• Nhấn "Xác nhận hoàn thành" để thêm vào hệ thống'),
                Text('• Thiết bị sẽ chính thức được ghi nhận'),
                SizedBox(height: 16),
                Text(
                  'Lưu ý quan trọng:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                Text('• Đảm bảo Bluetooth và Location được bật'),
                Text('• Cần kết nối internet để xác thực thiết bị'),
                Text('• Chỉ thiết bị thuộc tài khoản của bạn mới hiển thị'),
                Text('• Phải nhấn "Xác nhận hoàn thành" để hoàn tất'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Đã hiểu'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ESP32 WiFi Setup'),
        backgroundColor: Colors.teal,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showInstructions,
            tooltip: 'Hướng dẫn',
          ),
          // Server status indicator
          Container(
            margin: EdgeInsets.only(right: 16),
            child: Center(
              child: Icon(
                _serverConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _serverConnected ? Colors.white : Colors.red.shade300,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                if (_isScanning) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                    ),
                  ),
                  SizedBox(width: 12),
                ] else ...[
                  Icon(
                    _discoveredDevices.isEmpty ? Icons.info_outline : Icons.check_circle_outline,
                    color: _discoveredDevices.isEmpty ? Colors.orange : Colors.green,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.teal.shade700,
                    ),
                  ),
                ),
                if (!_serverConnected) ...[
                  Icon(
                    Icons.warning,
                    color: Colors.orange,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
          
          // Device list
          Expanded(
            child: _discoveredDevices.isEmpty
                ? _buildEmptyState()
                : _buildDeviceList(),
          ),
        ],
      ),
      
      // Floating action buttons
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isScanning)
            FloatingActionButton(
              onPressed: () async => await _stopScanning(),
              backgroundColor: Colors.red,
              heroTag: "stop",
              child: Icon(Icons.stop),
              tooltip: 'Dừng quét',
            )
          else
            FloatingActionButton(
              onPressed: () async => await _startScanning(),
              backgroundColor: Colors.teal,
              heroTag: "scan",
              child: Icon(Icons.bluetooth_searching),
              tooltip: 'Quét thiết bị',
            ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              size: 80,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 24),
            Text(
              _isScanning
                  ? 'Đang tìm kiếm thiết bị ESP32...'
                  : 'Chưa tìm thấy thiết bị ESP32 nào',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            if (!_isScanning) ...[
              Text(
                'Hãy đảm bảo ESP32 đang ở chế độ cấu hình WiFi\nvà thiết bị đã được đăng ký trong hệ thống',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async => await _startScanning(),
                icon: Icon(Icons.refresh),
                label: Text('Quét lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildDeviceList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        ESP32Device device = _discoveredDevices[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.teal.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.router,
                color: Colors.teal,
                size: 24,
              ),
            ),
            title: Text(
              device.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text(
                  'Serial Number: ${device.serialNumber}',
                  style: TextStyle(fontSize: 14),
                ),
                Text(
                  'Device ID: ${device.deviceId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (device.rssi != null) ...[
                  SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '${device.rssi} dBm',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (device.isRegistered)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Đã xác thực',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
            onTap: () async => await _connectToDevice(device),
          ),
        );
      },
    );
  }
}