import 'package:flutter/material.dart';
import 'dart:async';
import '../models/device_model.dart';
import '../services/esp32_handler.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';

enum SetupState {
  connecting,
  readingWiFiList,
  configuringWiFi,
  waitingForConnection,
  success,
  error,
}

class WiFiSetupScreen extends StatefulWidget {
  final ESP32Device device;
  
  const WiFiSetupScreen({Key? key, required this.device}) : super(key: key);
  
  @override
  _WiFiSetupScreenState createState() => _WiFiSetupScreenState();
}

class _WiFiSetupScreenState extends State<WiFiSetupScreen> {
  final ESP32Handler _esp32Handler = ESP32Handler();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  SetupState _currentState = SetupState.connecting;
  String _statusMessage = 'Đang kết nối với thiết bị...';
  List<String> _availableNetworks = [];
  StreamSubscription? _notificationSubscription;
  Timer? _timeoutTimer;
  bool _obscurePassword = true;
  bool _isCompletingSetup = false;
  
  @override
  void initState() {
    super.initState();
    _connectToDevice();
  }
  
  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _timeoutTimer?.cancel();
    _esp32Handler.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  void _connectToDevice() async {
    setState(() {
      _currentState = SetupState.connecting;
      _statusMessage = 'Đang kết nối với ${widget.device.name}...';
    });
    
    bool connected = await _esp32Handler.connectToDevice(widget.device.deviceId);
    
    if (connected) {
      _readWiFiList();
      _listenForNotifications();
    } else {
      setState(() {
        _currentState = SetupState.error;
        _statusMessage = 'Không thể kết nối với thiết bị. Vui lòng thử lại.';
      });
    }
  }
  
  void _readWiFiList() async {
    setState(() {
      _currentState = SetupState.readingWiFiList;
      _statusMessage = 'Đang đọc danh sách WiFi có sẵn...';
    });
    
    // Add delay for better UX
    await Future.delayed(Duration(seconds: 1));
    
    List<String> networks = await _esp32Handler.readWiFiList();
    
    setState(() {
      _availableNetworks = networks;
      _currentState = SetupState.configuringWiFi;
      _statusMessage = 'Vui lòng nhập thông tin WiFi để cấu hình cho thiết bị';
    });
  }
  
  void _listenForNotifications() {
    _notificationSubscription = _esp32Handler.notificationStream.listen(
      (message) {
        print('Received notification: $message');
        
        if (message.toLowerCase().contains('wifi_ok')) {
          _onWiFiConnected();
        }
      },
      onError: (error) {
        print('Notification error: $error');
        if (mounted) {
          setState(() {
            _currentState = SetupState.error;
            _statusMessage = 'Lỗi nhận thông báo từ thiết bị: $error';
          });
        }
      },
    );
  }
  
  void _sendWiFiCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _currentState = SetupState.waitingForConnection;
      _statusMessage = 'Đang gửi thông tin WiFi cho thiết bị...';
    });
    
    bool sent = await _esp32Handler.sendWiFiCredentials(
      _ssidController.text,
      _passwordController.text,
    );
    
    if (sent) {
      setState(() {
        _statusMessage = 'Thiết bị đang kết nối WiFi...\n(Có thể mất tới 40 giây)';
      });
      
      // Start timeout timer (40 seconds as per spec)
      _timeoutTimer = Timer(Duration(seconds: 40), () {
        if (_currentState == SetupState.waitingForConnection && mounted) {
          setState(() {
            _currentState = SetupState.error;
            _statusMessage = 'Timeout: Thiết bị không thể kết nối WiFi sau 40 giây.\nVui lòng kiểm tra lại thông tin WiFi.';
          });
          NotificationService.showTimeoutNotification();
        }
      });
    } else {
      setState(() {
        _currentState = SetupState.error;
        _statusMessage = 'Không thể gửi thông tin WiFi. Vui lòng thử lại.';
      });
    }
  }
  
  void _onWiFiConnected() async {
    _timeoutTimer?.cancel();
    
    setState(() {
      _currentState = SetupState.success;
      _statusMessage = 'Thiết bị đã kết nối WiFi thành công! 🎉\nVui lòng nhấn "Xác nhận hoàn thành" để thêm thiết bị vào hệ thống.';
    });
    
    // Show notification
    await NotificationService.showWiFiSuccessNotification();
    
    // NOTE: Không gửi END command ở đây, chờ user xác nhận
  }
  
  void _completeSetup() async {
    if (_isCompletingSetup) return; // Prevent double tap
    
    setState(() {
      _isCompletingSetup = true;
      _statusMessage = 'Đang hoàn tất cấu hình...';
    });
    
    try {
      // 1. Gửi END command trước
      bool endSent = await _esp32Handler.sendEndCommand();
      
      if (!endSent) {
        throw Exception('Không thể gửi lệnh kết thúc đến thiết bị');
      }
      
      // 2. Thêm device vào hệ thống qua API
      bool deviceAdded = await ApiService.addDeviceToSystem(
        serialNumber: widget.device.serialNumber,
        deviceId: widget.device.deviceId,
        name: widget.device.name,
      );
      
      if (!deviceAdded) {
        throw Exception('Không thể thêm thiết bị vào hệ thống');
      }
      
      // 3. Disconnect từ thiết bị
      await _esp32Handler.disconnect();
      
      // 4. Thành công - quay về màn hình chính
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thêm thiết bị ${widget.device.name} thành công!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _isCompletingSetup = false;
        _statusMessage = 'Thiết bị đã kết nối WiFi thành công! 🎉\nVui lòng nhấn "Xác nhận hoàn thành" để thêm thiết bị vào hệ thống.';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi hoàn tất cấu hình: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  void _retryConnection() {
    _timeoutTimer?.cancel();
    _connectToDevice();
  }
  
  void _selectNetworkFromList(String network) {
    setState(() {
      _ssidController.text = network;
    });
  }
  
  Widget _buildStateContent() {
    switch (_currentState) {
      case SetupState.connecting:
      case SetupState.readingWiFiList:
      case SetupState.waitingForConnection:
        return _buildLoadingState();
        
      case SetupState.configuringWiFi:
        return _buildWiFiConfigForm();
        
      case SetupState.success:
        return _buildSuccessState();
        
      case SetupState.error:
        return _buildErrorState();
    }
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
              ),
            ),
            SizedBox(height: 32),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
            if (_currentState == SetupState.waitingForConnection) ...[
              SizedBox(height: 16),
              LinearProgressIndicator(
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
              ),
              SizedBox(height: 8),
              Text(
                'Vui lòng chờ...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildWiFiConfigForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              'Cấu hình WiFi',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Thiết bị: ${widget.device.name}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            
            // Available networks section
            if (_availableNetworks.isNotEmpty) ...[
              Text(
                'Mạng WiFi có sẵn:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
              SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  itemCount: _availableNetworks.length,
                  itemBuilder: (context, index) {
                    String network = _availableNetworks[index];
                    bool isSelected = _ssidController.text == network;
                    
                    return ListTile(
                      leading: Icon(
                        Icons.wifi,
                        color: isSelected ? Colors.teal : Colors.grey,
                      ),
                      title: Text(
                        network,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.teal : Colors.black,
                        ),
                      ),
                      trailing: isSelected ? Icon(Icons.check, color: Colors.teal) : null,
                      onTap: () => _selectNetworkFromList(network),
                    );
                  },
                ),
              ),
              SizedBox(height: 24),
            ],
            
            // WiFi SSID input
            TextFormField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'Tên WiFi (SSID)',
                hintText: 'Nhập tên mạng WiFi',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập tên WiFi';
                }
                return null;
              },
            ),
            SizedBox(height: 20),
            
            // WiFi Password input
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Mật khẩu WiFi',
                hintText: 'Nhập mật khẩu WiFi',
                prefixIcon: Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                ),
              ),
              obscureText: _obscurePassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập mật khẩu WiFi';
                }
                if (value.length < 8) {
                  return 'Mật khẩu phải có ít nhất 8 ký tự';
                }
                return null;
              },
            ),
            SizedBox(height: 32),
            
            // Submit button
            ElevatedButton(
              onPressed: _sendWiFiCredentials,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send),
                  SizedBox(width: 8),
                  Text(
                    'Cấu hình WiFi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Info card
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Thiết bị sẽ thử kết nối WiFi trong 40 giây. Bạn sẽ nhận được thông báo khi hoàn tất.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 60,
                color: Colors.green,
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Thành công!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 32),
            
            // Warning box
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_outlined, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chỉ khi bạn nhấn "Xác nhận hoàn thành", thiết bị mới được thêm chính thức vào hệ thống.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            ElevatedButton(
              onPressed: _isCompletingSetup ? null : _completeSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCompletingSetup
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Đang xử lý...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle),
                        SizedBox(width: 8),
                        Text(
                          'Xác nhận hoàn thành',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 60,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Có lỗi xảy ra',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back),
                      SizedBox(width: 8),
                      Text('Quay lại'),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _retryConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh),
                      SizedBox(width: 8),
                      Text('Thử lại'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Disconnect from device when going back
        await _esp32Handler.disconnect();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Cấu hình WiFi'),
          backgroundColor: Colors.teal,
          elevation: 0,
          centerTitle: true,
        ),
        body: _buildStateContent(),
      ),
    );
  }
}