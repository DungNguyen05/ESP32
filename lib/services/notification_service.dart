import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  static bool _initialized = false;
  
  // Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;
    
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings = 
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    try {
      bool? result = await _notifications.initialize(settings);
      _initialized = result ?? false;
      
      if (kDebugMode) {
        print('Notification service initialized: $_initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing notifications: $e');
      }
    }
  }
  
  // Show WiFi success notification
  static Future<void> showWiFiSuccessNotification() async {
    if (!_initialized) await initialize();
    
    const AndroidNotificationDetails androidDetails = 
        AndroidNotificationDetails(
      'esp32_wifi_channel',
      'ESP32 WiFi Setup',
      channelDescription: 'Notifications for ESP32 WiFi setup process',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    try {
      await _notifications.show(
        0,
        'ESP32 Kết nối thành công! 🎉',
        'Thiết bị đã kết nối WiFi thành công và sẵn sàng sử dụng.',
        details,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error showing success notification: $e');
      }
    }
  }
  
  // Show error notification
  static Future<void> showErrorNotification(String error) async {
    if (!_initialized) await initialize();
    
    const AndroidNotificationDetails androidDetails = 
        AndroidNotificationDetails(
      'esp32_error_channel',
      'ESP32 Errors',
      channelDescription: 'Error notifications from ESP32',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    try {
      await _notifications.show(
        1,
        'Lỗi kết nối ESP32 ❌',
        error,
        details,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error showing error notification: $e');
      }
    }
  }
  
  // Show timeout notification
  static Future<void> showTimeoutNotification() async {
    await showErrorNotification(
      'Thiết bị không thể kết nối WiFi sau 40 giây. Vui lòng kiểm tra lại thông tin WiFi.'
    );
  }
  
  // Request notification permissions (especially for Android 13+) - FIXED
  static Future<bool> requestPermissions() async {
    if (!_initialized) await initialize();
    
    try {
      // For web and other platforms that don't support this method
      if (kIsWeb) return true;
      
      // Try to request permissions
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        // For newer versions, use areNotificationsEnabled
        final bool? granted = await androidPlugin.areNotificationsEnabled();
        return granted ?? false;
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting notification permissions: $e');
      }
      return false;
    }
  }
}