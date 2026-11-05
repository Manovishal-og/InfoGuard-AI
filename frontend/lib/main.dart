import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'models/verification_response.dart';
import 'services/backend_api_service.dart';
import 'screens/result_screen.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// ============================================================
// GLOBAL NAVIGATOR KEY
// ============================================================

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();


// ============================================================
// LOCAL NOTIFICATION SERVICE
// ============================================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'truthguard_verification';
  static const String channelName = 'TruthGuard Verification';
  static const String channelDescription =
      'Notifications when TruthGuard finishes verifying content.';

  // ----------------------------------------------------------
  // INITIALIZE
  // ----------------------------------------------------------

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings =
        InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await plugin.initialize(
  settings: settings,
  onDidReceiveNotificationResponse:
      _onNotificationTapped,
);

    // Android notification channel
    const AndroidNotificationChannel channel =
        AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      playSound: true,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Android 13+ notification permission
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }


  // ----------------------------------------------------------
  // SHOW VERIFICATION NOTIFICATION
  // ----------------------------------------------------------

  static Future<void> showVerificationNotification({
    required VerificationResponse result,
    required String verifiedUrl,
  }) async {

    final String verdict =
        result.verdict.toUpperCase();

    final String title =
        'InfoGuard AI • Verification Complete';

    final String body =
    '$verdict • ${result.category}';

    // Store complete result inside notification payload.
    final String payload = jsonEncode({
  'verdict': result.verdict,
  'category': result.category,
  'explanationEn': result.explanationEn,
  'explanationTa': result.explanationTa,
  'proofLink': result.proofLink,
  'verifiedUrl': verifiedUrl,
});

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,

      // WhatsApp-style important notification
      importance: Importance.max,
      priority: Priority.high,

      playSound: true,

      // Keep notification visible until user opens it
      autoCancel: true,

      styleInformation:
          BigTextStyleInformation(
        '',
      ),

      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(
      android: androidDetails,
    );

    await plugin.show(
  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  title: title,
  body: body,
  notificationDetails: notificationDetails,
  payload: payload,
);
  }


  // ----------------------------------------------------------
  // WHEN USER TAPS NOTIFICATION
  // ----------------------------------------------------------

  static void _onNotificationTapped(
      NotificationResponse response) {

    final String? payload = response.payload;

    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final Map<String, dynamic> data =
          jsonDecode(payload);

      final VerificationResponse result =
    VerificationResponse(
  verdict:
      data['verdict']?.toString() ?? 'UNKNOWN',

  confidenceScore:
      (data['confidenceScore'] as num?)
              ?.toDouble() ??
          0.0,

  category:
      data['category']?.toString() ??
          'Unknown',

  explanationEn:
      data['explanationEn']?.toString() ??
          '',

  explanationTa:
      data['explanationTa']?.toString() ??
          '',

  proofLink:
      data['proofLink']?.toString() ?? '',
);
      final String verifiedUrl =
          data['verifiedUrl']?.toString() ?? '';

      _openResultScreen(
        result: result,
        verifiedUrl: verifiedUrl,
      );

    } catch (e) {
      debugPrint(
        'Notification payload error: $e',
      );
    }
  }


  // ----------------------------------------------------------
  // OPEN RESULT SCREEN
  // ----------------------------------------------------------

  static void _openResultScreen({
    required VerificationResponse result,
    required String verifiedUrl,
  }) {

    final navigator =
        navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (context) =>
            ResultScreen(
          result: result,
          verifiedUrl: verifiedUrl,
        ),
      ),
    );
  }
}
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(
    VerificationTaskHandler(),
  );
}

class VerificationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(
    DateTime timestamp,
    TaskStarter starter,
  ) async {
    debugPrint(
      'InfoGuard AI background verification service started',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Verification is handled when the URL is received.
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    bool isTimeout,
  ) async {
    debugPrint(
      'InfoGuard AI background verification service stopped',
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    final String url = data['url']?.toString().trim() ?? '';

    if (url.isEmpty) {
      return;
    }

    _verifyInBackground(url);
  }

  Future<void> _verifyInBackground(String url) async {
    try {
      debugPrint(
        'Background verification started for: $url',
      );

      final BackendApiService apiService =
          BackendApiService();

      final VerificationResponse result =
          await apiService.verifyUrl(
        url: url,
        caption: '',
      );

      debugPrint(
        'Background verification completed.',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'verification_complete',
        'verifiedUrl': url,
        'result': {
          'verdict': result.verdict,
          'confidenceScore': result.confidenceScore,
          'category': result.category,
          'explanationEn': result.explanationEn,
          'explanationTa': result.explanationTa,
          'proofLink': result.proofLink,
        },
      });
    } catch (e) {
      debugPrint(
        'Background verification failed: $e',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'verification_error',
        'verifiedUrl': url,
        'error': e.toString(),
      });
    } finally {
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

// ============================================================
// MAIN
// ============================================================
void _onBackgroundTaskData(Object data) async {
  if (data is! Map) {
    return;
  }

  final String type =
      data['type']?.toString() ?? '';

  if (type == 'verification_error') {
    debugPrint(
      'Background verification error: ${data['error']}',
    );

    return;
  }

  if (type != 'verification_complete') {
    return;
  }

  try {
    final Map<String, dynamic> resultData =
        Map<String, dynamic>.from(
      data['result'] as Map,
    );

    final VerificationResponse result =
        VerificationResponse.fromJson(resultData);

    final String verifiedUrl =
        data['verifiedUrl']?.toString() ?? '';

    // Show normal Android notification.
    await NotificationService.showVerificationNotification(
      result: result,
      verifiedUrl: verifiedUrl,
    );

    // If InfoGuard is currently visible, open result automatically.
    final bool appIsForeground =
        await FlutterForegroundTask.isAppOnForeground;

    if (appIsForeground) {
      final navigator =
          navigatorKey.currentState;

      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              result: result,
              verifiedUrl: verifiedUrl,
            ),
          ),
        );
      }
    }
  } catch (e) {
    debugPrint(
      'Background result processing error: $e',
    );
  }
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize normal notification system.
  await NotificationService.initialize();

  // Initialize communication between UI and foreground service.
  FlutterForegroundTask.initCommunicationPort();

  // Receive completed verification results from background service.
  FlutterForegroundTask.addTaskDataCallback(
    _onBackgroundTaskData,
  );

  // Initialize foreground service.
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'infoguard_background',
      channelName: 'InfoGuard AI Verification',
      channelDescription:
          'Keeps InfoGuard AI verification running in the background.',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      playSound: true,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(
    const TruthGuardApp(),
  );
}

// ============================================================
// APP COLORS
// ============================================================

class AppColors {

  static const primary =
      Color(0xFF3867FF);

  static const primaryDark =
      Color(0xFF2852D9);

  static const deepNavy =
      Color(0xFF14213D);

  static const purple =
      Color(0xFF7657F6);

  static const softBlue =
      Color(0xFFEAF0FF);

  static const softPurple =
      Color(0xFFF1EDFF);

  static const background =
      Color(0xFFF7F9FC);

  static const white =
      Colors.white;

  static const secondary =
      Color(0xFF687386);

  static const border =
      Color(0xFFE5EAF2);

  static const success =
      Color(0xFF20A66A);

  static const warning =
      Color(0xFFF59E0B);

  static const danger =
      Color(0xFFE5484D);
}


// ============================================================
// MAIN APP
// ============================================================

class TruthGuardApp extends StatelessWidget {

  const TruthGuardApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      navigatorKey: navigatorKey,

      debugShowCheckedModeBanner: false,

      title: 'InfoGuard AI',

      theme: ThemeData(
        useMaterial3: true,

        scaffoldBackgroundColor:
            AppColors.background,

        colorScheme:
            ColorScheme.fromSeed(
          seedColor:
              AppColors.primary,
        ),
      ),

      home:
          const HomeScreen(),
    );
  }
}


// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatefulWidget {

  const HomeScreen({
    super.key,
  });

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}


// ============================================================
// HOME STATE
// ============================================================

class _HomeScreenState
    extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    initializeSharing();
  }

  // URL controller
  final TextEditingController
      urlController =
      TextEditingController();

  // Backend API
  final BackendApiService
      apiService =
      BackendApiService();

  // Loading
  bool isLoading = false;
  StreamSubscription<List<SharedMediaFile>>? _sharingSubscription;


  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
void dispose() {

  _sharingSubscription?.cancel();

  urlController.dispose();

  super.dispose();
}
void initializeSharing() {

  _sharingSubscription =
      ReceiveSharingIntent.instance.getMediaStream().listen(
    (List<SharedMediaFile> files) {
      _handleSharedMedia(files);
    },
    onError: (error) {
      debugPrint('Sharing error: $error');
    },
  );

  ReceiveSharingIntent.instance.getInitialMedia().then(
    (List<SharedMediaFile> files) {

      _handleSharedMedia(files);

      if (files.isNotEmpty) {
        ReceiveSharingIntent.instance.reset();
      }
    },
    onError: (error) {
      debugPrint('Initial sharing error: $error');
    },
  );
}


void _handleSharedMedia(
    List<SharedMediaFile> files) {

  if (!mounted || files.isEmpty) {
    return;
  }

  final String sharedText =
      files.first.path.trim();

  if (sharedText.isEmpty) {
    return;
  }

  final Uri? uri =
      Uri.tryParse(sharedText);

  if (uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https') &&
      uri.host.isNotEmpty) {

    setState(() {
      urlController.text = sharedText;
    });

    return;
  }

  final RegExp urlPattern = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  final Match? match =
      urlPattern.firstMatch(sharedText);

  if (match != null) {

    setState(() {
      urlController.text =
          match.group(0)!.trim();
    });
  }
}

  // ==========================================================
  // URL VALIDATION
  // ==========================================================

  bool isValidUrl(String value) {

    final uri =
        Uri.tryParse(value);

    if (uri == null) {
      return false;
    }

    return
        (uri.scheme == 'http' ||
            uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }


  Future<void> verifyContent() async {
  final String url = urlController.text.trim();

  // --------------------------------------------------------
  // EMPTY URL
  // --------------------------------------------------------

  if (url.isEmpty) {
    showMessage(
      'Please paste a URL first.',
    );
    return;
  }

  // --------------------------------------------------------
  // INVALID URL
  // --------------------------------------------------------

  if (!isValidUrl(url)) {
    showMessage(
      'Please enter a valid URL.',
    );
    return;
  }

  // --------------------------------------------------------
  // CLOSE KEYBOARD
  // --------------------------------------------------------

  FocusScope.of(context).unfocus();

  // --------------------------------------------------------
  // START LOADING
  // --------------------------------------------------------

  setState(() {
    isLoading = true;
  });

  try {
    // ------------------------------------------------------
    // START ANDROID FOREGROUND SERVICE
    // ------------------------------------------------------

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    final serviceResult =
        await FlutterForegroundTask.startService(
      serviceId: 1001,

      // Android foreground service type.
      serviceTypes: [
        ForegroundServiceTypes.dataSync,
      ],

      // Notification shown while verification is running.
      notificationTitle:
          'InfoGuard AI • Verification Running',

      notificationText:
          'Checking the content in the background...',

      // Use the application launcher icon.
      notificationIcon: null,

      // If notification is tapped, open the app.
      notificationInitialRoute: '/',

      // Start our background TaskHandler.
      callback: startCallback,
    );

    debugPrint(
      'Foreground service result: $serviceResult',
    );

    // ------------------------------------------------------
    // SEND URL TO BACKGROUND SERVICE
    // ------------------------------------------------------

    FlutterForegroundTask.sendDataToTask({
      'url': url,
    });

    // ------------------------------------------------------
    // VERIFICATION IS NOW RUNNING IN BACKGROUND
    //
    // We DO NOT wait for the backend here.
    //
    // The foreground service will wait for the backend,
    // even after the user returns to Instagram.
    // ------------------------------------------------------

    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = false;
    });

    showMessage(
      'Verification started. You can continue using Instagram. You will receive a notification when it is complete.',
    );
  } catch (e) {
    // ------------------------------------------------------
    // BACKGROUND SERVICE START ERROR
    // ------------------------------------------------------

    debugPrint(
      'Failed to start background verification: $e',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = false;
    });

    showMessage(
      'Unable to start background verification.',
    );
  }
}

  // ==========================================================
  // SHOW MESSAGE
  // ==========================================================

  void showMessage(
      String message) {

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(message),

          behavior:
              SnackBarBehavior.floating,

          margin:
              const EdgeInsets.all(16),

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(14),
          ),
        ),
      );
  }


  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
      BuildContext context) {

    return Scaffold(

      body: SafeArea(

        child:
            SingleChildScrollView(

          padding:
              const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            32,
          ),

          child: Column(

            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              buildHeader(),

              const SizedBox(
                height: 24,
              ),

              buildHero(),

              const SizedBox(
                height: 24,
              ),

              buildVerificationCard(),

              const SizedBox(
                height: 20,
              ),

              buildVerifyButton(),

              const SizedBox(
                height: 26,
              ),

              buildTrustMessage(),

              const SizedBox(
                height: 28,
              ),

              buildRecentSection(),
            ],
          ),
        ),
      ),
    );
  }


  // ==========================================================
  // HEADER
  // ==========================================================

  Widget buildHeader() {
  return Row(
    children: [
      // ------------------------------------------------------
      // INFOGUARD AI LOGO
      // ------------------------------------------------------

      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.purple,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: const Icon(
          Icons.shield_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),

      const SizedBox(width: 13),

      // ------------------------------------------------------
      // APP TITLE
      // ------------------------------------------------------

      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'InfoGuard AI',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.deepNavy,
              ),
            ),

            SizedBox(height: 3),

            Text(
              'AI-powered content verification',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),

      // ------------------------------------------------------
      // NOTIFICATION BUTTON
      // ------------------------------------------------------

      Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.notifications_none_rounded,
          color: AppColors.deepNavy,
          size: 22,
        ),
      ),
    ],
  );
}

  // ==========================================================
  // HERO
  // ==========================================================

  Widget buildHero() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      23,
      23,
      23,
      24,
    ),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          AppColors.softBlue,
          AppColors.softPurple,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
        color: Colors.white,
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(
            alpha: 0.07,
          ),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Stack(
      children: [
        // ----------------------------------------------------
        // SOFT DECORATIVE CIRCLE
        // ----------------------------------------------------

        Positioned(
          right: -35,
          top: -45,
          child: Container(
            width: 125,
            height: 125,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(
                alpha: 0.32,
              ),
            ),
          ),
        ),

        Positioned(
          right: 20,
          bottom: -60,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purple.withValues(
                alpha: 0.06,
              ),
            ),
          ),
        ),

        // ----------------------------------------------------
        // HERO CONTENT
        // ----------------------------------------------------

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // BADGE
            // ------------------------------------------------

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.82,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: 0.9,
                  ),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.purple,
                    size: 15,
                  ),

                  SizedBox(width: 7),

                  Text(
                    'SMART CONTENT VERIFICATION',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ------------------------------------------------
            // MAIN TITLE
            // ------------------------------------------------

            const Text(
              'Know what\'s real.',
              style: TextStyle(
                color: AppColors.deepNavy,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 2),

            const Text(
              'Before you share.',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 13),

            // ------------------------------------------------
            // DESCRIPTION
            // ------------------------------------------------

            const Text(
              'Analyze online content with AI-powered '
              'evidence verification before you believe '
              'or share it.',
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 19),

            // ------------------------------------------------
            // TRUST INDICATORS
            // ------------------------------------------------

            Row(
              children: [
                _buildHeroFeature(
                  Icons.auto_awesome_rounded,
                  'AI Analysis',
                ),

                const SizedBox(width: 8),

                _buildHeroFeature(
                  Icons.fact_check_rounded,
                  'Evidence',
                ),

                const SizedBox(width: 8),

                _buildHeroFeature(
                  Icons.verified_rounded,
                  'Reliable',
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}
Widget _buildHeroFeature(
  IconData icon,
  String label,
) {
  return Flexible(
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 14,
          ),

          const SizedBox(width: 5),

          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.deepNavy,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ==========================================================
  // VERIFICATION CARD
  // ==========================================================

  Widget buildVerificationCard() {

    return buildCard(

      child:
          Column(

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          const Row(

            children: [

              Icon(
                Icons.link_rounded,
                color:
                    AppColors.primary,
                size: 22,
              ),

              SizedBox(
                width: 8,
              ),

              Text(
                'Enter content URL',

                style:
                    TextStyle(
                  color:
                      AppColors.deepNavy,
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 7,
          ),

          const Text(
            'Paste a link from Instagram, YouTube, Facebook, X or any supported web page.',

            style:
                TextStyle(
              color:
                  AppColors.secondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          TextField(

            controller:
                urlController,

            keyboardType:
                TextInputType.url,

            autocorrect:
                false,

            textInputAction:
                TextInputAction.done,

            decoration:
                inputDecoration(
              hint:
                  'https://www.instagram.com/...',
              icon:
                  Icons.link_rounded,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Container(

            width:
                double.infinity,

            padding:
                const EdgeInsets.all(12),

            decoration:
                BoxDecoration(

              color:
                  AppColors.softBlue,

              borderRadius:
                  BorderRadius.circular(12),
            ),

            child:
                const Row(

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Icon(
                  Icons.info_outline_rounded,
                  color:
                      AppColors.primary,
                  size: 18,
                ),

                SizedBox(
                  width: 8,
                ),

                Expanded(

                  child:
                      Text(
                    'InfoGuard AI will analyze the content available through this URL.',

                    style:
                        TextStyle(
                      color:
                          AppColors.deepNavy,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ==========================================================
  // VERIFY BUTTON
  // ==========================================================

  Widget buildVerifyButton() {

    return SizedBox(

      width:
          double.infinity,

      height: 55,

      child:
          ElevatedButton(

        onPressed:
            isLoading
                ? null
                : verifyContent,

        style:
            ElevatedButton.styleFrom(

          backgroundColor:
              AppColors.primary,

          foregroundColor:
              Colors.white,

          disabledBackgroundColor:
              AppColors.primary.withValues(
            alpha: 0.6,
          ),

          elevation: 0,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(16),
          ),
        ),

        child:
            isLoading

                ? const Row(

                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [

                      SizedBox(

                        width: 22,
                        height: 22,

                        child:
                            CircularProgressIndicator(
                          color:
                              Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),

                      SizedBox(
                        width: 10,
                      ),

                      Text(
                        'Verifying...',
                        style:
                            TextStyle(
                          fontSize: 15,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                  )

                : const Row(

                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [

                      Icon(
                        Icons.search_rounded,
                      ),

                      SizedBox(
                        width: 8,
                      ),

                      Text(
                        'Verify Content',
                        style:
                            TextStyle(
                          fontSize: 15,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }


  // ==========================================================
  // TRUST MESSAGE
  // ==========================================================

  Widget buildTrustMessage() {

    return Row(

      children: [

        Container(

          padding:
              const EdgeInsets.all(8),

          decoration:
              BoxDecoration(

            color:
                const Color(0xFFE9F8F1),

            borderRadius:
                BorderRadius.circular(10),
          ),

          child:
              const Icon(
            Icons.shield_outlined,
            color:
                AppColors.success,
            size: 20,
          ),
        ),

        const SizedBox(
          width: 11,
        ),

        const Expanded(

          child:
              Text(
            'InfoGuard analyzes evidence before giving a verification result.',

            style:
                TextStyle(
              color:
                  AppColors.secondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }


  // ==========================================================
  // RECENT VERIFICATIONS
  // ==========================================================

  Widget buildRecentSection() {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Recent verifications',

          style:
              TextStyle(
            color:
                AppColors.deepNavy,
            fontSize: 17,
            fontWeight:
                FontWeight.w800,
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        Container(

          width:
              double.infinity,

          padding:
              const EdgeInsets.all(24),

          decoration:
              BoxDecoration(

            color:
                Colors.white,

            borderRadius:
                BorderRadius.circular(18),

            border:
                Border.all(
              color:
                  AppColors.border,
            ),
          ),

          child:
              const Column(

            children: [

              Icon(
                Icons.history_rounded,
                color:
                    Color(0xFFA0A8B5),
                size: 31,
              ),

              SizedBox(
                height: 8,
              ),

              Text(
                'No verifications yet',

                style:
                    TextStyle(
                  color:
                      AppColors.deepNavy,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              SizedBox(
                height: 4,
              ),

              Text(
                'Your verification history will appear here.',

                textAlign:
                    TextAlign.center,

                style:
                    TextStyle(
                  color:
                      AppColors.secondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  // ==========================================================
  // CARD
  // ==========================================================

  Widget buildCard({
    required Widget child,
  }) {

    return Container(

      width:
          double.infinity,

      padding:
          const EdgeInsets.all(19),

      decoration:
          BoxDecoration(

        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(21),

        border:
            Border.all(
          color:
              AppColors.border,
        ),

        boxShadow: [

          BoxShadow(

            color:
                Colors.black.withValues(
              alpha: 0.035,
            ),

            blurRadius:
                18,

            offset:
                const Offset(0, 7),
          ),
        ],
      ),

      child:
          child,
    );
  }


  // ==========================================================
  // INPUT DECORATION
  // ==========================================================

  InputDecoration inputDecoration({
    required String hint,
    required IconData icon,
  }) {

    return InputDecoration(

      hintText:
          hint,

      hintStyle:
          const TextStyle(
        color:
            Color(0xFF9AA3B2),
        fontSize: 13,
      ),

      prefixIcon:
          Icon(
        icon,
        color:
            AppColors.secondary,
      ),

      filled:
          true,

      fillColor:
          AppColors.background,

      contentPadding:
          const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 16,
      ),

      border:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(15),
        borderSide:
            const BorderSide(
          color:
              AppColors.border,
        ),
      ),

      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(15),
        borderSide:
            const BorderSide(
          color:
              AppColors.border,
        ),
      ),

      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(15),
        borderSide:
            const BorderSide(
          color:
              AppColors.primary,
          width: 1.5,
        ),
      ),
    );
  }
}