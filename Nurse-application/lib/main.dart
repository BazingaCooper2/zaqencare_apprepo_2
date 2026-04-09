import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'providers/theme_provider.dart';
import 'pages/splash_page.dart';


/// ✅ Global Supabase client
late final SupabaseClient supabase;

/// ✅ Global notifications plugin
final FlutterLocalNotificationsPlugin localNotifs =
    FlutterLocalNotificationsPlugin();

/// ✅ Top-level FCM background message handler (required by Firebase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📩 Handling background message: ${message.messageId}');

  await localNotifs.show(
    message.hashCode,
    message.notification?.title ?? 'Background Message',
    message.notification?.body ?? 'You have a new message',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🏁 Starting Initialization...');

  // ✅ Initialize Firebase
  try {
    await Firebase.initializeApp();
    debugPrint('🔥 Firebase initialized');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('⚠️ Firebase init failed: $e');
  }

  // ✅ Initialize Supabase
  await Supabase.initialize(
    url: 'https://asbfhxdomvclwsrekdxi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzYmZoeGRvbXZjbHdzcmVrZHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMjI3OTUsImV4cCI6MjA2OTg5ODc5NX0.0VzbWIc-uxIDhI03g04n8HSPRQ_p01UTJQ1sg8ggigU',
  );
  debugPrint('⚡ Supabase initialized');
  supabase = Supabase.instance.client;

  // Restore session
  final session = Supabase.instance.client.auth.currentSession;
  print("APP START AUTH SESSION: ${session?.user.email}");

  // ✅ Initialize notifications
  try {
    await _initLocalNotifs();
    debugPrint('🔔 Notifications initialized');
  } catch (e) {
    debugPrint('⚠️ Local notifications init failed: $e');
  }

  runApp(const AppRoot());
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  @override
  void initState() {
    super.initState();
    _initMessaging();
  }

  Future<void> _initMessaging() async {
    try {
      await _requestPermissionAndGetToken();
      debugPrint('📱 FCM Token received');

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('🔥 Foreground message: ${message.data}');
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📲 Notification tapped: ${message.data}');
      });
    } catch (e) {
      debugPrint('⚠️ Messaging init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'ZaqenCare',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}

/// ✅ Local notifications setup
Future<void> _initLocalNotifs() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();

  await localNotifs.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (resp) async {
      debugPrint('🔔 Local Notification tapped: ${resp.payload}');
      // Handle navigation if needed, e.g. based on payload (offersId)
    },
  );

  // Request runtime permissions
  await localNotifs
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await localNotifs
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  // Create the notification channel (Android) to ensure sound/pop-up
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'shift_offers_channel', // id
    'Shift Offers', // title
    description: 'Notifications for new shift offers',
    importance: Importance.max, // Importance.max leads to heads-up notification
    playSound: true,
  );

  await localNotifs
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

/// ✅ Request notification permission & get FCM token
Future<void> _requestPermissionAndGetToken() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    final token = await messaging.getToken();
    debugPrint('✅ FCM Token: $token');
  } else {
    debugPrint('⚠️ User declined notifications');
  }
}

/// ✅ Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
