import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'services/notification_service.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize notification service with error handling
  try {
    await NotificationService.initialize();
  } catch (e) {
    if (kDebugMode) {
      print('Error initializing notifications: $e');
    }
  }
  
  // Request permissions with error handling
  await _requestPermissions();
  
  runApp(ESP32App());
}

Future<void> _requestPermissions() async {
  try {
    // Only request permissions that are supported on current platform
    List<Permission> permissionsToRequest = [];
    
    // Add permissions based on platform
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      permissionsToRequest.addAll([
        Permission.bluetooth,
        Permission.location,
        Permission.notification,
      ]);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      permissionsToRequest.addAll([
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.notification,
      ]);
    }
    
    if (permissionsToRequest.isNotEmpty) {
      Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
      
      // Log permission status for debugging
      if (kDebugMode && statuses.isNotEmpty) {
        print('Permissions status:');
        statuses.forEach((permission, status) {
          print('${permission.toString()}: $status');
        });
      }
    }
    
    // Check notification permission separately with error handling
    try {
      bool notificationGranted = await NotificationService.requestPermissions();
      if (kDebugMode) {
        print('Notification permission: $notificationGranted');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting notification permission: $e');
      }
    }
    
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting permissions: $e');
    }
    // Don't crash the app if permissions fail
  }
}

class ESP32App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 WiFi Setup',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Primary theme colors
        primarySwatch: Colors.teal,
        primaryColor: Colors.teal,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        
        // App bar theme
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        
        // Card theme
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        
        // Elevated button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        
        // Input decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        
        // Text theme
        textTheme: TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
          ),
        ),
        
        // Snackbar theme
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentTextStyle: TextStyle(fontSize: 14),
        ),
        
        // Visual density
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      
      // Home screen
      home: SplashScreen(),
    );
  }
}

// Splash screen to show while initializing
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    try {
      // Show splash for at least 2 seconds
      await Future.delayed(Duration(seconds: 2));
      
      // Navigate to main screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen()),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during app initialization: $e');
      }
      
      // Show error screen if initialization fails
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ErrorScreen(error: e.toString())),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo/icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.router,
                size: 60,
                color: Colors.teal,
              ),
            ),
            
            SizedBox(height: 32),
            
            // App title
            Text(
              'ESP32 WiFi Setup',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            SizedBox(height: 8),
            
            // App subtitle
            Text(
              'Cấu hình WiFi cho thiết bị ESP32',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            
            SizedBox(height: 48),
            
            // Loading indicator
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            
            SizedBox(height: 16),
            
            Text(
              'Đang khởi tạo...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Error screen in case of initialization failure
class ErrorScreen extends StatelessWidget {
  final String error;
  
  const ErrorScreen({Key? key, required this.error}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.white,
              ),
              SizedBox(height: 24),
              Text(
                'Lỗi khởi tạo app',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              Text(
                error,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Restart app
                  main();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                ),
                child: Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}