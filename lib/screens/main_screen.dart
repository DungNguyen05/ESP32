import 'package:flutter/material.dart';
import 'dart:async';
import '../models/device_model.dart';
import '../services/ble_service.dart';
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
  
  @override
  void initState() {
    super.initState();
    _setupDevicesListener();
  }
  
  @override
  void dispose() {
    _devicesSubscription?.cancel();
    BLEService.stopScan();
    BLEService.dispose();
    super.dispose();
  }
  
  void _setupDevicesListener() {
    _devicesSubscription = BLEService.devicesStream.listen(
      (devices) {
        if (mounted) {
          setState(() {
            _discoveredDevices = devices;
            if (devices.isNotEmpty) {
              _statusMessage = 'Tìm thấy ${devices.length} thiết bị ESP32';
            } else if (_isScanning) {
              _statusMessage = 'Đang tìm kiếm thiết bị...';
            } else {
              _statusMessage = 'Không tìm thấy thiết bị nào';
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
  
  void _startScanning() async {
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
      
      setState(() {
        _statusMessage = 'Đang tìm kiếm thiết bị ESP32...';
      });
      
      await BLEService.startScan(timeoutSeconds: 30);
      
      // Auto stop scanning after timeout
      Timer(Duration(seconds: 30), () {
        if (_isScanning && mounted) {
          _stopScanning();
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
  
  // FIXED - Remove await from void function
  void _stopScanning() async {
    if (!_isScanning) return;
    
    await BLEService.stopScan();
    
    if (mounted) {
      setState(() {
        _isScanning = false;
        _statusMessage = _discoveredDevices.isEmpty 
            ? 'Không tìm thấy thiết bị nào' 
            : 'Tìm thấy ${_discoveredDevices.length} thiết bị ESP32';
      });
    }
  }
  
  void _connectToDevice(ESP32Device device) async {
    // Stop scanning before connecting
    if (_isScanning) {
      _stopScanning();
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WiFiSetupScreen(device: device),
      ),
    ).then((_) {
      // Refresh the list when returning from setup screen
      if (mounted) {
        setState(() {
          _discoveredDevices = BLEService.getDiscoveredDevices();
        });
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
                SizedBox(height: 16),
                Text(
                  '2. Quét thiết bị:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• Nhấn nút "Quét thiết bị" để tìm ESP32'),
                Text('• Thiết bị sẽ hiển thị với tên "GC-<SN>"'),
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
                  'Lưu ý:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                Text('• Thiết bị sẽ timeout sau 3 phút nếu không cấu hình'),
                Text('• Đảm bảo Bluetooth và Location được bật'),
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
              onPressed: _stopScanning,
              backgroundColor: Colors.red,
              heroTag: "stop",
              child: Icon(Icons.stop),
              tooltip: 'Dừng quét',
            )
          else
            FloatingActionButton(
              onPressed: _startScanning,
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
                'Hãy đảm bảo ESP32 đang ở chế độ cấu hình WiFi\nvà nhấn nút quét để tìm thiết bị',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startScanning,
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
                      'Đã đăng ký',
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
            onTap: () => _connectToDevice(device),
          ),
        );
      },
    );
  }
}