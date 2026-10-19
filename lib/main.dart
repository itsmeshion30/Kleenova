import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

// KLEENOVA application configuration.
// Replace these with your Supabase project values. Never put PayMongo secret keys here.
const supabaseUrl = 'https://mzzeltvikmijpqajhtty.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im16emVsdHZpa21panBxYWpodHR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1ODQ5MzQsImV4cCI6MjEwNTE2MDkzNH0.rwCP8jbicvqoifZAGHK4xHVTeSf-FhmyZxQdq12Efhc';

final supabase = Supabase.instance.client;

class ServiceItem {
  final String id, name, description, duration, imageUrl, category;
  final num price;
  const ServiceItem({required this.id, required this.name, required this.description, required this.duration, required this.price, required this.imageUrl, required this.category});
  factory ServiceItem.fromMap(Map<String, dynamic> row) => ServiceItem(
    id: row['id'].toString(),
    name: (row['name'] ?? 'Cleaning service').toString(),
    description: (row['description'] ?? '').toString(),
    duration: 'Approx. ${row['duration_hours'] ?? 2} hours',
    price: (row['price'] as num?) ?? 0,
    imageUrl: (row['image_url'] ?? '').toString(),
    category: (row['category'] ?? 'Cleaning').toString(),
  );
}


// Notification helpers. These only touch the notifications table and do not alter
// the booking/payment transaction flow.
Future<void> createKleenovaNotification({
  required String userId,
  required String title,
  required String message,
  String type = 'system',
  String? bookingId,
}) async {
  try {
    // Prevent the exact same unread notification from being inserted twice.
    // Different status changes (for example Confirmed -> Completed) remain
    // separate alerts because they contain different messages.
    if (bookingId != null && bookingId.isNotEmpty) {
      final existing = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('title', title)
          .eq('message', message)
          .eq('booking_id', bookingId)
          .eq('is_read', false)
          .limit(1);
      if (existing.isNotEmpty) return;
    }

    await supabase.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
      if (bookingId != null && bookingId.isNotEmpty) 'booking_id': bookingId,
      'is_read': false,
    });
  } catch (_) {
    // Keep notifications non-blocking: a notification failure must never break
    // booking, payment, or status operations.
  }
}

Future<void> notifyAdmins({
  required String title,
  required String message,
  String type = 'admin',
  String? bookingId,
}) async {
  try {
    final rows = await supabase.from('profiles').select('id').eq('role', 'admin');
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await createKleenovaNotification(
        userId: id,
        title: title,
        message: message,
        type: type,
        bookingId: bookingId,
      );
    }
  } catch (_) {}
}

Future<void> markNotificationRead(String id) async {
  final user = supabase.auth.currentUser;
  if (user == null) {
    throw Exception('Your admin session has expired. Please sign in again.');
  }

  final now = DateTime.now().toUtc().toIso8601String();
  await supabase
      .from('notifications')
      .update({'is_read': true, 'read_at': now})
      .eq('id', id)
      .eq('user_id', user.id);

  // Confirm the change was saved in Supabase instead of only changing the UI.
  final saved = await supabase
      .from('notifications')
      .select('id, is_read')
      .eq('id', id)
      .eq('user_id', user.id)
      .maybeSingle();

  if (saved == null || saved['is_read'] != true) {
    throw Exception(
      'The notification could not be saved as read. Check the notifications UPDATE policy in Supabase (RLS).',
    );
  }
}

Future<void> markAllNotificationsRead(String userId) async {
  await supabase.from('notifications').update({
    'is_read': true,
    'read_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('user_id', userId).eq('is_read', false);
}

Future<void> deleteNotification(String id) async {
  await supabase.from('notifications').delete().eq('id', id);
}

Future<void> deleteAllNotifications(String userId) async {
  await supabase.from('notifications').delete().eq('user_id', userId);
}


const coffee = Color(0xFF0F5C73);
const caramel = Color(0xFFFF7A59);
const cream = Color(0xFFFFF4EA);
const beige = Color(0xFFE6DCD2);
const ink = Color(0xFF243746);
const sage = Color(0xFF6C9A72);
const champagne = Color(0xFFFFC857);
const deepSage = Color(0xFF176B87);
const mist = Color(0xFFE8F6F7);
const warmWhite = Color(0xFFFFFFFF);
const coral = Color(0xFFFF6B57);
const aqua = Color(0xFF31B7C7);
const plum = Color(0xFF8B5FBF);
const sky = Color(0xFF4FA7E8);
const blush = Color(0xFFFFC2B3);
const lavender = Color(0xFFD8C4F0);
const peach = Color(0xFFFFD39E);


/// KLEENOVA interaction polish: a small press animation used on cards, buttons
/// and navigation actions without changing the underlying business logic.
class KleenovaPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double pressedScale;
  final Duration duration;

  const KleenovaPress({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.pressedScale = .975,
    this.duration = const Duration(milliseconds: 120),
  });

  @override
  State<KleenovaPress> createState() => _KleenovaPressState();
}

class _KleenovaPressState extends State<KleenovaPress> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius;
    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          splashColor: Theme.of(context).colorScheme.primary.withOpacity(.10),
          highlightColor: Theme.of(context).colorScheme.primary.withOpacity(.05),
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A lightweight animated modal used for confirmations so overlays feel
/// intentional instead of appearing instantly.
class KleenovaPageTransitionsBuilder extends PageTransitionsBuilder {
  const KleenovaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, .018),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

Future<T?> showKleenovaOverlay<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'KLEENOVA overlay',
    barrierColor: Colors.black.withOpacity(.42),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Future<bool> confirmKleenovaAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'No',
  bool destructive = false,
}) async {
  return await showKleenovaOverlay<bool>(
        context: context,
        barrierDismissible: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(.55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.18),
                        blurRadius: 38,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: (destructive ? Colors.redAccent : coffee)
                                  .withOpacity(.11),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              destructive
                                  ? Icons.delete_outline_rounded
                                  : Icons.auto_awesome_rounded,
                              color: destructive ? Colors.redAccent : coffee,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        message,
                        style: TextStyle(
                          height: 1.4,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              child: Text(cancelLabel),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: destructive
                                    ? Colors.redAccent
                                    : coffee,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pop(true),
                              child: Text(confirmLabel),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ) ??
      false;
}

class KleenovaLogoMark extends StatelessWidget {
  final double size;
  final bool onDark;
  const KleenovaLogoMark({super.key, this.size = 56, this.onDark = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _KleenovaLogoPainter(
            primary: onDark ? Colors.white : const Color(0xFF176B87),
            accent: const Color(0xFFFF8057),
          ),
        ),
      );
}

class _KleenovaLogoPainter extends CustomPainter {
  final Color primary;
  final Color accent;
  const _KleenovaLogoPainter({required this.primary, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final house = Path()
      ..moveTo(23 * s, 50 * s)
      ..lineTo(50 * s, 23 * s)
      ..lineTo(77 * s, 50 * s)
      ..lineTo(77 * s, 78 * s)
      ..lineTo(23 * s, 78 * s)
      ..close();
    stroke.color = primary;
    canvas.drawPath(house, stroke);

    final leaf = Path()
      ..moveTo(50 * s, 69 * s)
      ..cubicTo(31 * s, 58 * s, 35 * s, 37 * s, 52 * s, 30 * s)
      ..cubicTo(65 * s, 42 * s, 62 * s, 58 * s, 50 * s, 69 * s)
      ..close();
    stroke.color = accent;
    canvas.drawPath(leaf, stroke);

    final vein = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(50, 64) * s, const Offset(50, 36) * s, vein);
    canvas.drawLine(const Offset(50, 51) * s, const Offset(59, 44) * s, vein);
    canvas.drawLine(const Offset(50, 55) * s, const Offset(42, 48) * s, vein);
  }

  @override
  bool shouldRepaint(covariant _KleenovaLogoPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.accent != accent;
}

class KleenovaBrand extends StatelessWidget {
  final double size;
  final bool onDark;
  final bool compact;
  const KleenovaBrand({super.key, this.size = 28, this.onDark = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white : const Color(0xFF243746);
    final accent = onDark ? const Color(0xFFFFC857) : const Color(0xFFFF8057);
    final markSize = compact ? size * 1.15 : size * 1.45;

    final wordmark = RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: compact ? 1.1 : 1.8,
          height: 1,
        ),
        children: [
          TextSpan(text: 'KLEE', style: TextStyle(color: textColor)),
          TextSpan(text: 'NOVA', style: TextStyle(color: accent)),
        ],
      ),
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KleenovaLogoMark(size: markSize, onDark: onDark),
          const SizedBox(width: 8),
          wordmark,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KleenovaLogoMark(size: markSize, onDark: onDark),
        const SizedBox(height: 7),
        wordmark,
        const SizedBox(height: 4),
        Text(
          'CLEAN SPACES. BETTER DAYS.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: onDark ? Colors.white70 : const Color(0xFF60717B),
            fontSize: (size * .27).clamp(7, 10),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

// App-wide theme selection. Changing this notifier rebuilds MaterialApp immediately.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

// True while a customer (non-admin) is signed in: the UI is shown in a phone-sized
// frame, centered on large screens. Admin uses the full PC layout.
final ValueNotifier<bool> phoneLayout = ValueNotifier<bool>(false);

class _PhoneFrame extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const _PhoneFrame({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final framed = enabled && mq.size.width > 520;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final vPad = framed && mq.size.height > 720 ? 14.0 : 0.0;
    final phoneW = framed ? 440.0 : mq.size.width;
    final phoneH = mq.size.height - vPad * 2;
    return Container(
      decoration: BoxDecoration(
        gradient: framed
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF0E1A20), Color(0xFF1B1418)]
                    : const [Color(0xFFD6EEF2), Color(0xFFFFE6DC)],
              )
            : null,
        color: framed ? null : Colors.transparent,
      ),
      padding: EdgeInsets.symmetric(vertical: vPad),
      alignment: Alignment.center,
      child: Container(
        width: framed ? phoneW : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(framed ? 36 : 0),
          boxShadow: framed
              ? const [BoxShadow(color: Color(0x330F3B4A), blurRadius: 44, offset: Offset(0, 18))]
              : null,
        ),
        clipBehavior: framed ? Clip.antiAlias : Clip.none,
        child: MediaQuery(
          data: mq.copyWith(size: Size(phoneW, phoneH)),
          child: child,
        ),
      ),
    );
  }
}

class KleenovaApp extends StatelessWidget {
  const KleenovaApp({super.key});

  ThemeData _lightTheme() => ThemeData(
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: KleenovaPageTransitionsBuilder(),
            TargetPlatform.iOS: KleenovaPageTransitionsBuilder(),
            TargetPlatform.macOS: KleenovaPageTransitionsBuilder(),
            TargetPlatform.windows: KleenovaPageTransitionsBuilder(),
            TargetPlatform.linux: KleenovaPageTransitionsBuilder(),
            TargetPlatform.fuchsia: KleenovaPageTransitionsBuilder(),
          },
        ),
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        fontFamily: 'sans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: coffee,
          brightness: Brightness.light,
          primary: coffee,
          secondary: caramel,
          tertiary: sky,
          surface: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFF0E3D8),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, letterSpacing: -.6),
          headlineMedium: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(height: 1.35),
          bodyMedium: TextStyle(height: 1.3),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFFFF),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE3EAEC)),
          ),
          shadowColor: const Color(0x1A0F5C73),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFEFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE3EAEC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: caramel, width: 1.7),
          ),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF675850)),
          floatingLabelStyle: const TextStyle(color: deepSage, fontWeight: FontWeight.w700),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: coffee,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            elevation: 0,
            shadowColor: coffee.withOpacity(.22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: coffee,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: coffee,
            side: const BorderSide(color: Color(0xFFDDBEAA), width: 1.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 74,
          indicatorShape: const StadiumBorder(),
          iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
              color: st.contains(WidgetState.selected) ? coffee : const Color(0xFF7A8B93))),
          backgroundColor: const Color(0xFFFFFFFF),
          indicatorColor: const Color(0xFFD9F1F4),
          elevation: 0,
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: deepSage),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: const BorderSide(color: Color(0xFFE3EAEC)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: caramel,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: coffee,
          contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  ThemeData _darkTheme() => ThemeData(
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: KleenovaPageTransitionsBuilder(),
            TargetPlatform.iOS: KleenovaPageTransitionsBuilder(),
            TargetPlatform.macOS: KleenovaPageTransitionsBuilder(),
            TargetPlatform.windows: KleenovaPageTransitionsBuilder(),
            TargetPlatform.linux: KleenovaPageTransitionsBuilder(),
            TargetPlatform.fuchsia: KleenovaPageTransitionsBuilder(),
          },
        ),
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8A5B),
          brightness: Brightness.dark,
          primary: const Color(0xFFFF8A5B),
          secondary: const Color(0xFF45D0C8),
          tertiary: const Color(0xFFFFC857),
          surface: const Color(0xFF1F1A22),
          surfaceContainerHighest: Color(0xFF2F2630),
          onSurface: Colors.white,
          onSurfaceVariant: Color(0xFFEDE3F1),
          onBackground: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, letterSpacing: -.5, color: Colors.white),
          headlineMedium: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, color: Colors.white),
          headlineSmall: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, color: Colors.white),
          titleLarge: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, color: Colors.white),
          titleMedium: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          titleSmall: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          bodyLarge: TextStyle(height: 1.35, color: Colors.white),
          bodyMedium: TextStyle(height: 1.3, color: Colors.white),
          bodySmall: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
          labelMedium: TextStyle(color: Colors.white),
          labelSmall: TextStyle(color: Colors.white),
        ),
        scaffoldBackgroundColor: const Color(0xFF171312),
        canvasColor: const Color(0xFF171312),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF2A211E),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          contentTextStyle: TextStyle(color: Color(0xFFEDE3F1)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171312),
          foregroundColor: Color(0xFFF8F2EB),
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF2A211E),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF51413B)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2220),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF51413B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFD9A18B), width: 1.6),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD9A18B),
            foregroundColor: const Color(0xFF211B19),
            minimumSize: const Size.fromHeight(54),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          height: 76,
          backgroundColor: Color(0xFF211B20),
          indicatorColor: Color(0xFF40303A),
          elevation: 0,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Color(0xFFF5EDF4), fontWeight: FontWeight.w600),
          ),
          iconTheme: WidgetStatePropertyAll(IconThemeData(color: Color(0xFFF5EDF4))),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF51434D), thickness: 1),
        iconTheme: const IconThemeData(color: Color(0xFFEDE3F1)),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFFFF8A5B),
          selectionColor: Color(0x66FF8A5B),
          selectionHandleColor: Color(0xFFFF8A5B),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFFFF8A5B) : const Color(0xFF3A3038)),
          checkColor: const WidgetStatePropertyAll(Color(0xFF211B19)),
          side: const BorderSide(color: Color(0xFF8C7C88)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFFFF8A5B) : const Color(0xFFBDB2BC)),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF654538) : const Color(0xFF39313A)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF302831),
          selectedColor: const Color(0xFF4A3A34),
          disabledColor: const Color(0xFF282229),
          labelStyle: const TextStyle(color: Color(0xFFF5EDF4)),
          secondaryLabelStyle: const TextStyle(color: Color(0xFFF5EDF4)),
          side: const BorderSide(color: Color(0xFF51434D)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Color(0xFFF5EDF4),
          iconColor: Color(0xFFEDE3F1),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF2A222B),
          textStyle: TextStyle(color: Color(0xFFF5EDF4)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF241E25),
          modalBackgroundColor: Color(0xFF241E25),
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF393039),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFB18F),
            side: const BorderSide(color: Color(0xFF8A6B60)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF8A5B),
            foregroundColor: const Color(0xFF211B19),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'KLEENOVA',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: phoneLayout,
            builder: (_, on, __) => _PhoneFrame(enabled: on, child: child ?? const SizedBox.shrink()),
          ),
          home: const IntroPage(),
        ),
      );
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;

  // Keep a local copy of the session so the widget ALWAYS rebuilds
  // when Supabase signs the user in or out.
  Session? _session;
  bool _passwordRecovery = false;

  @override
  void initState() {
    super.initState();

    // Read any existing session immediately.
    _session = supabase.auth.currentSession;

    // Listen to ALL authentication changes.
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;

      setState(() {
        _session = data.session;

        if (data.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecovery = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  // Explicitly sync the gate after a successful login. This avoids relying
  // solely on the auth stream event to rebuild the app.
  void _syncSession() {
    if (!mounted) return;
    setState(() {
      _session = supabase.auth.currentSession;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_passwordRecovery) {
      return ResetPasswordPage(
        onComplete: () {
          if (!mounted) return;

          setState(() {
            _passwordRecovery = false;
            _session = supabase.auth.currentSession;
          });
        },
      );
    }

    // No active session -> show login.
    if (_session == null) {
      // Keep the sign-in / create-account screen in its original light style,
      // regardless of the user's selected app theme.
      final loginTheme = ThemeData.light().copyWith(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: coffee,
          brightness: Brightness.light,
          primary: coffee,
          secondary: caramel,
          surface: warmWhite,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          foregroundColor: ink,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: beige),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: caramel, width: 1.6),
          ),
        ),
      );
      return Theme(data: loginTheme, child: LoginPage(onSignedIn: _syncSession));
    }

    // Active session -> show the app.
    return const HomePage();
  }
}

class ResetPasswordPage extends StatefulWidget {
  final VoidCallback onComplete;
  const ResetPasswordPage({super.key, required this.onComplete});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool loading = false;
  bool showPassword = false;
  bool showConfirmPassword = false;

  @override
  void dispose() {
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final value = password.text;
    final confirm = confirmPassword.text;

    if (value.length < 6) {
      _msg('Password must be at least 6 characters.');
      return;
    }
    if (value != confirm) {
      _msg('Passwords do not match.');
      return;
    }

    setState(() => loading = true);
    try {
      await supabase.auth.updateUser(
        UserAttributes(password: value),
      );

      if (!mounted) return;
      _msg('Password updated successfully. Please sign in again.');
      await supabase.auth.signOut();
      if (mounted) widget.onComplete();
    } on AuthException catch (e) {
      _msg(e.message);
    } catch (e) {
      _msg('Could not update your password: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(message),
      ),
    );
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: beige),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: beige),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: caramel, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEAF5FF), Color(0xFFF9FCFF), Color(0xFFDDEEFF)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -75,
            right: -65,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFB9DCFA).withOpacity(.45),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -95,
            left: -65,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF9CCCF4).withOpacity(.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 550),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white.withOpacity(.94),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KleenovaBrand(size: 27),
                        const SizedBox(height: 28),
                        const Text(
                          'Create a new password',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF261E1B),
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose a new password for your KLEENOVA account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Color(0xFF5D514B)),
                            fontSize: 14.5,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: password,
                          obscureText: !showPassword,
                          decoration: _field(
                            'New password',
                            Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                () => showPassword = !showPassword,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmPassword,
                          obscureText: !showConfirmPassword,
                          onSubmitted: (_) => loading ? null : _updatePassword(),
                          decoration: _field(
                            'Confirm new password',
                            Icons.lock_reset_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(showConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                () => showConfirmPassword = !showConfirmPassword,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: loading ? null : _updatePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: coffee,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: coffee.withOpacity(.55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Update password',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: .82, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 2200), _openAuthGate);
  }

  void _openAuthGate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&w=1400&q=85',
              ),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Color(0xB86B4031),
                BlendMode.srcOver,
              ),
            ),
          ),
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 104,
                      width: 104,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: ink.withOpacity(.2),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const KleenovaLogoMark(size: 66),
                    ),
                    const SizedBox(height: 24),
                    const KleenovaBrand(size: 32, onDark: true),
                    const SizedBox(height: 8),
                    const Text(
                      'A cleaner home, a calmer you.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 36),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}


class LoginPage extends StatefulWidget {
  final VoidCallback? onSignedIn;
  const LoginPage({super.key, this.onSignedIn});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();

  bool loading = false;
  bool create = false;
  bool showPassword = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  String _authErrorMessage(AuthException e) {
    final message = e.message.trim();
    final lower = message.toLowerCase();
    final status = e.statusCode?.trim();

    if (status == '429' || lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many authentication requests right now. Please wait a little before trying again. ' +
          (status != null ? 'Supabase status: $status.' : '');
    }

    if (lower.contains('user already registered') || lower.contains('already registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }

    if (lower.contains('email not confirmed') || lower.contains('email_not_confirmed')) {
      return 'Your email has not been confirmed yet. Check your inbox, then sign in.';
    }

    if (lower.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }

    if (lower.contains('password') && lower.contains('weak')) {
      return 'Your password is too weak. Use a stronger password and try again.';
    }

    if (lower.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }

    return message.isEmpty ? 'Authentication failed. Please try again.' : message;
  }

  Future<void> submit() async {
    // Prevent double taps from sending multiple Auth requests.
    if (loading) return;

    final emailValue = email.text.trim();
    final passwordValue = password.text;

    if (emailValue.isEmpty || passwordValue.isEmpty) {
      return msg('Enter your email and password.');
    }

    if (!emailValue.contains('@') || !emailValue.contains('.')) {
      return msg('Please enter a valid email address.');
    }

    if (create) {
      if (name.text.trim().isEmpty) return msg('Enter your full name.');
      if (phone.text.trim().isEmpty) return msg('Enter your phone number.');
      if (address.text.trim().isEmpty) return msg('Enter your home address.');
    }

    if (!mounted) return;
    setState(() => loading = true);

    try {
      if (create) {
        final res = await supabase.auth.signUp(
          email: emailValue,
          password: passwordValue,
          data: {
            'full_name': name.text.trim(),
            'phone': phone.text.trim(),
            'address': address.text.trim(),
          },
        );

        final user = res.user;
        if (user != null) {
          // Keep the existing profile creation behavior intact.
          await supabase.from('profiles').upsert({
            'id': user.id,
            'email': user.email,
            'full_name': name.text.trim(),
            'phone': phone.text.trim(),
            'address': address.text.trim(),
            'role': 'customer',
          });
        }

        // With Confirm email disabled, Supabase returns a session immediately.
        // With Confirm email enabled, session is null until the email is verified.
        if (res.session != null) {
          appThemeMode.value = ThemeMode.light;
          widget.onSignedIn?.call();
          msg('Account created successfully. You are now signed in.');
        } else {
          msg('Account created. Check your email to confirm your account, then sign in.');
        }
      } else {
        final response = await supabase.auth.signInWithPassword(
          email: emailValue,
          password: passwordValue,
        );

        // A successful password login should always create a session.
        // AuthGate listens for this session and switches to HomePage.
        if (response.session == null) {
          msg('Sign in failed. No session was created.');
          return;
        }

        // A different account always starts with the Light theme.
        appThemeMode.value = ThemeMode.light;
        // Force AuthGate to rebuild immediately with the new session.
        widget.onSignedIn?.call();
      }
    } on AuthException catch (e) {
      msg(_authErrorMessage(e));
    } catch (e) {
      msg('Could not complete request: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: email.text.trim());
    bool sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !sending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendReset() async {
              final value = controller.text.trim();
              if (value.isEmpty || !value.contains('@')) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter a valid email address.')),
                );
                return;
              }

              setDialogState(() => sending = true);
              try {
                // Android deep link: register this scheme/host in
                // android/app/src/main/AndroidManifest.xml and in Supabase
                // Authentication > URL Configuration > Redirect URLs.
                const redirectTo = 'io.supabase.flutter://reset-callback/';
                await supabase.auth.resetPasswordForEmail(
                  value,
                  redirectTo: redirectTo,
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                msg('Password reset link sent. Check your email.');
              } on AuthException catch (e) {
                if (dialogContext.mounted) {
                  setDialogState(() => sending = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(_authErrorMessage(e))),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  setDialogState(() => sending = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Could not send reset email: $e')),
                  );
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Forgot password?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter your account email and we will send you a secure password reset link.',
                    style: TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => sending ? null : sendReset(),
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending ? null : sendReset,
                  style: FilledButton.styleFrom(
                    backgroundColor: coffee,
                    foregroundColor: Colors.white,
                  ),
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(s),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    const blue = Color(0xFF1769AA);
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIcon: Icon(icon, size: 22, color: const Color(0xFF3979AE)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7FAFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      labelStyle: const TextStyle(
        color: Color(0xFF687B91),
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: blue,
        fontWeight: FontWeight.w700,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD8E5F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: blue, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9534F)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9534F), width: 2),
      ),
    );
  }

  Widget _brandHeader() {
    const blue = Color(0xFF1769AA);
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4CA0E8), Color(0xFF155A9B)],
            ),
            borderRadius: BorderRadius.circular(27),
            boxShadow: const [
              BoxShadow(
                color: Color(0x302A72B5),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: KleenovaLogoMark(size: 57, onDark: true),
          ),
        ),
        const SizedBox(height: 18),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'sans',
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1,
            ),
            children: [
              TextSpan(text: 'KLEE', style: TextStyle(color: Color(0xFF163654))),
              TextSpan(text: 'NOVA', style: TextStyle(color: Color(0xFF2584D5))),
            ],
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'CLEAN SPACES  •  BETTER LIVING',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF5B7590),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'A cleaner home, a calmer you.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF48627B),
            fontSize: 14.5,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _loginCard() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE0EBF5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              create ? 'Create your account' : 'Welcome back',
              style: TextStyle(
                color: Color(0xFF183A5A),
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              create
                  ? 'Set up your KLEENOVA account in a few simple steps.'
                  : 'Sign in to manage your cleaning appointments.',
              style: TextStyle(
                color: Color(0xFF61758A),
                fontSize: 14.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 23),

            if (create) ...[
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(
                  label: 'Full name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: _fieldDecoration(
                  label: 'Phone number',
                  icon: Icons.phone_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.sentences,
                decoration: _fieldDecoration(
                  label: 'Home address',
                  icon: Icons.home_outlined,
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: 'Email address',
                icon: Icons.mail_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: !showPassword,
              onSubmitted: (_) => loading ? null : submit(),
              decoration: _fieldDecoration(
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  tooltip: showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF5C7187),
                  ),
                  onPressed: () =>
                      setState(() => showPassword = !showPassword),
                ),
              ),
            ),

            if (!create) ...[
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _forgotPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: const Color(0xFF1769AA),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: loading ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1769AA),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF1769AA).withOpacity(.55),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: loading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          create ? 'Create account' : 'Sign in',
                          key: ValueKey(create),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            TextButton(
              onPressed: () => setState(() => create = !create),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1769AA),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  create
                      ? 'Already have an account? Sign in'
                      : 'New to KLEENOVA? Create an account',
                  key: ValueKey(create),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&w=1400&q=85',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
          ),
          Positioned.fill(
            child: Container(color: const Color(0xD9FFF7EF)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 760;

                return Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      compact ? 12 : 22,
                      24,
                      24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 550),
                      child: Column(
                        children: [
                          _brandHeader(),
                          SizedBox(height: compact ? 18 : 26),
                          _loginCard(),
                          const SizedBox(height: 18),
                          const Text(
                            'Thoughtful care for every corner.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF58738D),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  Timer? _autoRefreshTimer;
  Map<String, dynamic>? profile;
  bool loadingProfile = true;
  int unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    loadProfile();
    _loadUnreadNotifications();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadUnreadNotifications();
      loadProfile();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    Future.microtask(() => phoneLayout.value = false);
    super.dispose();
  }

  Future<void> _loadUnreadNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final rows = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);
      if (!mounted) return;
      setState(() => unreadNotifications = (rows as List).length);
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    try {
      profile = await supabase
          .from('profiles')
          .select()
          .eq('id', supabase.auth.currentUser!.id)
          .maybeSingle();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      loadingProfile = false;
      if (profile?['role'] == 'admin') tab = 0;
    });
    final isAdminNow = profile?['role'] == 'admin';
    if (phoneLayout.value == isAdminNow) phoneLayout.value = !isAdminNow;
  }

  Future<void> logout() async {
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Log out?',
      message: 'Are you sure you want to log out of KLEENOVA?',
      confirmLabel: 'Yes, log out',
      cancelLabel: 'Stay signed in',
    );
    if (!confirmed || !mounted) return;

    try {
      // Each newly signed-in account starts in Light mode.
      appThemeMode.value = ThemeMode.light;
      await supabase.auth.signOut(scope: SignOutScope.local);
      if (!mounted) return;
      // Reset the navigation stack so the signed-out screen is shown even if
      // the auth-state stream does not rebuild the current dashboard promptly.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not log out. Please try again. ($e)')),
      );
    }
  }

  Widget _notificationNavIcon(bool selected) {
    final icon = Icon(
      selected ? Icons.notifications_rounded : Icons.notifications_none_rounded,
    );
    if (unreadNotifications <= 0) return icon;
    final label = unreadNotifications > 99 ? '99+' : '$unreadNotifications';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -9,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wait for the profile/role before building the dashboard. This prevents
    // the customer dashboard from flashing briefly when an admin signs in.
    if (loadingProfile) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KleenovaBrand(size: 30),
              const SizedBox(height: 18),
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2.5,
              ),
            ],
          ),
        ),
      );
    }

    final admin = profile?['role'] == 'admin';

    final pages = <Widget>[];
    if (admin) {
      pages.addAll([
        const AdminPage(),
        ProfilePage(profile: profile, onLogout: logout),
      ]);
    } else {
      pages.addAll([
        CustomerHome(
          onGoToTab: (value) { if (mounted) setState(() => tab = value); },
          onBook: (service) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceDetailsPage(service: service),
            ),
          ),
        ),
        CustomerServicesPage(
          onBook: (service) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceDetailsPage(service: service),
            ),
          ),
        ),
        FavoritesPage(
          onBook: (service) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceDetailsPage(service: service),
            ),
          ),
          onBrowseServices: () {
            if (mounted) {
              setState(() => tab = 1);
            }
          },
        ),
        const BookingsPage(),
        const AlertsPage(),
        ProfilePage(profile: profile, onLogout: logout),
      ]);
    }

    final selected = tab.clamp(0, pages.length - 1);

    if (admin && MediaQuery.sizeOf(context).width >= 700) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: const Color(0xFF0B4A5F),
              selectedIndex: selected,
              labelType: NavigationRailLabelType.all,
              indicatorColor: const Color(0xFF2BA5BC),
              minWidth: 78,
              unselectedIconTheme: const IconThemeData(color: Colors.white70),
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedLabelTextStyle: const TextStyle(color: Colors.white70, fontSize: 12),
              selectedLabelTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              leading: const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 10),
                child: KleenovaLogoMark(size: 40, onDark: true),
              ),
              onDestinationSelected: (value) {
                setState(() => tab = value);
                _loadUnreadNotifications();
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: Text('Admin'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Profile'),
                ),
              ],
            ),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor.withOpacity(.4)),
            Expanded(child: SafeArea(child: pages[selected])),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: pages[selected]),
      bottomNavigationBar: NavigationBar(
        height: 78,
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        selectedIndex: selected,
        onDestinationSelected: (value) {
          setState(() => tab = value);
          _loadUnreadNotifications();
        },
        destinations: admin
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Admin',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ]
            : [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.cleaning_services_outlined),
                  selectedIcon: Icon(Icons.cleaning_services_rounded),
                  label: 'Services',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.favorite_border_rounded),
                  selectedIcon: Icon(Icons.favorite_rounded),
                  label: 'Favorites',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Bookings',
                ),
                NavigationDestination(
                  icon: _notificationNavIcon(false),
                  selectedIcon: _notificationNavIcon(true),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
      ),
    );
  }
}

class CustomerServicesPage extends StatefulWidget {
  final ValueChanged<ServiceItem> onBook;
  const CustomerServicesPage({super.key, required this.onBook});
  @override State<CustomerServicesPage> createState() => _CustomerServicesPageState();
}

class _CustomerServicesPageState extends State<CustomerServicesPage> {
  late Future<List<ServiceItem>> future;
  Timer? _autoRefreshTimer;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _category = 'All';
  static const categories = ['All', 'Cleaning', 'Maintenance', 'Repair', 'Home Care', 'Other'];

  @override
  void initState() {
    super.initState();
    future = _loadServices();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final next = await _loadServices();
      if (!mounted) return;
      setState(() => future = Future.value(next));
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<ServiceItem>> _loadServices() async {
    final rows = await supabase
        .from('services')
        .select()
        .eq('is_active', true)
        .order('name');
    return (rows as List)
        .map((row) => ServiceItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  List<ServiceItem> _filtered(List<ServiceItem> all) {
    final q = _search.trim().toLowerCase();
    return all.where((service) {
      final matchesSearch = q.isEmpty ||
          service.name.toLowerCase().contains(q) ||
          service.description.toLowerCase().contains(q);
      final matchesCategory = _category == 'All' ||
          service.category.toLowerCase() == _category.toLowerCase();
      return matchesSearch && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF171312) : const Color(0xFFFAF4EE);
    final surface = isDark ? const Color(0xFF2A211E) : Colors.white;
    final primaryText = isDark ? const Color(0xFFF8F2EB) : const Color(0xFF173B55);
    final mutedText = isDark ? const Color(0xFFCEC3BD) : const Color(0xFF71808A);
    final borderColor = isDark ? const Color(0xFF51413B) : const Color(0xFFE6D8CE);

    return Container(
      color: pageBg,
      child: RefreshIndicator(
        color: const Color(0xFFFF8057),
        onRefresh: () async => setState(() => future = _loadServices()),
        child: FutureBuilder<List<ServiceItem>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load services.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final all = snapshot.data ?? [];
            final services = _filtered(all);
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('Services', style: TextStyle(color: primaryText, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.7))),
                        Container(width: 42, height: 42, decoration: BoxDecoration(color: surface, shape: BoxShape.circle), child: Icon(Icons.tune_rounded, color: primaryText, size: 20)),
                      ]),
                      const SizedBox(height: 5),
                      Text('Find a service that fits your home.', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : mutedText), fontSize: 13)),
                      const SizedBox(height: 17),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _search = value),
                        decoration: InputDecoration(
                          hintText: 'Search services',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _searchController.clear(); setState(() => _search = ''); }),
                          filled: true,
                          fillColor: surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFFF8057), width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final category = categories[index];
                            final selected = category == _category;
                            return ChoiceChip(
                              label: Text(category),
                              selected: selected,
                              onSelected: (_) => setState(() => _category = category),
                              selectedColor: const Color(0xFFFF8057),
                              backgroundColor: surface,
                              side: BorderSide(color: selected ? const Color(0xFFFF8057) : borderColor),
                              labelStyle: TextStyle(color: selected ? Colors.white : primaryText, fontWeight: FontWeight.w700, fontSize: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(child: Text('Available services', style: TextStyle(color: primaryText, fontSize: 19, fontWeight: FontWeight.w900))),
                        Text('${services.length}', style: const TextStyle(color: Color(0xFFFF6F4D), fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 11),
                    ]),
                  ),
                ),
                if (services.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(padding: const EdgeInsets.fromLTRB(20, 30, 20, 120), child: _emptyServices()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _ModernServiceCard(service: services[index], onOpen: () => widget.onBook(services[index])),
                        childCount: services.length,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: .72,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyServices() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? const Color(0xFF51413B) : const Color(0xFFE6D8CE)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cleaning_services_outlined, color: isDark ? const Color(0xFFFFB59A) : const Color(0xFF6F3E32), size: 42),
        const SizedBox(height: 12),
        Text('No services found', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? const Color(0xFFF8F2EB) : const Color(0xFF26333D), fontSize: 16)),
        const SizedBox(height: 5),
        Text('Try another search or category.', textAlign: TextAlign.center, style: TextStyle(color: isDark ? const Color(0xFFCEC3BD) : const Color(0xFF71808A), fontSize: 12.5)),
      ]),
    );
  }

}

class _ModernServiceCard extends StatelessWidget {
  final ServiceItem service;
  final VoidCallback onOpen;
  const _ModernServiceCard({required this.service, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2A211E) : Colors.white;
    final textColor = isDark ? const Color(0xFFF8F2EB) : const Color(0xFF263746);
    final mutedColor = isDark ? const Color(0xFFCEC3BD) : const Color(0xFF71808A);
    final image = service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=800&q=85'
        : service.imageUrl;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: isDark ? const Color(0xFF51413B) : const Color(0xFFE6D8CE)),
            boxShadow: const [BoxShadow(color: Color(0x07000000), blurRadius: 12, offset: Offset(0, 5))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 125,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE8D4C4), child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF6F3E32), size: 34))),
                Positioned(left: 9, top: 9, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: const Color(0xE8173B55), borderRadius: BorderRadius.circular(15)), child: Text(service.category, style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)))),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(service.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w900, height: 1.15)),
                  const SizedBox(height: 6),
                  Row(children: [Icon(Icons.schedule_rounded, color: mutedColor, size: 14), const SizedBox(width: 4), Flexible(child: Text(service.duration.replaceFirst(' hours', ' hrs'), overflow: TextOverflow.ellipsis, style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : mutedColor), fontSize: 10, fontWeight: FontWeight.w700)))]),
                  const Spacer(),
                  Row(children: [
                    Text('₱${service.price.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFF6F4D), fontSize: 14, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Container(width: 30, height: 30, decoration: const BoxDecoration(color: Color(0xFF173B55), shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}


class FavoritesPage extends StatefulWidget {
  final ValueChanged<ServiceItem>? onBook;
  final VoidCallback? onBrowseServices;

  const FavoritesPage({
    super.key,
    this.onBook,
    this.onBrowseServices,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late Future<List<ServiceItem>> _future;
  Timer? _autoRefreshTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadFavorites();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentAutoRefresh());
  }

  Future<void> _silentAutoRefresh() async {
    try {
      final next = await _loadFavorites();
      if (!mounted) return;
      setState(() => _future = Future.value(next));
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<List<ServiceItem>> _loadFavorites() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    // First get the user's saved service IDs.
    final favoriteRows = await supabase
        .from('favorites')
        .select('service_id')
        .eq('customer_id', user.id)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(favoriteRows);

    if (rows.isEmpty) return [];

    final serviceIds = rows
        .map((row) => row['service_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    if (serviceIds.isEmpty) return [];

    // Load the actual services.
    final serviceRows = await supabase
        .from('services')
        .select()
        .inFilter('id', serviceIds)
        .eq('is_active', true);

    final servicesById = <String, ServiceItem>{};

    for (final row in List<Map<String, dynamic>>.from(serviceRows)) {
      final service = ServiceItem.fromMap(row);
      servicesById[service.id] = service;
    }

    // Keep the same order as the favorites table.
    return serviceIds
        .map((id) => servicesById[id])
        .whereType<ServiceItem>()
        .toList();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final next = _loadFavorites();
    setState(() => _future = next);
    await next;
  }

  Future<void> _removeFavorite(ServiceItem service) async {
    if (_busy) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _busy = true);

    try {
      await supabase
          .from('favorites')
          .delete()
          .eq('customer_id', user.id)
          .eq('service_id', service.id);

      if (!mounted) return;

      setState(() {
        _future = _loadFavorites();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${service.name} removed from favorites.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not remove favorite: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openService(ServiceItem service) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailsPage(service: service),
      ),
    );

    // Re-check favorites after returning from the service details page.
    if (mounted) {
      setState(() => _future = _loadFavorites());
    }
  }

  Widget _serviceCard(ServiceItem service) {
    final image = service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=900&q=85'
        : service.imageUrl;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _openService(service),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFE6D8CE),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 130,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFE8D4C4),
                        child: const Icon(
                          Icons.cleaning_services_rounded,
                          color: Color(0xFF6F3E32),
                          size: 38,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE8173B55),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          service.category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _removeFavorite(service),
                          child: const Padding(
                            padding: EdgeInsets.all(9),
                            child: Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF5D5D),
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF263746),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFF71808A),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            service.duration.replaceFirst(
                              'Approx. ',
                              '',
                            ),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF71808A),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Text(
                          '₱${service.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Color(0xFFFF6F4D),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 34,
                          child: FilledButton(
                            onPressed: () {
                              if (widget.onBook != null) {
                                widget.onBook!(service);
                              } else {
                                _openService(service);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF173B55),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Book now',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyFavorites() {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 36, 26, 36),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE6D8CE),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE6DA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFFFF6F4D),
              size: 38,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'No favorites yet',
            style: TextStyle(
              color: Color(0xFF26333D),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Save cleaning services you love by tapping the heart icon.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF71808A),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 19),
          FilledButton.icon(
            onPressed: () {
              if (widget.onBrowseServices != null) {
                widget.onBrowseServices!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: const Text('Browse services'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF8057),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FutureBuilder<List<ServiceItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF8057),
              ),
            );
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              color: const Color(0xFFFF8057),
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  Text(
                    'Could not load favorites.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final favorites = snapshot.data ?? [];

          return RefreshIndicator(
            color: const Color(0xFFFF8057),
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 35),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Favorites',
                            style: TextStyle(
                              color: Color(0xFF173B55),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Your saved cleaning services',
                            style: TextStyle(
                              color: Color(0xFF71808A),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE6DA),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFF5D5D),
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${favorites.length}',
                            style: const TextStyle(
                              color: Color(0xFF6F3E32),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (favorites.isEmpty)
                  _emptyFavorites()
                else ...[
                  Text(
                    '${favorites.length} saved service${favorites.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF26333D),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 11),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: favorites.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                      mainAxisExtent: 315,
                    ),
                    itemBuilder: (_, index) =>
                        _serviceCard(favorites[index]),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class AlertsPage extends StatefulWidget {
  final ValueChanged<int>? onUnreadChanged;
  const AlertsPage({super.key, this.onUnreadChanged});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  late Future<List<Map<String, dynamic>>> future;
  Timer? _autoRefreshTimer;
  bool _busy = false;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    future = _load();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentAutoRefresh());
  }

  Future<void> _silentAutoRefresh() async {
    try {
      final next = await _load();
      if (!mounted) return;
      setState(() => future = Future.value(next));
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final notifications = List<Map<String, dynamic>>.from(rows);
    final unread = notifications.where((n) => n['is_read'] != true).length;

    if (widget.onUnreadChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnreadChanged!(unread);
      });
    }

    return notifications;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final nextFuture = _load();
    // Keep the setState callback synchronous; assignment in an arrow
    // callback can return the Future and trigger a Flutter runtime error.
    setState(() {
      future = nextFuture;
    });
    await nextFuture;
  }

  Future<void> _markRead(String id) async {
    try {
      await markNotificationRead(id);
      await _refresh();
    } catch (e) {
      if (mounted) _message('Could not mark notification as read: $e');
    }
  }

  Future<void> _markAllRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Mark all as read?',
      message: 'All unread alerts will be marked as read.',
      confirmLabel: 'Mark as read',
      cancelLabel: 'Cancel',
    );

    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await markAllNotificationsRead(user.id);
      await _refresh();
      if (mounted) _message('All alerts marked as read.');
    } catch (e) {
      if (mounted) _message('Could not update alerts: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteOne(String id) async {
    try {
      await deleteNotification(id);
      await _refresh();
    } catch (e) {
      if (mounted) _message('Could not delete alert: $e');
    }
  }

  Future<void> _deleteAll() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Clear all alerts?',
      message: 'This will permanently remove your notification history.',
      confirmLabel: 'Clear all',
      cancelLabel: 'Cancel',
      destructive: true,
    );

    if (!confirmed) return;

    try {
      await deleteAllNotifications(user.id);
      await _refresh();
      if (mounted) _message('All alerts cleared.');
    } catch (e) {
      if (mounted) _message('Could not clear alerts: $e');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Text(text),
      ),
    );
  }

  IconData _iconForNotification(Map<String, dynamic> n) {
    final type = '${n['type'] ?? ''}'.toLowerCase();
    final title = '${n['title'] ?? ''}'.toLowerCase();

    if (type.contains('payment') || title.contains('payment')) {
      return Icons.payments_rounded;
    }
    if (type.contains('booking') || title.contains('booking')) {
      return Icons.calendar_month_rounded;
    }
    if (type.contains('clean') || title.contains('clean')) {
      return Icons.cleaning_services_rounded;
    }
    if (type.contains('complete') || title.contains('completed')) {
      return Icons.check_circle_rounded;
    }
    if (type.contains('cancel') || title.contains('cancel')) {
      return Icons.event_busy_rounded;
    }
    return Icons.notifications_rounded;
  }

  Color _accentForNotification(Map<String, dynamic> n) {
    final type = '${n['type'] ?? ''}'.toLowerCase();
    final title = '${n['title'] ?? ''}'.toLowerCase();

    if (type.contains('payment') || title.contains('payment')) {
      return const Color(0xFF3E7D45);
    }
    if (type.contains('booking') || title.contains('booking')) {
      return const Color(0xFF176B87);
    }
    if (type.contains('cancel') || title.contains('cancel')) {
      return const Color(0xFFD9534F);
    }
    if (type.contains('complete') || title.contains('completed')) {
      return const Color(0xFF8B5FBF);
    }
    return const Color(0xFFFF8057);
  }

  String kleenovaDateTime(dynamic raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final month = const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][local.month - 1];
  final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$month ${local.day}, ${local.year} • $hour:$minute $suffix';
}

String _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';

    final date = DateTime.tryParse(raw);
    if (date == null) return raw;

    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(local.year, local.month, local.day);

    final difference = today.difference(dateOnly).inDays;

    String time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: false,
    );

    if (difference == 0) return 'Today • $time';
    if (difference == 1) return 'Yesterday • $time';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return '${months[local.month - 1]} ${local.day}, ${local.year} • $time';
  }

  List<Map<String, dynamic>> _filtered(
    List<Map<String, dynamic>> rows,
  ) {
    if (_filter == 'Unread') {
      return rows.where((n) => n['is_read'] != true).toList();
    }
    if (_filter == 'Read') {
      return rows.where((n) => n['is_read'] == true).toList();
    }
    return rows;
  }

  Widget _summaryCard(
    BuildContext context,
    int unread,
    int total,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF173B55),
            Color(0xFF176B87),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F176B87),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stay up to date',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unread == 0
                      ? 'You are all caught up.'
                      : 'You have $unread unread alert${unread == 1 ? '' : 's'}.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;

    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF8057) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF8057)
                : const Color(0xFFE6D8CE),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : const Color(0xFF51443E),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _notificationCard(
    BuildContext context,
    Map<String, dynamic> n,
  ) {
    final isRead = n['is_read'] == true;
    final accent = _accentForNotification(n);
    final icon = _iconForNotification(n);

    return Dismissible(
      key: ValueKey('notification-${n['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await confirmKleenovaAction(
          context,
          title: 'Delete alert?',
          message: 'This alert will be removed from your notification history.',
          confirmLabel: 'Delete',
          cancelLabel: 'Cancel',
          destructive: true,
        );
        if (!confirmed) return false;

        await _deleteOne(n['id'].toString());
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 25,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isRead
              ? null
              : () => _markRead(n['id'].toString()),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isRead
                  ? Colors.white
                  : const Color(0xFFFFF7EF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isRead
                    ? const Color(0xFFE6D8CE)
                    : accent.withOpacity(.55),
                width: isRead ? 1 : 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.035),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${n['title'] ?? 'Notification'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF26333D),
                                fontSize: 14.5,
                                height: 1.15,
                                fontWeight: isRead
                                    ? FontWeight.w700
                                    : FontWeight.w900,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .4,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${n['message'] ?? ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5E625F),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _formatDate('${n['created_at'] ?? ''}'),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!isRead)
                            _alertAction(
                              icon: Icons.done_rounded,
                              color: const Color(0xFF3E7D45),
                              tooltip: 'Mark as read',
                              onPressed: () =>
                                  _markRead(n['id'].toString()),
                            ),
                          _alertAction(
                            icon: Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                            tooltip: 'Delete',
                            onPressed: () =>
                                _deleteOne(n['id'].toString()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alertAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 32,
      ),
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 19),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF8057),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load alerts.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rows = snapshot.data ?? [];
          final unread = rows.where((n) => n['is_read'] != true).length;
          final filtered = _filtered(rows);

          return RefreshIndicator(
            color: const Color(0xFFFF8057),
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alerts',
                            style: TextStyle(
                              color: Color(0xFF173B55),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Updates about your bookings and payments',
                            style: TextStyle(
                              color: Color(0xFF71808A),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Alert actions',
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Color(0xFF26333D),
                        size: 27,
                      ),
                      onSelected: (value) {
                        if (value == 'read') {
                          _markAllRead();
                        } else {
                          _deleteAll();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'read',
                          child: Row(
                            children: [
                              Icon(Icons.done_all_rounded, size: 20),
                              SizedBox(width: 10),
                              Text('Mark all as read'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_sweep_outlined,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text('Clear all alerts'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _summaryCard(context, unread, rows.length),
                const SizedBox(height: 18),

                Row(
                  children: [
                    _filterChip('All'),
                    const SizedBox(width: 8),
                    _filterChip('Unread'),
                    const SizedBox(width: 8),
                    _filterChip('Read'),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent alerts',
                        style: TextStyle(
                          color: Color(0xFF26333D),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${filtered.length}',
                      style: TextStyle(
                        color: Color(0xFFFF6F4D),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFFE6D8CE),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFE6DA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            color: Color(0xFFFF8057),
                            size: 31,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _filter == 'All'
                              ? 'No alerts yet'
                              : 'No $_filter alerts',
                          style: const TextStyle(
                            color: Color(0xFF26333D),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Booking, payment, and service updates will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF71808A),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...filtered.map(
                    (notification) => _notificationCard(
                      context,
                      notification,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CustomerHome extends StatefulWidget {
  final ValueChanged<ServiceItem> onBook;
  final ValueChanged<int>? onGoToTab;

  const CustomerHome({
    super.key,
    required this.onBook,
    this.onGoToTab,
  });

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  late Future<List<ServiceItem>> future;
  Timer? _autoRefreshTimer;
  String selectedCategory = 'All';

  static const serviceCategories = [
    'All',
    'Cleaning',
    'Maintenance',
    'Repair',
    'Home Care',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    future = loadServices();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final next = await loadServices();
      if (!mounted) return;
      setState(() => future = Future.value(next));
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<List<ServiceItem>> loadServices() async {
    final rows = await supabase
        .from('services')
        .select()
        .eq('is_active', true)
        .order('name');

    return (rows as List)
        .map((r) => ServiceItem.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  List<ServiceItem> _filter(List<ServiceItem> items) {
    if (selectedCategory == 'All') return items;

    return items
        .where(
          (s) => s.category.toLowerCase() == selectedCategory.toLowerCase(),
        )
        .toList();
  }

  void _openServices() => widget.onGoToTab?.call(1);
  void _openBookings() => widget.onGoToTab?.call(3);
  void _openAlerts() => widget.onGoToTab?.call(4);
  void _openProfile() => widget.onGoToTab?.call(5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pageBg =
        isDark ? const Color(0xFF171312) : const Color(0xFFF3F9FA);
    final surface =
        isDark ? const Color(0xFF2A211E) : Colors.white;
    final surfaceSoft =
        isDark ? const Color(0xFF332824) : const Color(0xFFE8F6F7);
    final primary =
        isDark ? const Color(0xFFFFB18F) : const Color(0xFF0F5C73);
    final accent = const Color(0xFFFF8057);
    final text =
        isDark ? const Color(0xFFF8F2EB) : const Color(0xFF243746);
    final muted =
        isDark ? const Color(0xFFCEC3BD) : const Color(0xFF71808A);
    final border =
        isDark ? const Color(0xFF51413B) : const Color(0xFFD9ECEF);

    final email = supabase.auth.currentUser?.email ?? '';
    final rawName = email.split('@').first.trim();
    final displayName = rawName.isEmpty ? 'there' : _titleCase(rawName);

    return Container(
      color: pageBg,
      child: RefreshIndicator(
        color: accent,
        onRefresh: () async => setState(() => future = loadServices()),
        child: FutureBuilder<List<ServiceItem>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 160),
                  _homeEmpty(
                    'Could not load services.\n${snapshot.error}',
                    Icons.cloud_off_rounded,
                  ),
                ],
              );
            }

            final allServices = snapshot.data ?? [];
            final services = _filter(allServices);
            final featured = services.isNotEmpty ? services.first : null;
            final popular = services.take(4).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
              children: [
                // ----------------------------------------------------------
                // TOP BAR
                // ----------------------------------------------------------
                Row(
                  children: [
                    const KleenovaLogoMark(size: 40),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: KleenovaBrand(
                        size: 21,
                        compact: true,
                      ),
                    ),
                    _roundHeaderButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: _openAlerts,
                    ),
                    const SizedBox(width: 8),
                    _roundHeaderButton(
                      icon: Icons.person_outline_rounded,
                      onTap: _openProfile,
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // ----------------------------------------------------------
                // WELCOME / HERO
                // ----------------------------------------------------------
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? const [
                              Color(0xFF3B2A25),
                              Color(0xFF263E4B),
                            ]
                          : const [
                              Color(0xFF0B4A5F),
                              Color(0xFF1B8AA0),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x20173B55),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -24,
                        top: -30,
                        child: Container(
                          width: 125,
                          height: 125,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(.07),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, ${displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFC857),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'A Cleaner Home\nIs a Happier You',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.7,
                            ),
                          ),
                          const SizedBox(height: 9),
                          const Text(
                            'Professional cleaning services\nat your fingertips.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _openServices,
                            child: const Text('Book Now  →'),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------------
                // SEARCH
                // ----------------------------------------------------------
                Material(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _openServices,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: muted,
                            size: 23,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              'What does your home need?',
                              style: TextStyle(
                                color: muted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: surfaceSoft,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: primary,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // ----------------------------------------------------------
                // QUICK ACTIONS
                // ----------------------------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: _colorTile(Icons.event_available_rounded,
                          'Book\nService', _openServices, const Color(0xFF2A9DB0)),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _colorTile(Icons.groups_rounded,
                          'My\nBookings', _openBookings, const Color(0xFF7FB069)),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _colorTile(Icons.credit_card_rounded,
                          'Payments', _openBookings, const Color(0xFF8C6FD0)),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ----------------------------------------------------------
                // CATEGORIES
                // ----------------------------------------------------------
                _sectionTitle(
                  'Browse by category',
                  _openServices,
                  text,
                  accent,
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 39,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: serviceCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (_, index) {
                      final category = serviceCategories[index];
                      final selected = selectedCategory == category;

                      return ChoiceChip(
                        label: Text(category),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => selectedCategory = category);
                        },
                        selectedColor: accent,
                        backgroundColor: surface,
                        side: BorderSide(
                          color: selected ? accent : border,
                        ),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 25),

                // ----------------------------------------------------------
                // FEATURED SERVICE
                // ----------------------------------------------------------
                _sectionTitle(
                  'Featured for you',
                  _openServices,
                  text,
                  accent,
                ),
                const SizedBox(height: 10),
                if (featured == null)
                  _homeEmpty(
                    selectedCategory == 'All'
                        ? 'No services available yet.'
                        : 'No services in $selectedCategory yet.',
                    Icons.cleaning_services_outlined,
                  )
                else
                  _featuredService(
                    featured,
                    text,
                    muted,
                    accent,
                  ),

                if (popular.length > 1) ...[
                  const SizedBox(height: 25),

                  // --------------------------------------------------------
                  // POPULAR SERVICES
                  // --------------------------------------------------------
                  _sectionTitle(
                    'Recommended Services',
                    _openServices,
                    text,
                    accent,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 218,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: popular.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 11),
                      itemBuilder: (_, index) {
                        return SizedBox(
                          width: 165,
                          child: _homeServiceCard(
                            popular[index],
                            text,
                            muted,
                            accent,
                            surface,
                            border,
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF263E4B) : const Color(0xFFDDF3F6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trusted Cleaners. Safer Homes.',
                              style: TextStyle(
                                color: text,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Background checked • Verified • Rated by real customers',
                              style: TextStyle(color: muted, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  Widget _roundHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2A211E) : Colors.white;
    final foreground =
        isDark ? const Color(0xFFF8F2EB) : const Color(0xFF263746);

    return Material(
      color: surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? const Color(0xFF51413B)
                  : const Color(0xFFE6D8CE),
            ),
          ),
          child: Icon(
            icon,
            color: foreground,
            size: 21,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    VoidCallback? action,
    Color textColor,
    Color accent,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -.25,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
            ),
            child: Text(
              'View All →',
              style: TextStyle(
                color: const Color(0xFF0F5C73),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }

  Widget _colorTile(
    IconData icon,
    String label,
    VoidCallback onTap,
    Color color,
  ) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(.28),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 27),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    VoidCallback onTap,
    Color primary,
    Color accent,
    Color surface,
    Color border,
    Color textColor,
  ) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, accent],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featuredService(
    ServiceItem service,
    Color textColor,
    Color muted,
    Color accent,
  ) {
    final image = service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1200&q=85'
        : service.imageUrl;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        onTap: () => widget.onBook(service),
        borderRadius: BorderRadius.circular(25),
        child: Container(
          height: 214,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A173B55),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: const Color(0xFFDCCEC3),
                    child: const Icon(
                      Icons.cleaning_services_rounded,
                      size: 40,
                      color: Color(0xFF6F3E32),
                    ),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x05000000),
                      Color(0xE6173B55),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 15,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FEATURED',
                    style: TextStyle(
                      color: Color(0xFF176B87),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 15,
                bottom: 15,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                color: Color(0xFFFFC857),
                                size: 15,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  service.duration.replaceFirst(
                                    ' hours',
                                    ' hrs',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '₱${service.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Book',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeServiceCard(
    ServiceItem service,
    Color textColor,
    Color muted,
    Color accent,
    Color surface,
    Color border,
  ) {
    final image = service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=800&q=85'
        : service.imageUrl;

    return KleenovaPress(
      onTap: () => widget.onBook(service),
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 105,
                width: double.infinity,
                child: Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: const Color(0xFFE8D4C4),
                      child: const Icon(
                        Icons.cleaning_services_rounded,
                        color: Color(0xFF6F3E32),
                        size: 32,
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          height: 1.15,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: muted,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              service.duration.replaceFirst(
                                ' hours',
                                ' hrs',
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: muted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '₱${service.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F5C73),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeEmpty(String message, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 190,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? const Color(0xFF51413B)
              : const Color(0xFFE6D8CE),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isDark
                ? const Color(0xFFFFB59A)
                : const Color(0xFF6F3E32),
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? const Color(0xFFCEC3BD)
                  : const Color(0xFF71808A),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _KleenovaMiniLogo extends StatelessWidget {
  @override Widget build(BuildContext context) => _KleenovaLogoMark(size: 42);
}

class _KleenovaLogoMark extends StatelessWidget {
  final double size;
  const _KleenovaLogoMark({required this.size});
  @override Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _KleenovaLogoPainter(
        primary: const Color(0xFF176B87),
        accent: const Color(0xFFFF8057),
      ));
}

IconData _serviceCategoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'maintenance': return Icons.handyman_outlined;
    case 'repair': return Icons.build_outlined;
    case 'home care': return Icons.home_outlined;
    case 'other': return Icons.grid_view_rounded;
    default: return Icons.cleaning_services_outlined;
  }
}

Widget _dashboardAction(BuildContext context, IconData icon, String title, VoidCallback onTap) => KleenovaPress(
  onTap: onTap,
  borderRadius: BorderRadius.circular(19),
  child: Container(
    height: 108,
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFE7DCD3)),
      boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 5))],
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF173B55), Color(0xFFD96B45)], begin: Alignment.topLeft, end: Alignment.bottomRight), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
      const SizedBox(height: 9),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF26333D))),
    ]),
  ),
);

Widget _categoryChip(BuildContext context, String label, bool selected, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.only(right: 8),
  child: Material(
    color: selected ? const Color(0xFF0F766E) : Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? const Color(0xFF0F766E) : const Color(0xFFE7D7C6)),
          gradient: selected ? const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFFFF8A5B)]) : null,
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ),
  ),
);

Widget _emptyService(BuildContext context, String text, IconData icon) => Container(margin: const EdgeInsets.only(top:8), padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).dividerColor)), child: Column(children:[Icon(icon,color:Theme.of(context).colorScheme.secondary,size:34),const SizedBox(height:10),Text(text,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.onSurface,height:1.5))]));


class ServiceDetailsPage extends StatefulWidget {
  final ServiceItem service;
  const ServiceDetailsPage({super.key, required this.service});

  @override
  State<ServiceDetailsPage> createState() => _ServiceDetailsPageState();
}

class _ServiceDetailsPageState extends State<ServiceDetailsPage> {
  late Future<Map<String, dynamic>> _reviewsFuture;
  bool _submittingReview = false;
  bool _isFavorite = false;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _reviewsFuture = _loadReviews();
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final row = await supabase
          .from('favorites')
          .select('id')
          .eq('customer_id', user.id)
          .eq('service_id', widget.service.id)
          .maybeSingle();
      if (mounted) setState(() => _isFavorite = row != null);
    } catch (_) {
      // Favorites are optional until the favorites table/RLS is installed.
    }
  }

  Future<void> _toggleFavorite() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save favorites.')),
      );
      return;
    }
    if (_favoriteBusy) return;

    final previous = _isFavorite;
    setState(() {
      _favoriteBusy = true;
      _isFavorite = !previous;
    });

    try {
      if (previous) {
        await supabase
            .from('favorites')
            .delete()
            .eq('customer_id', user.id)
            .eq('service_id', widget.service.id);
      } else {
        await supabase.from('favorites').insert({
          'customer_id': user.id,
          'service_id': widget.service.id,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            previous
                ? 'Removed from favorites.'
                : 'Added to favorites.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isFavorite = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update favorite: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<Map<String, dynamic>> _loadReviews() async {
    final currentUserId = supabase.auth.currentUser?.id;
    final bookingRows = await supabase.from('bookings').select('id').eq('service_id', widget.service.id);
    final bookingIds = List<Map<String, dynamic>>.from(bookingRows).map((b) => b['id'].toString()).toList();
    final reviewRows = <Map<String, dynamic>>[];

    final directRows = await supabase
        .from('reviews')
        .select('id, booking_id, service_id, service_name, customer_id, rating, comment, created_at, is_read, read_at')
        .eq('service_id', widget.service.id)
        .order('created_at', ascending: false);
    reviewRows.addAll(List<Map<String, dynamic>>.from(directRows));
    if (bookingIds.isNotEmpty) {
      final bookedRows = await supabase
          .from('reviews')
          .select('id, booking_id, service_id, service_name, customer_id, rating, comment, created_at, is_read, read_at')
          .inFilter('booking_id', bookingIds)
          .order('created_at', ascending: false);
      final knownIds = reviewRows.map((r) => r['id'].toString()).toSet();
      reviewRows.addAll(List<Map<String, dynamic>>.from(bookedRows).where((r) => !knownIds.contains(r['id'].toString())));
    }
    reviewRows.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    final reviews = reviewRows;

    final customerIds = reviews
        .map((r) => r['customer_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (customerIds.isNotEmpty) {
      try {
        final profileRows = await supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', customerIds);
        final names = <String, String>{};
        for (final profile in List<Map<String, dynamic>>.from(profileRows)) {
          names[profile['id'].toString()] =
              (profile['full_name'] ?? 'KLEENOVA customer').toString();
        }
        for (final review in reviews) {
          review['reviewer_name'] = names[review['customer_id']?.toString()] ?? 'KLEENOVA customer';
        }
      } catch (_) {
        for (final review in reviews) {
          review['reviewer_name'] = 'KLEENOVA customer';
        }
      }
    }
    final alreadyReviewed = currentUserId != null && reviews.any((r) => r['customer_id']?.toString() == currentUserId);
    return {'reviews': reviews, 'canReview': currentUserId != null && !alreadyReviewed};
  }

  void _refreshReviews() {
    final nextReviews = _loadReviews();
    if (!mounted) return;
    setState(() {
      _reviewsFuture = nextReviews;
    });
  }

  Future<void> _openReviewForm({required bool focusComment}) async {
    final data = await _reviewsFuture;
    final canReview = data['canReview'] == true;
    if (!mounted) return;
    if (supabase.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to leave a review.')),
      );
      return;
    }
    if (!canReview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already reviewed this service.')),
      );
      return;
    }

    final commentController = TextEditingController();
    int? rating = focusComment ? null : 5;
    final formKey = GlobalKey<FormState>();
    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: !_submittingReview,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedRating = rating ?? 0;
          final ratingLabel = switch (selectedRating) {
            1 => 'Poor',
            2 => 'Fair',
            3 => 'Good',
            4 => 'Very good',
            5 => 'Excellent',
            _ => 'Tap a star to rate',
          };

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : const Color(0xFFFFF8F1),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE7D6C9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  focusComment ? 'Write a comment' : 'Rate this service',
                                  style: TextStyle(
                                    color: Color(0xFF2B211E),
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.6,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  focusComment
                                      ? 'Tell others about your experience.'
                                      : 'How was your cleaning experience?',
                                  style: const TextStyle(
                                    color: Color(0xFF756861),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: const Color(0xFFFFE4D8),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.pop(dialogContext, false),
                              child: const SizedBox(
                                width: 38,
                                height: 38,
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFF6F3E32),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (!focusComment) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Your rating',
                          style: TextStyle(
                            color: Color(0xFF3C302B),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE8D8CC)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(5, (index) {
                                  final active = index < selectedRating;
                                  return IconButton(
                                    tooltip: '${index + 1} star${index == 0 ? '' : 's'}',
                                    splashRadius: 25,
                                    onPressed: () => setDialogState(() => rating = index + 1),
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 150),
                                      child: Icon(
                                        active
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        key: ValueKey('$index-$active'),
                                        color: active
                                            ? const Color(0xFFFF8A00)
                                            : const Color(0xFFD8C9BF),
                                        size: 38,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                child: Text(
                                  ratingLabel,
                                  key: ValueKey(ratingLabel),
                                  style: TextStyle(
                                    color: selectedRating == 0
                                        ? const Color(0xFF8C7B72)
                                        : const Color(0xFF6F3E32),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),
                      const Text(
                        'Comment',
                        style: TextStyle(
                          color: Color(0xFF3C302B),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: commentController,
                        minLines: 5,
                        maxLines: 6,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Share your experience... (optional)',
                          hintStyle: TextStyle(
                            color: Color(0xFF9A8980),
                            fontSize: 13.5,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          contentPadding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: const BorderSide(color: Color(0xFFE4D3C8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: const BorderSide(color: Color(0xFFE4D3C8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF8057),
                              width: 1.7,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                        validator: (value) =>
                            (value?.length ?? 0) > 1000
                                ? 'Maximum 1000 characters.'
                                : null,
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: commentController,
                          builder: (_, value, __) => Text(
                            '${value.text.length}/1000',
                            style: const TextStyle(
                              color: Color(0xFF756861),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                foregroundColor: const Color(0xFF6F3E32),
                                side: const BorderSide(color: Color(0xFFDCC8BA)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (formKey.currentState?.validate() ?? false) {
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                              icon: const Icon(Icons.send_rounded, size: 17),
                              label: const Text('Submit review'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                backgroundColor: const Color(0xFF6F3E32),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (shouldSubmit != true || !mounted) {
      commentController.dispose();
      return;
    }

    final confirmReview = await confirmKleenovaAction(
      context,
      title: 'Submit review?',
      message: 'Are you sure you want to submit this rating and comment?',
      confirmLabel: 'Yes, submit',
      cancelLabel: 'No',
    );
    if (!confirmReview) {
      commentController.dispose();
      return;
    }

    setState(() => _submittingReview = true);
    try {
      await supabase.from('reviews').insert({
        'booking_id': null,
        'service_id': widget.service.id,
        'service_name': widget.service.name,
        'customer_id': supabase.auth.currentUser!.id,
        'rating': rating,
        'comment': commentController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you! Your review was submitted.')));
      _refreshReviews();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit review: ${e.message}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit review: $e')));
    } finally {
      commentController.dispose();
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  void _showAllReviews(List<Map<String, dynamic>> reviews) {
    final currentUserId = supabase.auth.currentUser?.id;
    final pageContext = context;
    final visibleReviews = List<Map<String, dynamic>>.from(reviews);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(children: [
                  const Expanded(child: Text('Customer reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
                ]),
              ),
              const Divider(height: 1, color: beige),
              Expanded(
                child: visibleReviews.isEmpty
                    ? const Center(child: Text('No reviews yet for this service.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: visibleReviews.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (tileContext, index) {
                          final review = visibleReviews[index];
                          final isOwnReview = currentUserId != null &&
                              review['customer_id']?.toString() == currentUserId;
                          return _reviewTile(
                            review,
                            showDelete: isOwnReview,
                            onDelete: isOwnReview
                                ? () async {
                                    final confirmed = await showDialog<bool>(
                                      context: sheetContext,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Delete your review?'),
                                        content: const Text('This review will be permanently deleted.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dialogContext, false),
                                            child: const Text('Keep review'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(dialogContext, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true) return;
                                    try {
                                      await supabase
                                          .from('reviews')
                                          .delete()
                                          .eq('id', review['id'].toString())
                                          .eq('customer_id', currentUserId);
                                      if (!sheetContext.mounted) return;
                                      setSheetState(() {
                                        visibleReviews.removeWhere((item) =>
                                            item['id'].toString() == review['id'].toString());
                                      });
                                      _refreshReviews();
                                      ScaffoldMessenger.of(pageContext).showSnackBar(
                                        const SnackBar(content: Text('Your review was deleted.')),
                                      );
                                    } on PostgrestException catch (e) {
                                      if (pageContext.mounted) {
                                        ScaffoldMessenger.of(pageContext).showSnackBar(
                                          SnackBar(content: Text('Could not delete review: ${e.message}')),
                                        );
                                      }
                                    } catch (e) {
                                      if (pageContext.mounted) {
                                        ScaffoldMessenger.of(pageContext).showSnackBar(
                                          SnackBar(content: Text('Could not delete review: $e')),
                                        );
                                      }
                                    }
                                  }
                                : null,
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _reviewTile(
    Map<String, dynamic> review, {
    bool showDelete = false,
    VoidCallback? onDelete,
  }) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = (review['comment'] ?? '').toString().trim();
    final name = (review['reviewer_name'] ?? 'KLEENOVA customer').toString();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface))),
          ...List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: 16,
            color: Colors.amber.shade800,
          )),
          if (showDelete) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Delete your review',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: colors.error,
            ),
          ],
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(comment, style: TextStyle(height: 1.4, color: colors.onSurface)),
        ] else ...[
          const SizedBox(height: 8),
          Text('Rating only', style: TextStyle(fontStyle: FontStyle.italic, color: colors.onSurfaceVariant)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?auto=format&fit=crop&w=1200&q=85'
        : widget.service.imageUrl;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: const Color(0xFF173B55),
        title: const Text('Service details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: _favoriteBusy ? null : _toggleFavorite,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                _isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(_isFavorite),
                color: _isFavorite ? const Color(0xFFFF5D5D) : const Color(0xFF173B55),
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 125),
            children: [
              Hero(
                tag: 'service-${widget.service.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Stack(
                    children: [
                      Image.network(
                        image,
                        height: 235,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 235, color: const Color(0xFFE8D4C4), child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF6F3E32), size: 54)),
                      ),
                      Positioned(left: 14, top: 14, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xE8173B55), borderRadius: BorderRadius.circular(20)), child: Text(widget.service.category, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(widget.service.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5)),
              const SizedBox(height: 7),
              Row(children: [const Icon(Icons.star_rounded, color: Color(0xFFFFB020), size: 19), const SizedBox(width: 4), const Text('Customer ratings & reviews', style: TextStyle(color: Color(0xFF5C6A73), fontSize: 12.5, fontWeight: FontWeight.w700))]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _modernStat(Icons.payments_outlined, 'Starting price', '₱${widget.service.price.toStringAsFixed(2)}')),
                const SizedBox(width: 10),
                Expanded(child: _modernStat(Icons.schedule_rounded, 'Duration', widget.service.duration.replaceFirst(' hours', ' hrs'))),
              ]),
              const SizedBox(height: 22),
              _detailsSectionTitle('About this service'),
              const SizedBox(height: 7),
              Text(widget.service.description.isEmpty ? 'Routine home tidying and room refresh performed with care by KLEENOVA service professionals.' : widget.service.description, style: const TextStyle(color: Color(0xFF5D686F), fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 22),
              _detailsSectionTitle("What's included"),
              const SizedBox(height: 10),
              _includedItem('Dusting and surface wipe-down'),
              _includedItem('Bathroom and kitchen cleaning'),
              _includedItem('Floor sweeping and mopping'),
              _includedItem('Trash removal and tidying'),
              const SizedBox(height: 22),
              FutureBuilder<Map<String, dynamic>>(
                future: _reviewsFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _reviewContainer(const [Text('Reviews could not be loaded.', style: TextStyle(color: Color(0xFF5D686F))), SizedBox(height: 8)]);
                  }
                  if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF8057))));
                  final reviews = List<Map<String, dynamic>>.from(snapshot.data!['reviews'] as List);
                  final ratedReviews = reviews.where((r) => r['rating'] is num).toList();
                  final avg = ratedReviews.isEmpty ? 0.0 : ratedReviews.map((r) => (r['rating'] as num).toDouble()).reduce((a, b) => a + b) / ratedReviews.length;
                  return _reviewContainer([
                    Row(children: [
                      const Text('Reviews', style: TextStyle(color: Color(0xFF26333D), fontSize: 18, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB020), size: 20),
                      const SizedBox(width: 4),
                      Text(reviews.isEmpty ? 'New' : '${avg.toStringAsFixed(1)} • ${reviews.length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    if (reviews.isEmpty)
                      const Text('Be the first to share your experience with this service.', style: TextStyle(color: Color(0xFF71808A), fontSize: 12.5))
                    else
                      ...reviews.take(2).map(_reviewTile),
                    const SizedBox(height: 13),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(onPressed: _submittingReview ? null : () => _openReviewForm(focusComment: false), icon: const Icon(Icons.star_border_rounded, size: 17), label: const Text('Rate'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: _submittingReview ? null : () => _openReviewForm(focusComment: true), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17), label: const Text('Comment'))),
                    ]),
                    Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _showAllReviews(reviews), icon: const Icon(Icons.reviews_outlined, size: 17), label: const Text('View all reviews'))),
                  ]);
                },
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6D8CE))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Booking summary', style: TextStyle(color: Color(0xFF26333D), fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _summaryLine('Service price', '₱${widget.service.price.toStringAsFixed(2)}'),
                  _summaryLine('Booking fee', '₱0.00'),
                  _summaryLine('Currency', 'PHP'),
                ]),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 18, offset: Offset(0, -5))]),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Text('Starting price', style: TextStyle(color: Color(0xFF71808A), fontSize: 10.5, fontWeight: FontWeight.w600)), Text('₱${widget.service.price.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 19, fontWeight: FontWeight.w900))])),
                  SizedBox(width: 160, height: 52, child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(service: widget.service))), icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: const Text('Book now'))),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernStat(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE6D8CE))),
    child: Row(children: [
      Container(width: 35, height: 35, decoration: BoxDecoration(color: const Color(0xFFFFE6DD), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: const Color(0xFFFF6F4D), size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 9.5, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12.5, fontWeight: FontWeight.w900))])),
    ]),
  );

  Widget _detailsSectionTitle(String title) => Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900));

  Widget _includedItem(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(children: [
      Container(width: 25, height: 25, decoration: const BoxDecoration(color: Color(0xFFE5F7EF), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Color(0xFF0F766E), size: 16)),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _reviewContainer(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6D8CE))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _summaryLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))), Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 12))]),
  );
}

Widget _detailStat(String label, String value) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: BoxDecoration(color: const Color(0xFFE5F0F6), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, color: ink)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ink))]));

Widget _priceLine(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(label, style: const TextStyle())), Text(value, style: const TextStyle(fontWeight: FontWeight.w500))]));

class BookingPage extends StatefulWidget {
  final ServiceItem service;

  const BookingPage({super.key, required this.service});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final address = TextEditingController();
  final province = TextEditingController();
  final barangay = TextEditingController();
  final city = TextEditingController();
  final notes = TextEditingController();

  DateTime date = DateTime.now().add(const Duration(days: 1));
  String time = '09:00 AM';
  bool busy = false;
  bool customTimeSelected = false;
  String paymentMethod = 'paymongo_qrph';
  int _bookingStep = 0;

  final voucherController = TextEditingController();
  String? appliedVoucher;
  double discountAmount = 0;

  static const Map<String, Map<String, dynamic>> vouchers = {
    'WELCOME10': {
      'type': 'percent',
      'value': 10.0,
      'minimum': 500.0,
      'maximumDiscount': 100.0,
      'label': '10% OFF up to ₱100',
    },
    'CLEAN50': {
      'type': 'fixed',
      'value': 50.0,
      'minimum': 500.0,
      'label': '₱50 OFF',
    },
    'SAVE100': {
      'type': 'fixed',
      'value': 100.0,
      'minimum': 1000.0,
      'label': '₱100 OFF',
    },
  };

  double get finalTotal => (widget.service.price - discountAmount).clamp(0, double.infinity).toDouble();

  void applyVoucher([String? code]) {
    final entered = (code ?? voucherController.text).trim().toUpperCase();
    final voucher = vouchers[entered];
    if (voucher == null) {
      setState(() {
        appliedVoucher = null;
        discountAmount = 0;
      });
      msg('Voucher not found. Try WELCOME10, CLEAN50, or SAVE100.');
      return;
    }

    final price = widget.service.price.toDouble();
    final minimum = (voucher['minimum'] as num).toDouble();
    if (price < minimum) {
      msg('$entered requires a minimum service price of ₱${minimum.toStringAsFixed(0)}.');
      return;
    }

    double discount;
    if (voucher['type'] == 'percent') {
      discount = price * ((voucher['value'] as num).toDouble() / 100);
      final max = (voucher['maximumDiscount'] as num?)?.toDouble();
      if (max != null) discount = discount.clamp(0, max).toDouble();
    } else {
      discount = (voucher['value'] as num).toDouble();
    }

    discount = discount.clamp(0, price).toDouble();
    setState(() {
      voucherController.text = entered;
      appliedVoucher = entered;
      discountAmount = discount;
    });
    msg('$entered applied. You saved ₱${discount.toStringAsFixed(2)}.');
  }

  void removeVoucher() {
    setState(() {
      voucherController.clear();
      appliedVoucher = null;
      discountAmount = 0;
    });
    msg('Voucher removed.');
  }

  Widget _paymentOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = paymentMethod == value;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: busy ? null : () => setState(() => paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? coffee.withOpacity(.08) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? coffee : Theme.of(context).dividerColor,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? coffee : beige,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: selected ? Colors.white : coffee),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: paymentMethod,
              activeColor: coffee,
              onChanged: busy ? null : (v) => setState(() => paymentMethod = v!),
            ),
          ],
        ),
      ),
    );
  }

  final slots = ['09:00 AM', '10:00 AM', '11:00 AM', '01:00 PM', '02:00 PM', '03:00 PM'];

  List<Map<String, String>> _provinces = [];
  List<Map<String, String>> _cities = [];
  List<Map<String, String>> _barangays = [];
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  bool _loadingProvinces = false;
  bool _loadingCities = false;
  bool _loadingBarangays = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  @override
  void dispose() {
    address.dispose();
    province.dispose();
    barangay.dispose();
    city.dispose();
    notes.dispose();
    voucherController.dispose();
    super.dispose();
  }

  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  List<dynamic> _itemsFromJson(dynamic json) {
    if (json is List) return json;
    if (json is Map) {
      for (final key in ['data', 'results', 'items', 'provinces', 'cities_municipalities', 'barangays']) {
        final value = json[key];
        if (value is List) return value;
      }
    }
    throw const FormatException('Unexpected location data format.');
  }

  Map<String, String>? _locationFromItem(dynamic item) {
    if (item is String) {
      final name = item.trim();
      return name.isEmpty ? null : {'name': name, 'code': name};
    }
    if (item is Map) {
      final name = (item['name'] ?? item['displayName'] ?? item['display_name'] ?? '').toString().trim();
      final code = (item['code'] ?? item['psgc_code'] ?? item['psgcCode'] ?? item['id'] ?? '').toString().trim();
      if (name.isNotEmpty && code.isNotEmpty) return {'name': name, 'code': code};
    }
    return null;
  }

  Future<List<Map<String, String>>> _fetchLocationList(String path) async {
    final response = await http
        .get(Uri.parse('https://psgc.cloud/api/v2$path'))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Location service returned ${response.statusCode}.');
    }

    final parsed = jsonDecode(response.body);
    final values = _itemsFromJson(parsed)
        .map(_locationFromItem)
        .whereType<Map<String, String>>()
        .fold<Map<String, Map<String, String>>>({}, (map, item) {
          map[item['code']!] = item;
          return map;
        })
        .values
        .toList()
      ..sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));

    return values;
  }

  Future<void> _loadProvinces() async {
    if (_provinces.isNotEmpty || _loadingProvinces) return;

    if (!mounted) return;
    setState(() => _loadingProvinces = true);
    try {
      final allProvinces = await _fetchLocationList('/provinces');

      // KLEENOVA currently serves Bohol only. Keep the province selector
      // restricted to Bohol and preselect it for a simpler booking flow.
      final bohol = allProvinces.where(
        (item) => (item['name'] ?? '').trim().toLowerCase() == 'bohol',
      ).toList();

      if (bohol.isEmpty) {
        throw Exception('Bohol was not returned by the location service.');
      }

      if (!mounted) return;
      setState(() {
        _provinces = bohol;
        _selectedProvinceCode = bohol.first['code'];
        province.text = bohol.first['name']!;
        city.clear();
        barangay.clear();
        _selectedCityCode = null;
        _cities = [];
        _barangays = [];
        _locationError = null;
      });

      // Load only municipalities/cities that belong to Bohol.
      await _loadCities();
    } catch (_) {
      if (mounted) {
        setState(() => _locationError = 'Could not load Bohol locations. Check your internet connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingProvinces = false);
    }
  }

  Future<void> _loadCities() async {
    if (province.text.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _loadingCities = true;
      _locationError = null;
    });

    try {
      final path = '/provinces/${Uri.encodeComponent(_selectedProvinceCode ?? province.text)}/cities-municipalities';
      final values = await _fetchLocationList(path);
      if (mounted) setState(() => _cities = values);
    } catch (_) {
      if (mounted) {
        setState(() => _locationError = 'Could not load cities/municipalities for ${province.text}. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _loadBarangays() async {
    if (province.text.isEmpty || city.text.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _loadingBarangays = true;
      _locationError = null;
    });

    try {
      final path = '/cities-municipalities/${Uri.encodeComponent(_selectedCityCode ?? city.text)}/barangays';
      final values = await _fetchLocationList(path);
      if (mounted) setState(() => _barangays = values);
    } catch (_) {
      if (mounted) {
        setState(() => _locationError = 'Could not load barangays for ${city.text}. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingBarangays = false);
    }
  }

  String _bookingDisplayKey(Map<String, dynamic> row) => [
        row['service_id'] ?? row['service_name'] ?? '',
        row['booking_date'] ?? '',
        row['booking_time'] ?? '',
        row['address'] ?? '',
        row['municipality'] ?? '',
      ].map((v) => v.toString().trim().toLowerCase()).join('|');

  Future<void> book() async {
    if (address.text.trim().isEmpty || province.text.trim().isEmpty || barangay.text.trim().isEmpty || city.text.trim().isEmpty) {
      msg('Please complete your address, province, city, and barangay.');
      return;
    }

    final isCash = paymentMethod == 'pay_after_service';
    final amountText = '₱${finalTotal.toStringAsFixed(2)}';

    final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(.46),
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(.9)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x42000000),
                      blurRadius: 34,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: isCash ? const Color(0xFFFFE5DA) : const Color(0xFFE2F5F5),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            isCash ? Icons.payments_outlined : Icons.qr_code_2_rounded,
                            color: isCash ? coffee : deepSage,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCash ? 'Confirm booking' : 'Confirm QRPH payment',
                                style: TextStyle(
                                  color: Color(0xFF243746),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCash ? 'Cash on delivery' : 'Secure QRPH checkout',
                                style: const TextStyle(
                                  color: Color(0xFF7A6D66),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF806F67), size: 21),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE9D9CF)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCash ? Icons.receipt_long_outlined : Icons.lock_outline_rounded,
                              color: coffee,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Expanded(
                            child: Text(
                              'Amount due',
                              style: TextStyle(
                                color: Color(0xFF6E6059),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            amountText,
                            style: TextStyle(
                              color: Color(0xFF243746),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      isCash
                          ? 'Your booking will be created with a pending payment. Please prepare $amountText in cash and pay the cleaner when the service is completed.'
                          : 'Your booking will be created with a pending payment. Continue to the secure QRPH checkout to complete your payment.',
                      style: const TextStyle(
                        color: Color(0xFF5F514B),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (!isCash) ...[
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7F6),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.verified_user_outlined, color: deepSage, size: 17),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You’ll be redirected to the secure payment page. Return to KLEENOVA after paying.',
                                style: TextStyle(
                                  color: Color(0xFF42656A),
                                  fontSize: 11.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: coffee,
                                side: const BorderSide(color: Color(0xFFE2CFC4)),
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              style: FilledButton.styleFrom(
                                backgroundColor: coffee,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: Icon(isCash ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 19),
                              label: Text(
                                isCash ? 'Confirm booking' : 'Continue to pay',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (!proceed) return;
    if (!mounted) return;
    setState(() => busy = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        msg('Please sign in to complete your booking.');
        return;
      }

      final existingRows = await supabase
          .from('bookings')
          .select('id,status,payment_status,service_id,service_name,booking_date,booking_time,address,municipality')
          .eq('customer_id', user.id)
          .eq('booking_date', date.toIso8601String().substring(0, 10))
          .eq('booking_time', time);

      final requestedKey = _bookingDisplayKey({
        'service_id': widget.service.id,
        'service_name': widget.service.name,
        'booking_date': date.toIso8601String().substring(0, 10),
        'booking_time': time,
        'address': address.text.trim(),
        'municipality': city.text.trim(),
      });

      for (final existing in List<Map<String, dynamic>>.from(existingRows)) {
        final existingStatus = (existing['status'] ?? '').toString().toLowerCase();
        if (existingStatus == 'cancelled' || existingStatus == 'canceled' || existingStatus == 'completed') continue;
        if (_bookingDisplayKey(existing) == requestedKey) {
          final existingPayment = (existing['payment_status'] ?? 'pending').toString().toLowerCase();
          msg(existingPayment == 'paid'
              ? 'You already have a paid booking for this service, date, time, and address.'
              : 'You already have a booking for this service, date, time, and address. Check My Bookings instead of creating another one.');
          return;
        }
      }

      final row = await supabase.from('bookings').insert({
        'customer_id': user.id,
        'service_id': widget.service.id,
        'service_name': widget.service.name,
        'service_price': finalTotal,
        'booking_date': date.toIso8601String().substring(0, 10),
        'booking_time': time,
        'address': address.text.trim(),
        'province': province.text.trim(),
        'barangay': barangay.text.trim(),
        'municipality': city.text.trim(),
        'instructions': notes.text.trim(),
        'status': 'pending',
        'payment_method': paymentMethod,
        'payment_status': 'pending',
      }).select().single();

      if (!mounted) return;

      // Pay After Service does not create a PayMongo checkout.
      // The booking remains pending until payment is collected and confirmed by the business.
      if (paymentMethod == 'pay_after_service') {
        await createKleenovaNotification(
          userId: user.id,
          title: 'Booking confirmed!',
          message: 'Your ${widget.service.name} booking is confirmed. Total: ₱${finalTotal.toStringAsFixed(2)}${appliedVoucher != null ? ' after $appliedVoucher discount.' : '.'} You can follow updates in My Bookings. Payment is due after the service is completed.',
          type: 'booking',
          bookingId: row['id'].toString(),
        );
        msg('Booking confirmed! You can follow its progress in My Bookings. Payment will be collected after the service.');
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BookingsPage()));
        return;
      }

      final paid = await startPayment(row['id'].toString(), finalTotal);
      if (!mounted) return;

      if (paid) {
        await createKleenovaNotification(
          userId: user.id,
          title: 'You’re all booked!',
          message: 'Your ${widget.service.name} booking is confirmed and paid at ₱${finalTotal.toStringAsFixed(2)}${appliedVoucher != null ? ' using $appliedVoucher.' : '.'} You can track its progress in My Bookings.',
          type: 'payment',
          bookingId: row['id'].toString(),
        );
        msg('Payment confirmed! Your booking is all set. You can track it in My Bookings.');
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BookingsPage()));
      } else {
        await createKleenovaNotification(
          userId: user.id,
          title: 'Booking received!',
          message: 'Your ${widget.service.name} booking was saved at ₱${finalTotal.toStringAsFixed(2)}. We’ll let you know when there’s an update. Payment is still pending.',
          type: 'booking',
          bookingId: row['id'].toString(),
        );
        msg('Your booking is saved! You can check its status in My Bookings. Payment is still pending.');
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BookingsPage()));
      }
    } catch (e) {
      msg('Booking failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _checkPayment(String bookingId) async {
    try {
      final row = await supabase
          .from('bookings')
          .select('payment_status')
          .eq('id', bookingId)
          .maybeSingle();
      final status = (row?['payment_status'] ?? 'pending').toString().toLowerCase();
      return status == 'paid';
    } catch (_) {
      return false;
    }
  }

  Future<bool> startPayment(String bookingId, num pesos) async {
    try {
      final result = await supabase.functions.invoke(
        'create-paymongo-payment',
        body: {
          'booking_id': bookingId,
          'amount_centavos': (pesos * 100).round(),
          'payment_method': 'qrph',
        },
      );
      final data = result.data as Map<String, dynamic>;
      final url = Uri.tryParse(data['checkout_url']?.toString() ?? '');
      if (url == null || !url.hasScheme) {
        throw Exception('Payment function did not return checkout_url.');
      }
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open checkout.');
      }

      if (!mounted) return false;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool checking = false;
          String message = 'Complete your QRPH payment, then tap “Check Payment”.';
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.verified_outlined, color: coffee),
                  SizedBox(width: 10),
                  Expanded(child: Text('Payment Verification')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amount: ₱${pesos.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(message),
                  const SizedBox(height: 10),
                  const Text(
                    'The booking will only show PAID after PayMongo confirms the payment and your booking record is updated.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white),
                  icon: checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh),
                  label: Text(checking ? 'Checking...' : 'Check Payment'),
                  onPressed: checking
                      ? null
                      : () async {
                          setDialogState(() {
                            checking = true;
                            message = 'Checking your payment status...';
                          });
                          final paid = await _checkPayment(bookingId);
                          if (!context.mounted) return;
                          if (paid) {
                            Navigator.pop(dialogContext, true);
                          } else {
                            setDialogState(() {
                              checking = false;
                              message = 'Payment is not confirmed yet. If you already paid, wait a few seconds and check again.';
                            });
                          }
                        },
                ),
              ],
            ),
          );
        },
      );

      return confirmed == true;
    } catch (e) {
      msg('Could not start payment: $e');
      return false;
    }
  }

  Future<void> selectLocation(
    String label,
    Future<void> Function() loadOptions,
    List<Map<String, String>> options,
    TextEditingController target, {
    bool enabled = true,
  }) async {
    if (!enabled || busy) return;
    if (options.isEmpty) {
      await loadOptions();
    }
    if (!mounted) return;

    final currentOptions = label == 'Province'
        ? _provinces
        : label == 'Municipality / City'
            ? _cities
            : _barangays;

    if (currentOptions.isEmpty) {
      msg(_locationError ?? 'No options are available. Please try again.');
      return;
    }

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final results = currentOptions
                .where((value) => value['name']!.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select $label',
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        onChanged: (value) => setSheetState(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Search locations',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: results.isEmpty
                            ? const Center(child: Text('No matching locations found.'))
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) => ListTile(
                                  title: Text(
                                    results[index]['name']!,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  trailing: const Icon(Icons.chevron_right_rounded, color: caramel),
                                  onTap: () => Navigator.pop(sheetContext, results[index]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() {
      target.text = selected['name']!;
      if (label == 'Province') {
        _selectedProvinceCode = selected['code'];
        _selectedCityCode = null;
        city.clear();
        barangay.clear();
        _cities = [];
        _barangays = [];
      } else if (label == 'Municipality / City') {
        _selectedCityCode = selected['code'];
        barangay.clear();
        _barangays = [];
      }
      _locationError = null;
    });
  }

  Widget locationField(
    String label,
    IconData icon,
    TextEditingController target,
    Future<void> Function() loadOptions,
    List<Map<String, String>> options, {
    bool enabled = true,
    bool loading = false,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (!enabled || busy || loading)
              ? null
              : () => selectLocation(label, loadOptions, options, target, enabled: enabled),
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFEDE3F1)
                    : const Color(0xFF52616B),
                fontWeight: FontWeight.w600,
              ),
              floatingLabelStyle: const TextStyle(
                color: Color(0xFFFF8057),
                fontWeight: FontWeight.w700,
              ),
              prefixIcon: Icon(
                icon,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFEDE3F1)
                    : const Color(0xFF52616B),
              ),
              suffixIcon: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : const Icon(Icons.keyboard_arrow_down_rounded),
              helperText: !enabled
                  ? (label == 'Municipality / City'
                      ? 'Select a province first'
                      : 'Select a city/municipality first')
                  : null,
            ),
            child: Text(
              target.text.isEmpty ? (enabled ? 'Select' : 'Select previous location first') : target.text,
              style: TextStyle(
                color: target.text.isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      );

  Widget _dateCard(DateTime value) {
    final selected = value.year == date.year && value.month == date.month && value.day == date.day;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return KleenovaPress(
      onTap: () => setState(() => date = value),
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? coffee : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: selected ? coffee : beige),
          boxShadow: [
            if (!selected) const BoxShadow(color: Color(0x12000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              indexedWeekday(value, weekdays),
              style: TextStyle(color: selected ? Colors.white70 : ink, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              '${value.day}',
              style: TextStyle(
                color: selected ? Colors.white : ink,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            Text(
              months[value.month - 1],
              style: TextStyle(color: selected ? Colors.white70 : ink, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomTime() async {
    final parts = time.split(' ');
    TimeOfDay initial = TimeOfDay.now();
    if (parts.length == 2) {
      final hm = parts[0].split(':');
      if (hm.length == 2) {
        var hour = int.tryParse(hm[0]) ?? initial.hourOfPeriod;
        final minute = int.tryParse(hm[1]) ?? initial.minute;
        final isPm = parts[1].toUpperCase() == 'PM';
        if (hour == 12) hour = 0;
        if (isPm) hour += 12;
        initial = TimeOfDay(hour: hour, minute: minute);
      }
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'SELECT YOUR PREFERRED TIME',
      cancelText: 'CANCEL',
      confirmText: 'SET TIME',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: coffee,
            onPrimary: Colors.white,
            surface: cream,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    final minute = picked.minute.toString().padLeft(2, '0');
    final period = picked.period == DayPeriod.am ? 'AM' : 'PM';

    setState(() {
      time = '$hour:$minute $period';
      customTimeSelected = true;
    });
  }

  Widget _timeChip(String value) => ChoiceChip(
        label: Text(value),
        selected: time == value && !customTimeSelected,
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.surface,
        side: BorderSide(color: Theme.of(context).dividerColor),
        labelStyle: TextStyle(
          color: time == value && !customTimeSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        onSelected: (_) => setState(() {
          time = value;
          customTimeSelected = false;
        }),
      );

  Widget _sectionTitle(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF7A6D66),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _stepBadge(String number, String label, bool active) {
    return Expanded(
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: active ? coffee : beige,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                color: active ? Colors.white : caramel,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? ink : const Color(0xFF8D8078),
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _datePickerButton() {
    return InkWell(
      onTap: busy
          ? null
          : () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: coffee,
                        onPrimary: Colors.white,
                        surface: cream,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (d != null && mounted) setState(() => date = d);
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: beige.withOpacity(.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: beige),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: caramel,
              size: 17,
            ),
            SizedBox(width: 6),
            Text(
              'Calendar',
              style: TextStyle(
                color: caramel,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: beige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: address,
            textInputAction: TextInputAction.next,
            // Explicit foreground colors prevent the dark-theme hint/label
            // colors from becoming nearly invisible on the light input fill.
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF243746),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'Street / house address',
              hintText: 'Enter your complete street address',
              labelStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFEDE3F1)
                    : const Color(0xFF52616B),
                fontWeight: FontWeight.w600,
              ),
              floatingLabelStyle: const TextStyle(
                color: Color(0xFFFF8057),
                fontWeight: FontWeight.w700,
              ),
              hintStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFBDB2BC)
                    : const Color(0xFF7A6D66),
              ),
              prefixIcon: Icon(
                Icons.home_work_outlined,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFEDE3F1)
                    : const Color(0xFF52616B),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF2A2220)
                  : cream,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF51413B)
                      : beige,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFFF8057), width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          locationField(
            'Province',
            Icons.map_outlined,
            province,
            _loadProvinces,
            _provinces,
            loading: _loadingProvinces,
          ),
          const SizedBox(height: 10),
          locationField(
            'Municipality / City',
            Icons.location_city_outlined,
            city,
            _loadCities,
            _cities,
            enabled: province.text.isNotEmpty,
            loading: _loadingCities,
          ),
          const SizedBox(height: 10),
          locationField(
            'Barangay',
            Icons.location_on_outlined,
            barangay,
            _loadBarangays,
            _barangays,
            enabled: city.text.isNotEmpty,
            loading: _loadingBarangays,
          ),
          if (_locationError != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _locationError!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentCard({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = paymentMethod == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? (selected ? const Color(0xFF3A2B29) : const Color(0xFF2A2220))
            : (selected ? const Color(0xFFFFF8F2) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? (selected ? const Color(0xFFD9A18B) : const Color(0xFF51413B))
              : (selected ? coffee : beige),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: busy
            ? null
            : () => setState(() => paymentMethod = value),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? (selected ? const Color(0xFF8A5142) : const Color(0xFF40332F))
                      : (selected ? coffee : beige),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: (selected || isDark) ? Colors.white : coffee,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFD8CFCA) : const Color(0xFF665B55),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? (isDark ? const Color(0xFFD9A18B) : coffee)
                        : (isDark ? const Color(0xFFB6A7A0) : const Color(0xFF9A8C83)),
                    width: 1.8,
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: selected
                    ? Container(
                        decoration: const BoxDecoration(
                          color: coffee,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final locationParts = [
      address.text.trim(),
      barangay.text.trim(),
      city.text.trim(),
      province.text.trim(),
    ].where((v) => v.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF173B55),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20173B55),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Booking summary',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '₱${finalTotal.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _summaryRow(Icons.cleaning_services_rounded, 'Service', widget.service.name),
          const SizedBox(height: 9),
          _summaryRow(Icons.event_rounded, 'Date & time', '${date.day}/${date.month}/${date.year} • $time'),
          if (locationParts.isNotEmpty) ...[
            const SizedBox(height: 9),
            _summaryRow(Icons.location_on_rounded, 'Address', locationParts.join(', ')),
          ],
          const SizedBox(height: 9),
          _summaryRow(
            Icons.payments_outlined,
            'Subtotal',
            '₱${widget.service.price.toStringAsFixed(2)}',
          ),
          if (appliedVoucher != null) ...[
            const SizedBox(height: 9),
            _summaryRow(
              Icons.local_offer_rounded,
              'Voucher',
              '$appliedVoucher  −₱${discountAmount.toStringAsFixed(2)}',
            ),
          ],
          const SizedBox(height: 9),
          _summaryRow(
            paymentMethod == 'paymongo_qrph' ? Icons.qr_code_2_rounded : Icons.payments_rounded,
            'Payment',
            paymentMethod == 'paymongo_qrph' ? 'PayMongo QRPH' : 'Pay After Service',
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.white70,
          size: 16,
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepIndicator(bool dark) {
    const labels = ['Date & Time', 'Instructions', 'Address', 'Payment'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? const Color(0xFF51413B) : beige,
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index <= _bookingStep;
          final current = index == _bookingStep;
          return Expanded(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: current ? 34 : 28,
                  height: current ? 34 : 28,
                  decoration: BoxDecoration(
                    color: active ? coffee : (dark ? const Color(0xFF403331) : const Color(0xFFF1E7DE)),
                    shape: BoxShape.circle,
                    boxShadow: current
                        ? [
                            BoxShadow(
                              color: coffee.withOpacity(.20),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: active
                      ? Icon(
                          index < _bookingStep
                              ? Icons.check_rounded
                              : index == 0
                                  ? Icons.schedule_rounded
                                  : index == 1
                                      ? Icons.notes_rounded
                                      : index == 2
                                          ? Icons.location_on_outlined
                                          : Icons.payments_outlined,
                          color: Colors.white,
                          size: current ? 17 : 14,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: dark ? Colors.white70 : const Color(0xFF8D8078),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active
                          ? (dark ? Colors.white : ink)
                          : (dark ? Colors.white54 : const Color(0xFF9A8E87)),
                      fontSize: 9.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (index < labels.length - 1)
                  Container(
                    width: 10,
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: active && index < _bookingStep
                        ? coffee
                        : (dark ? const Color(0xFF51413B) : beige),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _selectedServiceMiniCard(bool dark) {
    final image = widget.service.imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?auto=format&fit=crop&w=800&q=85'
        : widget.service.imageUrl;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? const Color(0xFF51413B) : beige),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              image,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: dark ? const Color(0xFF403331) : const Color(0xFFEFE0D5),
                child: Icon(
                  Icons.cleaning_services_rounded,
                  color: dark ? const Color(0xFFFFB18F) : coffee,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELECTED SERVICE',
                  style: TextStyle(
                    color: dark ? Colors.white54 : const Color(0xFF7A6D66),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.service.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dark ? Colors.white : ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.service.duration} • ₱${widget.service.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: dark ? const Color(0xFFD8CFCA) : const Color(0xFF6E625B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTitle(String title, String subtitle, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: dark ? Colors.white : ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: dark ? const Color(0xFFD0C4BE) : const Color(0xFF756861),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _instructionsCard(bool dark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dark ? const Color(0xFF51413B) : beige),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF49352F) : const Color(0xFFFFE8DE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.notes_rounded,
                  color: dark ? const Color(0xFFFFB18F) : caramel,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Help your cleaner prepare',
                  style: TextStyle(
                    color: dark ? Colors.white : ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: notes,
            minLines: 7,
            maxLines: 10,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
                  'Example: Please use the side gate. Focus on the kitchen and living room. There is a pet at home.',
              alignLabelWithHint: true,
              filled: true,
              fillColor: dark ? const Color(0xFF211B19) : const Color(0xFFFFFAF6),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 92),
                child: Icon(Icons.edit_note_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: dark ? const Color(0xFF51413B) : beige),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: dark ? const Color(0xFF51413B) : beige),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: caramel, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional • You can leave this blank if there are no special instructions.',
            style: TextStyle(
              color: dark ? const Color(0xFFBDB2BC) : const Color(0xFF8A7D75),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentStep(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Voucher & savings',
          subtitle: 'Apply a voucher before payment if you have one.',
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A211E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dark ? const Color(0xFF51413B) : beige),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: voucherController,
                      enabled: !busy && appliedVoucher == null,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Enter voucher code',
                        prefixIcon: const Icon(Icons.local_offer_outlined),
                        filled: true,
                        fillColor: dark ? const Color(0xFF211B19) : const Color(0xFFF9F3EE),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: dark ? const Color(0xFF51413B) : beige),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: dark ? const Color(0xFF51413B) : beige),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: coffee, width: 1.4),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : (appliedVoucher == null ? () => applyVoucher() : removeVoucher),
                      style: FilledButton.styleFrom(
                        backgroundColor: appliedVoucher == null ? coffee : const Color(0xFF9B5A48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        appliedVoucher == null ? 'Apply' : 'Remove',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: vouchers.entries.map((entry) {
                  final selected = appliedVoucher == entry.key;
                  return ActionChip(
                    avatar: Icon(
                      selected ? Icons.check_circle_rounded : Icons.local_offer_rounded,
                      size: 15,
                      color: selected ? Colors.white : coffee,
                    ),
                    label: Text('${entry.key} • ${entry.value['label']}'),
                    onPressed: busy ? null : () => applyVoucher(entry.key),
                    backgroundColor: selected ? coffee : (dark ? const Color(0xFF403331) : const Color(0xFFF7EDE6)),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : (dark ? Colors.white : coffee),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide(
                      color: selected ? coffee : (dark ? const Color(0xFF51413B) : const Color(0xFFE4D0C4)),
                    ),
                  );
                }).toList(),
              ),
              if (appliedVoucher != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF263A31) : const Color(0xFFEAF7F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF3E7A57), size: 17),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'You saved ₱${discountAmount.toStringAsFixed(2)} with $appliedVoucher.',
                          style: const TextStyle(
                            color: Color(0xFF356547),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle(
          'Payment method',
          subtitle: 'Secure payment is handled through PayMongo.',
        ),
        const SizedBox(height: 11),
        _paymentCard(
          value: 'paymongo_qrph',
          icon: Icons.qr_code_2_rounded,
          title: 'PayMongo QRPH',
          subtitle: 'Pay securely online using QRPH.',
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF29232A) : const Color(0xFFF1F6F8),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: dark ? const Color(0xFF51434D) : const Color(0xFFC7DCE4),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_rounded, color: deepSage, size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'After you confirm, KLEENOVA will open the secure PayMongo QRPH checkout. Your booking is saved before payment is started.',
                  style: TextStyle(
                    color: Color(0xFF53636B),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _summaryCard(),
      ],
    );
  }

  Future<bool> _goNext() async {
    if (_bookingStep == 0) {
      setState(() => _bookingStep = 1);
      return true;
    }

    if (_bookingStep == 1) {
      setState(() => _bookingStep = 2);
      return true;
    }

    if (_bookingStep == 2) {
      if (address.text.trim().isEmpty ||
          province.text.trim().isEmpty ||
          barangay.text.trim().isEmpty ||
          city.text.trim().isEmpty) {
        msg('Please complete your service address first.');
        return false;
      }
      setState(() => _bookingStep = 3);
      return true;
    }

    return false;
  }

  Widget _bottomAction(bool dark) {
    final last = _bookingStep == 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF211B19) : Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, -5),
          ),
        ],
        border: Border(
          top: BorderSide(color: Color(0x12000000)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_bookingStep > 0) ...[
              SizedBox(
                width: 54,
                height: 52,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _bookingStep--),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: dark ? const Color(0xFF6B5A53) : beige),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: dark ? Colors.white : ink,
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : last
                          ? book
                          : _goNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: caramel,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: caramel.withOpacity(.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  icon: Icon(
                    last ? Icons.lock_rounded : Icons.arrow_forward_rounded,
                    size: 19,
                  ),
                  label: Text(
                    last ? 'Confirm & Pay' : 'Continue',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final stepTitles = [
      ['Choose date & time', 'Select when you want your cleaning service.'],
      ['Add instructions', 'Tell your cleaner anything important before the visit.'],
      ['Service address', 'Enter the exact location where the service will happen.'],
      ['Review & payment', 'Check your booking details and continue to secure PayMongo payment.'],
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: _bookingStep == 0 ? 'Back to service' : 'Previous step',
          onPressed: busy
              ? null
              : () {
                  if (_bookingStep > 0) {
                    setState(() => _bookingStep--);
                  } else {
                    Navigator.pop(context);
                  }
                },
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A211E) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: dark ? const Color(0xFF51413B) : beige),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: dark ? Colors.white : ink,
              size: 21,
            ),
          ),
        ),
        title: Text(
          'Book a service',
          style: TextStyle(
            color: dark ? Colors.white : ink,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -.4,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: [
                _stepIndicator(dark),
                const SizedBox(height: 14),
                _selectedServiceMiniCard(dark),
                const SizedBox(height: 24),
                _stepTitle(
                  stepTitles[_bookingStep][0],
                  stepTitles[_bookingStep][1],
                  dark,
                ),
                const SizedBox(height: 16),

                if (_bookingStep == 0) ...[
                  _sectionTitle(
                    'Select date',
                    subtitle: 'Choose one of the available days or use the calendar.',
                    trailing: _datePickerButton(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 94,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 7,
                      separatorBuilder: (_, __) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final value = DateTime.now().add(
                          Duration(days: index + 1),
                        );
                        return _dateCard(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF2A211E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: dark ? const Color(0xFF51413B) : beige),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          'Select time',
                          subtitle: 'Pick a preferred time for your cleaner.',
                          trailing: OutlinedButton.icon(
                            onPressed: busy ? null : _pickCustomTime,
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(customTimeSelected ? time : 'Custom'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: customTimeSelected ? Colors.white : caramel,
                              backgroundColor: customTimeSelected
                                  ? coffee
                                  : (dark ? const Color(0xFF403331) : beige.withOpacity(.55)),
                              side: BorderSide(
                                color: customTimeSelected ? coffee : Colors.transparent,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: slots.map(_timeChip).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_bookingStep == 1) _instructionsCard(dark),

                if (_bookingStep == 2) ...[
                  _addressCard(),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF29232A) : const Color(0xFFF1F6F8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: dark ? const Color(0xFF51434D) : const Color(0xFFC7DCE4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: dark ? const Color(0xFFFFB18F) : deepSage,
                          size: 19,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Please make sure the address is complete so the assigned cleaner can find you easily.',
                            style: TextStyle(
                              color: dark ? const Color(0xFFEDE3F1) : const Color(0xFF53636B),
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_bookingStep == 3) _paymentStep(dark),
              ],
            ),
          ),
          _bottomAction(dark),
        ],
      ),
    );
  }

}

String indexedWeekday(DateTime value, List<String> weekdays) => weekdays[value.weekday - 1];

String kleenovaDateTime(dynamic raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} • $hour:$minute $suffix';
}

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});
  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  late Future<List<Map<String,dynamic>>> future;
  Timer? _autoRefreshTimer;
  @override
  void initState() {
    super.initState();
    future = load();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentAutoRefresh());
  }

  Future<void> _silentAutoRefresh() async {
    try {
      final next = await load();
      if (!mounted) return;
      setState(() => future = Future.value(next));
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<List<Map<String,dynamic>>> load() async {
    final rows = await supabase
        .from('bookings')
        .select()
        .eq('customer_id', supabase.auth.currentUser!.id)
        // Customer removal is a soft delete. Do NOT filter admin_deleted_at:
        // an admin-hidden booking must remain visible to the customer.
        .isFilter('customer_deleted_at', null)
        .order('created_at', ascending: false);

    final result = <Map<String,dynamic>>[];
    final seenDuplicateKeys = <String>{};

    // A payment can move an existing booking from PENDING to PAID. If an
    // older duplicate row exists for the exact same booking details, never
    // show both rows to the customer; prefer the paid row.
    final typedRows = List<Map<String,dynamic>>.from(rows);
    final paidKeys = <String>{};
    for (final row in typedRows) {
      final payment = (row['payment_status'] ?? '').toString().toLowerCase();
      if (payment != 'paid') continue;
      final key = _bookingDisplayKey(row);
      paidKeys.add(key);
    }

    for (final row in typedRows) {
      final key = _bookingDisplayKey(row);
      final payment = (row['payment_status'] ?? 'pending').toString().toLowerCase();
      final status = (row['status'] ?? 'pending').toString().toLowerCase();
      final duplicatePaidPending = payment == 'pending' && paidKeys.contains(key) &&
          status != 'cancelled' && status != 'canceled';
      if (duplicatePaidPending) {
        continue;
      }
      if (seenDuplicateKeys.contains(key) && payment == 'pending') continue;
      seenDuplicateKeys.add(key);
      result.add(row);
    }
    // Resolve assigned cleaner IDs into readable names for the customer cards.
    // Keep existing saved name fields as fallbacks for older booking records.
    try {
      // Query only columns required by the customer view. Selecting optional
      // columns that do not exist in some database schemas makes the entire
      // lookup fail and incorrectly displays 'Waiting for cleaner assignment'.
      final cleanerRows = await supabase.from('cleaners').select('id,full_name');
      final cleanerById = <String, Map<String, dynamic>>{};
      for (final raw in List<Map<String, dynamic>>.from(cleanerRows)) {
        final id = (raw['id'] ?? '').toString().trim();
        if (id.isNotEmpty) cleanerById[id] = raw;
      }
      for (final booking in result) {
        final ids = <String>{};
        final many = booking['cleaner_ids'];
        if (many is List) ids.addAll(many.map((value) => value.toString().trim()).where((id) => id.isNotEmpty));
        final one = (booking['cleaner_id'] ?? '').toString().trim();
        if (one.isNotEmpty) ids.add(one);
        final resolvedNames = <String>[];
        for (final id in ids) {
          final cleaner = cleanerById[id];
          final name = (cleaner?['full_name'] ?? cleaner?['name'] ?? cleaner?['cleaner_name'] ?? '').toString().trim();
          if (name.isNotEmpty && !resolvedNames.contains(name)) resolvedNames.add(name);
        }
        final savedNames = booking['cleaner_names'];
        if (resolvedNames.isEmpty && savedNames is List) {
          resolvedNames.addAll(savedNames.map((v) => v.toString().trim()).where((v) => v.isNotEmpty));
        }
        final savedName = (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '').toString().trim();
        if (resolvedNames.isEmpty && savedName.isNotEmpty) resolvedNames.add(savedName);
        booking['cleaner_names'] = resolvedNames;
      }
    } catch (_) {
      // If the cleaners table cannot be read, retain names already stored on bookings.
      for (final booking in result) {
        final names = booking['cleaner_names'];
        if (names is! List) {
          final oldName = (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '').toString().trim();
          booking['cleaner_names'] = oldName.isEmpty ? <String>[] : <String>[oldName];
        }
      }
    }
    return result;
  }

  String _bookingDisplayKey(Map<String,dynamic> row) => [
    row['service_id'] ?? row['service_name'] ?? '',
    row['booking_date'] ?? '',
    row['booking_time'] ?? '',
    row['address'] ?? '',
    row['municipality'] ?? '',
  ].map((v) => v.toString().trim().toLowerCase()).join('|');

  Future<void> refresh() async {
    setState(() { future = load(); });
    await future;
  }

  Future<bool> _isPaymentPaid(String bookingId) async {
    try {
      final row = await supabase
          .from('bookings')
          .select('payment_status')
          .eq('id', bookingId)
          .maybeSingle();
      return (row?['payment_status'] ?? 'pending').toString().toLowerCase() == 'paid';
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelMyBooking(Map<String,dynamic> booking) async {
    var currentStatus = (booking['status'] ?? 'pending').toString().toLowerCase();
    var currentPaymentStatus = (booking['payment_status'] ?? 'pending').toString().toLowerCase();

    // Always re-read the booking before allowing cancellation. The payment
    // webhook may have changed payment_status after this card was loaded.
    try {
      final latest = await supabase
          .from('bookings')
          .select('status,payment_status')
          .eq('id', booking['id'])
          .eq('customer_id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (latest != null) {
        currentStatus = (latest['status'] ?? currentStatus).toString().toLowerCase();
        currentPaymentStatus = (latest['payment_status'] ?? currentPaymentStatus).toString().toLowerCase();
        booking['status'] = latest['status'];
        booking['payment_status'] = latest['payment_status'];
      }
    } catch (_) {}

    if (currentPaymentStatus == 'paid') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paid bookings can no longer be cancelled.')));
      }
      return;
    }
    if (currentStatus == 'completed' || currentStatus == 'cancelled' || currentStatus == 'canceled') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This booking can no longer be cancelled.')));
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('Are you sure you want to cancel this booking? The cancellation will be sent to the KLEENOVA admin team.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    ) ?? false;
    if (!ok) return;

    try {
      final bookingId = booking['id']?.toString() ?? '';
      if (bookingId.isEmpty) throw Exception('Missing booking ID.');

      // Customer cancellation is performed through a small Supabase RPC so
      // RLS does not silently turn the UPDATE into a zero-row update. The RPC
      // must verify auth.uid() = customer_id before changing the status.
      final result = await supabase.rpc(
        'cancel_my_booking',
        params: {'p_booking_id': bookingId},
      );

      if (result != true) {
        throw Exception('The booking was not cancelled. Make sure the cancel_my_booking Supabase function is installed.');
      }

      // Notify admins only after the database change succeeds. The admin
      // notification list collapses older alerts for this same booking so the
      // cancellation becomes the single visible current alert.
      try {
        await notifyAdmins(
          title: 'Booking cancelled by user',
          message: 'A customer cancelled their ${(booking['service_name'] ?? 'service').toString()} booking.',
          type: 'booking',
          bookingId: bookingId,
        );
      } catch (_) {}

      if (!mounted) return;
      // Refresh exactly once after a successful cancellation. There is no
      // periodic/background refresh on this page.
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel booking: $e')));
    }
  }

  Future<void> _deleteMyBooking(Map<String,dynamic> booking) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove booking from your list?'),
        content: const Text('This hides the booking from your account only. The admin will still keep the booking record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('You must be logged in to delete a booking.');
      final bookingId = booking['id'];
      if (bookingId == null) throw Exception('This booking has no valid ID.');

      // Use a database function that verifies the signed-in customer owns
      // this booking before marking it hidden. This avoids an UPDATE silently
      // affecting zero rows because of the bookings table's RLS policy.
      final result = await supabase.rpc(
        'remove_my_booking',
        params: {'p_booking_id': bookingId.toString()},
      );

      if (result != true) {
        throw Exception(
          'The booking was not removed. Make sure the remove_my_booking Supabase function and customer_deleted_at column are installed.',
        );
      }

      if (!mounted) return;
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking removed from your list.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete booking: $e')));
    }
  }

  Future<void> _checkPayment(Map<String,dynamic> booking) async {
    final paid = await _isPaymentPaid(booking['id'].toString());
    if (!mounted) return;
    if (paid) {
      await refresh();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.check_circle, color: Color(0xFF4F7B58)),
            SizedBox(width: 10),
            Text('Payment Confirmed'),
          ]),
          content: const Text('Your QRPH payment has been confirmed. Your booking now shows PAID.'),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.schedule, color: Color(0xFFB7791F)),
            SizedBox(width: 10),
            Text('Payment Pending'),
          ]),
          content: const Text(
            'Your payment has not been confirmed yet. If you already completed QRPH payment, wait a few seconds and tap Check Payment again.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Okay'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _requestReschedule(Map<String, dynamic> booking) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final oldDate = (booking['booking_date'] ?? '').toString();
    final oldTime = (booking['booking_time'] ?? '').toString();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final newDate = pickedDate.toIso8601String().split('T').first;
    final timeController = TextEditingController(text: oldTime.isNotEmpty ? oldTime : '09:00 AM');
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request reschedule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current schedule',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text('$oldDate  •  $oldTime'),
            const SizedBox(height: 16),
            const Text(
              'New requested schedule',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text('$newDate'),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                labelText: 'New preferred time (e.g. 10:00 AM)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );

    if (result != true) {
      timeController.dispose();
      reasonController.dispose();
      return;
    }

    try {
      await supabase.from('booking_reschedule_requests').insert({
        'booking_id': booking['id'],
        'customer_id': user.id,
        'old_date': oldDate,
        'old_time': oldTime,
        'requested_date': newDate,
        'requested_time': timeController.text.trim(),
        'reason': reasonController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule request sent to the admin.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send request: $e')),
        );
      }
    }

    timeController.dispose();
    reasonController.dispose();
  }

  Future<void> _bookAgain(Map<String, dynamic> booking) async {
    try {
      final serviceId = booking['service_id']?.toString();
      Map<String, dynamic>? service;
      if (serviceId != null && serviceId.isNotEmpty) {
        service = await supabase.from('services').select().eq('id', serviceId).maybeSingle();
      }
      if (service == null) {
        final name = (booking['service_name'] ?? '').toString();
        service = await supabase.from('services').select().eq('name', name).limit(1).maybeSingle();
      }
      if (service == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This service is no longer available.'))); return; }
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(service: ServiceItem.fromMap(Map<String, dynamic>.from(service!)))));
      await refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start a repeat booking: $e'))); }
  }

  Future<void> _showBookingDetails(Map<String,dynamic> booking) async {
    final colors = Theme.of(context).colorScheme;
    final rawStatus = (booking['status'] ?? 'pending').toString().toLowerCase();
    final paymentStatus = (booking['payment_status'] ?? 'pending').toString().toLowerCase();
    final amount = (booking['service_price'] as num?)?.toDouble() ?? 0;
    final bookingId = booking['id']?.toString() ?? '—';
    final paymentMethod = (booking['payment_method'] ?? 'QRPH').toString();
    final address = [
      (booking['address'] ?? '').toString().trim(),
      (booking['barangay'] ?? '').toString().trim(),
      (booking['municipality'] ?? '').toString().trim(),
      (booking['province'] ?? '').toString().trim(),
    ].where((v) => v.isNotEmpty).join(', ');

    String serviceStatus = rawStatus;
    if (serviceStatus == 'confirmed' || serviceStatus == 'on_the_way' || serviceStatus == 'currently_cleaning') {
      serviceStatus = 'in_progress';
    }
    final isCancelled = serviceStatus == 'cancelled' || serviceStatus == 'canceled';
    final currentStep = serviceStatus == 'completed' ? 2 : serviceStatus == 'in_progress' ? 1 : 0;

    // Resolve ALL assigned cleaners, not just cleaner_id or the first
    // item in cleaner_ids. The single ID remains supported for older bookings.
    final cleanerNames = <String>[];
    final assignedCleanerIds = <String>{};
    final multipleCleanerIds = booking['cleaner_ids'];
    if (multipleCleanerIds is List) {
      assignedCleanerIds.addAll(
        multipleCleanerIds
            .map((id) => id.toString().trim())
            .where((id) => id.isNotEmpty),
      );
    }
    final singleCleanerId = (booking['cleaner_id'] ?? '').toString().trim();
    if (singleCleanerId.isNotEmpty) assignedCleanerIds.add(singleCleanerId);

    if (assignedCleanerIds.isNotEmpty) {
      try {
        final cleanerRows = await supabase
            .from('cleaners')
            .select('id,full_name')
            .inFilter('id', assignedCleanerIds.toList());
        for (final cleaner in List<Map<String, dynamic>>.from(cleanerRows)) {
          final name = (cleaner['full_name'] ?? '').toString().trim();
          if (name.isNotEmpty && !cleanerNames.contains(name)) {
            cleanerNames.add(name);
          }
        }
      } catch (e) {
        debugPrint('Could not resolve booking cleaner names: $e');
      }
    }

    // Use saved display names when an older booking has no resolvable cleaner row.
    if (cleanerNames.isEmpty) {
      final savedNames = booking['cleaner_names'];
      if (savedNames is List) {
        for (final value in savedNames) {
          final name = value.toString().trim();
          if (name.isNotEmpty && !cleanerNames.contains(name)) {
            cleanerNames.add(name);
          }
        }
      }
      final savedName =
          (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '')
              .toString()
              .trim();
      if (cleanerNames.isEmpty && savedName.isNotEmpty) {
        cleanerNames.add(savedName);
      }
    }

    Widget statusStep({required int index, required String title, required String subtitle}) {
      final active = !isCancelled && index <= currentStep;
      final completed = !isCancelled && index < currentStep;
      final color = active ? const Color(0xFF4F7B58) : const Color(0xFFCFC3BC);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFE7F2E9) : const Color(0xFFF2ECE8),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Icon(
                  completed ? Icons.check_rounded : (active ? Icons.radio_button_checked_rounded : Icons.circle_outlined),
                  size: 17,
                  color: color,
                ),
              ),
              if (index < 2)
                Container(width: 2, height: 35, color: index < currentStep ? const Color(0xFF9FC5A5) : const Color(0xFFE1D8D2)),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: active ? colors.onSurface : colors.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.3, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFFFE3D8), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.event_note_rounded, color: coffee),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Booking Details')),
        ]),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7EFE9),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(booking['service_name']?.toString() ?? 'Cleaning service', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text('Booking #${bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 9),
                    Text('Booked on ${kleenovaDateTime(booking['created_at'])}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    if ((booking['updated_at'] ?? '').toString().trim().isNotEmpty)
                      Text('Last updated ${kleenovaDateTime(booking['updated_at'])}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 17),
                const Text('Service status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (isCancelled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFFBE9E7), borderRadius: BorderRadius.circular(15)),
                    child: const Row(children: [
                      Icon(Icons.cancel_outlined, color: Color(0xFFC94A43)),
                      SizedBox(width: 9),
                      Expanded(child: Text('This booking was cancelled.', style: TextStyle(color: Color(0xFF9E332D), fontWeight: FontWeight.w800))),
                    ]),
                  )
                else
                  Column(children: [
                    statusStep(index: 0, title: 'Pending', subtitle: 'Your booking has been received and is waiting for assignment.'),
                    statusStep(
                      index: 1,
                      title: 'In progress',
                      subtitle: cleanerNames.isEmpty
                          ? 'Your cleaning service is being processed.'
                          : 'Assigned cleaners: ${cleanerNames.join(', ')}',
                    ),
                    statusStep(index: 2, title: 'Completed service', subtitle: 'The cleaning service has been completed.'),
                  ]),
                const SizedBox(height: 5),
                const Text('Booking information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 11),
                _detailRow('Booked on', kleenovaDateTime(booking['created_at'])),
                if ((booking['updated_at'] ?? '').toString().trim().isNotEmpty)
                  _detailRow('Last updated', kleenovaDateTime(booking['updated_at'])),
                _detailRow('Service date', booking['booking_date']?.toString() ?? '—'),
                _detailRow('Service time', booking['booking_time']?.toString() ?? '—'),
                _detailRow('Address', address.isEmpty ? '—' : address),
                if ((booking['instructions'] ?? booking['notes'] ?? '').toString().trim().isNotEmpty)
                  _detailRow('Instructions', (booking['instructions'] ?? booking['notes']).toString()),
                if (cleanerNames.isNotEmpty)
                  _detailRow('Assigned cleaners', cleanerNames.join(', ')),
                const SizedBox(height: 6),
                const Text('Payment information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 11),
                _detailRow('Amount', '₱${amount.toStringAsFixed(2)}'),
                _detailRow('Payment status', paymentStatus.toUpperCase()),
                _detailRow('Method', paymentMethod),
                _detailRow('Booking ID', bookingId),
              ],
            ),
          ),
        ),
        actions: [
          if (paymentStatus == 'paid')
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showReceipt(booking);
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View receipt'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.primary, foregroundColor: colors.onPrimary),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withOpacity(.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 115,
              child: Text(
                label,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReceipt(Map<String,dynamic> booking) async {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final amount = (booking['service_price'] as num?)?.toDouble() ?? 0;
    final status = (booking['payment_status'] ?? 'pending').toString().toUpperCase();
    final bookingId = booking['id']?.toString() ?? '—';
    // Keep the existing QRPH payment flow and display the method stored on the booking.
    final paymentMethod = (booking['payment_method'] ?? 'QRPH').toString();
    final createdAt = booking['created_at']?.toString() ?? '';
    final paid = status == 'PAID' || status == 'COMPLETED';
    final statusColor = paid ? const Color(0xFF2E8B62) : const Color(0xFFD18A25);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? .30 : .14),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F5C73), Color(0xFF197F91)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -18,
                          top: -26,
                          child: Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(.07),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 43,
                                  height: 43,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(.13),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const KleenovaLogoMark(size: 36, onDark: true),
                                ),
                                const SizedBox(width: 11),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'KLEENOVA',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.3,
                                        ),
                                      ),
                                      Text(
                                        'CLEAN SPACES. BETTER DAYS.',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.receipt_long_rounded, color: Color(0xFFFFC857), size: 27),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'PAYMENT RECEIPT',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '₱${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(.18),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: statusColor.withOpacity(.65)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    paid ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                    color: paid ? const Color(0xFFB6F0D2) : const Color(0xFFFFD68A),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    paid ? 'PAYMENT CONFIRMED' : 'PAYMENT $status',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 21, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BOOKING DETAILS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Color(0xFF0F5C73),
                          ),
                        ),
                        const SizedBox(height: 15),
                        _receiptRow('Service', booking['service_name']?.toString() ?? 'Cleaning service'),
                        _receiptRow('Booking reference', bookingId),
                        _receiptRow('Booking date', booking['booking_date']?.toString() ?? '—'),
                        _receiptRow('Time', booking['booking_time']?.toString() ?? '—'),
                        _receiptRow('Payment method', paymentMethod),
                        if (createdAt.isNotEmpty) _receiptRow('Created on', createdAt),
                        const SizedBox(height: 5),
                        Divider(color: colors.outlineVariant, height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'TOTAL ${paid ? 'PAID' : 'AMOUNT'}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .8,
                                ),
                              ),
                            ),
                            Text(
                              '₱${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF302823) : const Color(0xFFFFF4EA),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDark ? const Color(0xFF51413B) : const Color(0xFFF0DCCB),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.favorite_rounded, color: Color(0xFFFF7A59), size: 22),
                              const SizedBox(height: 7),
                              Text(
                                'Thank you for choosing KLEENOVA!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  fontFamily: 'serif',
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Clean spaces. Better days.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F5C73),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 118, child: Text(label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
        Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface))),
      ]),
    );
  }

  Future<void> _payBooking(Map<String,dynamic> booking) async {
    final alreadyPaid = await _isPaymentPaid(booking['id'].toString());
    if (alreadyPaid) {
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This booking is already paid.')));
      return;
    }

    final amount = (booking['service_price'] as num?)?.toDouble() ?? 0;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.qr_code_2, color: coffee),
          SizedBox(width: 10),
          Expanded(child: Text('Continue to QRPH Payment')),
        ]),
        content: Text(
          'Amount due: ₱${amount.toStringAsFixed(2)}\n\nYou will be redirected to the secure QRPH checkout. After paying, return here and tap Check Payment.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue to Pay'),
          ),
        ],
      ),
    ) ?? false;

    if (!proceed) return;

    try {
      final result = await supabase.functions.invoke(
        'create-paymongo-payment',
        body: {
          'booking_id': booking['id'].toString(),
          'amount_centavos': (amount * 100).round(),
          'payment_method': 'qrph',
        },
      );
      final data = result.data as Map<String,dynamic>;
      final url = Uri.tryParse(data['checkout_url']?.toString() ?? '');
      if (url == null || !url.hasScheme) throw Exception('Payment function did not return checkout_url.');
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw Exception('Could not open checkout.');

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Payment Verification'),
          content: const Text('Complete the QRPH payment, return to KLEENOVA, then tap Check Payment on this booking.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Later')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _checkPayment(booking);
              },
              child: const Text('Check Payment'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start payment: $e')));
      }
    }
  }

  String _bookingFilter = 'All';

  Widget _bookingStatusChip(String status, bool paid) {
    final normalized = status.toLowerCase();
    final isCancelled = normalized == 'cancelled' || normalized == 'canceled';
    final label = isCancelled ? 'CANCELLED' : paid ? 'PAID' : 'PENDING';
    final bg = isCancelled
        ? const Color(0xFFFBE9E7)
        : paid
            ? const Color(0xFFE5F4E9)
            : const Color(0xFFF4F7F8);
    final fg = isCancelled
        ? const Color(0xFFB63F37)
        : paid
            ? const Color(0xFF3F7650)
            : const Color(0xFF7A4B38);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .3)),
    );
  }

  String _prettyStatus(Map<String, dynamic> booking) {
    final payment = (booking['payment_status'] ?? 'pending').toString().toLowerCase();
    final serviceStatus = (booking['status'] ?? 'pending').toString().toLowerCase();
    if (serviceStatus == 'cancelled' || serviceStatus == 'canceled') return 'Cancelled';
    if (serviceStatus == 'completed') return 'Completed';
    if (serviceStatus == 'in_progress' || serviceStatus == 'currently_cleaning' || serviceStatus == 'on_the_way') return 'In Progress';
    return payment == 'paid' ? 'Paid' : 'Pending';
  }

  bool _matchesFilter(Map<String, dynamic> booking) {
    if (_bookingFilter == 'All') return true;
    final serviceStatus = (booking['status'] ?? 'pending').toString().toLowerCase();
    final payment = (booking['payment_status'] ?? 'pending').toString().toLowerCase();
    switch (_bookingFilter) {
      case 'Completed': return serviceStatus == 'completed';
      case 'Cancelled': return serviceStatus == 'cancelled' || serviceStatus == 'canceled';
      case 'In Progress': return serviceStatus == 'in_progress' || serviceStatus == 'currently_cleaning' || serviceStatus == 'on_the_way';
      case 'Paid': return payment == 'paid' && serviceStatus != 'cancelled' && serviceStatus != 'canceled';
      case 'Pending': return payment != 'paid' && serviceStatus != 'completed' && serviceStatus != 'cancelled' && serviceStatus != 'canceled';
      default: return true;
    }
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final paymentStatus = (b['payment_status'] ?? 'pending').toString().toLowerCase();
    final status = (b['status'] ?? 'pending').toString().toLowerCase();
    final isPaid = paymentStatus == 'paid';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    final isCompleted = status == 'completed';
    final paymentMethod = (b['payment_method'] ?? 'qrph').toString().toLowerCase().replaceAll(' ', '_');
    // Only offer online QRPH checkout for bookings that have not been paid.
    // Pay-after-service bookings must be settled through the existing service flow.
    final canContinuePayment = !isPaid && !isCancelled && !isCompleted &&
        (paymentMethod == 'qrph' || paymentMethod.contains('paymongo'));
    final amount = (b['service_price'] as num?)?.toDouble() ?? 0;
    final serviceName = (b['service_name'] ?? 'Cleaning service').toString();
    final date = (b['booking_date'] ?? '').toString().trim();
    final time = (b['booking_time'] ?? '').toString().trim();
    final address = (b['address'] ?? '').toString().trim();
    final city = (b['municipality'] ?? '').toString().trim();
    final bookedOn = (b['created_at'] ?? '').toString();
    final lastUpdated = (b['updated_at'] ?? '').toString();
    final cleanerNames = <String>[];
    final cleanerList = b['cleaner_names'];
    if (cleanerList is List) {
      cleanerNames.addAll(cleanerList.map((v) => v.toString().trim()).where((v) => v.isNotEmpty));
    }
    final fallbackCleaner = (b['cleaner_name'] ?? b['assigned_cleaner_name'] ?? '').toString().trim();
    if (cleanerNames.isEmpty && fallbackCleaner.isNotEmpty) cleanerNames.add(fallbackCleaner);

    String progressLabel;
    IconData progressIcon;
    Color progressColor;
    if (isCancelled) {
      progressLabel = 'Cancelled';
      progressIcon = Icons.cancel_outlined;
      progressColor = const Color(0xFFC94A43);
    } else if (isCompleted) {
      progressLabel = 'Completed';
      progressIcon = Icons.check_circle_rounded;
      progressColor = const Color(0xFF3F7650);
    } else if (status == 'in_progress' || status == 'currently_cleaning' || status == 'on_the_way') {
      progressLabel = 'Cleaning in progress';
      progressIcon = Icons.cleaning_services_rounded;
      progressColor = const Color(0xFF176B87);
    } else if (status == 'confirmed') {
      progressLabel = 'Confirmed';
      progressIcon = Icons.verified_outlined;
      progressColor = const Color(0xFF176B87);
    } else {
      progressLabel = 'Booking received';
      progressIcon = Icons.schedule_rounded;
      progressColor = const Color(0xFFB7791F);
    }

    final bookingId = b['id']?.toString() ?? '';
    final shortId = bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final secondarySurface = Theme.of(context).colorScheme.surfaceContainerHighest;
    final text = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dark ? const Color(0xFF51413B) : const Color(0xFFE6D8CE)),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFE3D8), Color(0xFFE8F0F3)]),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.cleaning_services_rounded, color: coffee, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(serviceName, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Booking #$shortId', style: TextStyle(color: muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ])),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz_rounded, color: muted),
              onSelected: (value) {
                if (value == 'details') _showBookingDetails(b);
                if (value == 'receipt') _showReceipt(b);
                if (value == 'cancel') _cancelMyBooking(b);
                if (value == 'reschedule') _requestReschedule(b);
                if (value == 'again') _bookAgain(b);
                if (value == 'delete') _deleteMyBooking(b);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'details', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.visibility_outlined), title: Text('View details'))),
                if (isPaid) const PopupMenuItem(value: 'receipt', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long_outlined), title: Text('View receipt'))),
                if (!isPaid && !isCompleted && !isCancelled) const PopupMenuItem(value: 'cancel', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.cancel_outlined, color: Colors.redAccent), title: Text('Cancel booking'))),
                if (!isCompleted && !isCancelled) const PopupMenuItem(value: 'reschedule', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.calendar_month_outlined), title: Text('Request reschedule'))),
                const PopupMenuItem(value: 'again', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.replay_rounded), title: Text('Book again'))),
                const PopupMenuItem(value: 'delete', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline, color: Colors.redAccent), title: Text('Delete booking'))),
              ],
            ),
          ]),
          const SizedBox(height: 14),

          // Booking progress is deliberately separate from payment status so the customer
          // can understand what is happening with the service at a glance.
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: progressColor.withOpacity(dark ? .18 : .09),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: progressColor.withOpacity(.22)),
            ),
            child: Row(children: [
              Icon(progressIcon, color: progressColor, size: 21),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BOOKING STATUS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .7, color: progressColor)),
                const SizedBox(height: 2),
                Text(progressLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: progressColor)),
              ])),
              if (!isCancelled && !isCompleted)
                Icon(Icons.chevron_right_rounded, color: progressColor, size: 20),
            ]),
          ),
          const SizedBox(height: 10),

          // Schedule and location are grouped because these are the two details the
          // customer normally needs to check before the service.
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: secondarySurface, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: coffee),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SERVICE SCHEDULE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .6, color: muted)),
                  const SizedBox(height: 3),
                  Text(date.isEmpty && time.isEmpty ? 'Schedule not set' : '${date.isEmpty ? 'Date not set' : date}  •  ${time.isEmpty ? 'Time not set' : time}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: text)),
                ])),
              ]),
              if (address.isNotEmpty || city.isNotEmpty) ...[
                const SizedBox(height: 11),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.location_on_outlined, size: 18, color: muted),
                  const SizedBox(width: 9),
                  Expanded(child: Text([address, city].where((v) => v.isNotEmpty).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted, height: 1.3))),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: _transactionInfoTile(
              icon: isPaid ? Icons.check_circle_outline : Icons.schedule_rounded,
              label: 'PAYMENT',
              value: isPaid ? 'Paid' : 'Payment pending',
              color: isPaid ? const Color(0xFF3F7650) : const Color(0xFFB7791F),
            )),
            const SizedBox(width: 9),
            Expanded(child: _transactionInfoTile(
              icon: Icons.payments_outlined,
              label: 'TOTAL',
              value: '₱${amount.toStringAsFixed(2)}',
              color: coffee,
            )),
          ]),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF302724) : const Color(0xFFF7EFE9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(cleanerNames.isEmpty ? Icons.person_off_outlined : Icons.person_outline, size: 18, color: cleanerNames.isEmpty ? muted : coffee),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CLEANER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .6, color: muted)),
                const SizedBox(height: 2),
                Text(cleanerNames.isEmpty ? (isCompleted ? 'Cleaner details unavailable' : 'Waiting for cleaner assignment') : cleanerNames.join(', '), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: text)),
              ])),
            ]),
          ),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: Text('Booked ${kleenovaDateTime(bookedOn)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: muted))),
            if (lastUpdated.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.update_rounded, size: 13, color: muted),
              const SizedBox(width: 3),
              Text('Updated', style: TextStyle(fontSize: 10.5, color: muted)),
            ],
          ]),
          const SizedBox(height: 12),
          if (canContinuePayment) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _payBooking(b),
                icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                label: const Text('Continue Payment', style: TextStyle(fontWeight: FontWeight.w900)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7A59),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showBookingDetails(b),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View booking details', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
            ),
          ),
        ]),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF12171B) : const Color(0xFFF7F1EA);
    final text = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Bookings', style: TextStyle(fontWeight: FontWeight.w900, color: text)),
            Text('Track your cleaning service transactions', style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh bookings',
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load your bookings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800, color: text),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final rows = snapshot.data ?? <Map<String, dynamic>>[];
          final filtered = rows.where(_matchesFilter).toList();
          final active = rows.where((b) {
            final status = (b['status'] ?? 'pending').toString().toLowerCase();
            return status != 'completed' && status != 'cancelled' && status != 'canceled';
          }).length;
          final completed = rows.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'completed').length;
          final paid = rows.where((b) => (b['payment_status'] ?? '').toString().toLowerCase() == 'paid').length;
          final pendingPayment = rows.where((b) {
            final status = (b['status'] ?? '').toString().toLowerCase();
            final payment = (b['payment_status'] ?? 'pending').toString().toLowerCase();
            return status != 'cancelled' && status != 'canceled' && payment != 'paid';
          }).length;

          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF2C2220), Color(0xFF24313A)]
                          : const [Color(0xFFFFE5D8), Color(0xFFEAF2F4)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: isDark ? const Color(0xFF51413B) : const Color(0xFFE6D8CE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Booking overview', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: text)),
                      const SizedBox(height: 4),
                      Text('Keep an eye on your service progress and payment.', style: TextStyle(fontSize: 11.5, color: muted)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: _transactionInfoTile(icon: Icons.pending_actions_rounded, label: 'ACTIVE', value: '$active', color: const Color(0xFFB7791F))),
                        const SizedBox(width: 8),
                        Expanded(child: _transactionInfoTile(icon: Icons.task_alt_rounded, label: 'COMPLETED', value: '$completed', color: const Color(0xFF4F7B58))),
                        const SizedBox(width: 8),
                        Expanded(child: _transactionInfoTile(icon: Icons.payments_outlined, label: 'PAID', value: '$paid', color: coffee)),
                      ]),
                      if (pendingPayment > 0) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB7791F)),
                          const SizedBox(width: 7),
                          Expanded(child: Text('$pendingPayment booking${pendingPayment == 1 ? '' : 's'} still have payment pending.', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w700))),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Your transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: text)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: ['All', 'Paid', 'Pending', 'In Progress', 'Completed', 'Cancelled'].map((filter) {
                    final selected = _bookingFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: selected,
                        selectedColor: coffee,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        side: BorderSide(color: selected ? coffee : Theme.of(context).dividerColor),
                        labelStyle: TextStyle(color: selected ? Colors.white : text, fontWeight: FontWeight.w700),
                        onSelected: (_) => setState(() => _bookingFilter = filter),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(children: [
                      const Icon(Icons.calendar_month_outlined, size: 44, color: coffee),
                      const SizedBox(height: 10),
                      Text('No bookings yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: text)),
                      const SizedBox(height: 4),
                      Text('Your cleaning service bookings will appear here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted)),
                    ]),
                  )
                else if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(children: [
                      Icon(Icons.filter_alt_off_rounded, size: 38, color: muted),
                      const SizedBox(height: 8),
                      Text('No $_bookingFilter bookings', style: TextStyle(fontWeight: FontWeight.w800, color: text)),
                      const SizedBox(height: 3),
                      Text('Try another transaction filter.', style: TextStyle(fontSize: 11, color: muted)),
                    ]),
                  )
                else
                  ...filtered.map(_bookingCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _transactionInfoTile({required IconData icon, required String label, required String value, required Color color}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A211E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: dark ? const Color(0xFF51413B) : const Color(0xFFE7D9CF)),
      ),
      child: Row(children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
        ])),
      ]),
    );
  }

Widget _pill(String value)=>Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(30)),
  // The pill has a light beige background in both themes, so keep its text dark.
  child: Text(value.toUpperCase(), style: TextStyle(
    color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink), fontSize: 10, fontWeight: FontWeight.bold,
  )),
);

} // end _BookingsPageState


class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onLogout;
  const ProfilePage({super.key, required this.profile, required this.onLogout});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _aboutOpen = false;
  bool _howToOpen = false;

  String _profileValue(String key, String fallback) {
    final value = widget.profile?[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  void _showEditProfile() {
    final name = TextEditingController(text: _profileValue('full_name', ''));
    final phone = TextEditingController(text: _profileValue('phone', ''));
    final address = TextEditingController(text: _profileValue('address', ''));
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 10),
            TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final user = supabase.auth.currentUser;
              if (user == null) return;
              try {
                final updated = await supabase.from('profiles').update({
                  'full_name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'address': address.text.trim(),
                }).eq('id', user.id).select().maybeSingle();
                if (!mounted) return;
                if (updated != null) {
                  setState(() => widget.profile?.addAll(Map<String, dynamic>.from(updated)));
                }
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update profile: $e')));
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final panelColor = isDark ? const Color(0xFF211B19) : const Color(0xFFFFFCF7);
        final primaryText = isDark ? const Color(0xFFF8F2EB) : const Color(0xFF243746);
        final secondaryText = isDark ? const Color(0xFFD8CFCB) : const Color(0xFF62534D);
        final iconColor = isDark ? const Color(0xFFFFB18F) : coffee;
        return Material(
          color: panelColor,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: appThemeMode,
              builder: (context, selectedMode, _) => Theme(
                data: Theme.of(sheetContext).copyWith(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  colorScheme: Theme.of(sheetContext).colorScheme.copyWith(
                    surface: panelColor,
                    onSurface: primaryText,
                    onSurfaceVariant: secondaryText,
                    primary: iconColor,
                  ),
                  textTheme: Theme.of(sheetContext).textTheme.apply(
                    bodyColor: primaryText,
                    displayColor: primaryText,
                  ),
                  radioTheme: RadioThemeData(
                    fillColor: WidgetStatePropertyAll(iconColor),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: primaryText)),
                      const SizedBox(height: 6),
                      Text('Theme mode', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: secondaryText)),
                      const SizedBox(height: 8),
                      RadioListTile<ThemeMode>(
                        contentPadding: EdgeInsets.zero,
                        activeColor: iconColor,
                        value: ThemeMode.system,
                        groupValue: selectedMode,
                        title: Text('System default', style: TextStyle(color: primaryText)),
                        secondary: Icon(Icons.settings_suggest_outlined, color: iconColor),
                        onChanged: (value) { if (value != null) appThemeMode.value = value; },
                      ),
                      RadioListTile<ThemeMode>(
                        contentPadding: EdgeInsets.zero,
                        activeColor: iconColor,
                        value: ThemeMode.light,
                        groupValue: selectedMode,
                        title: Text('Light', style: TextStyle(color: primaryText)),
                        secondary: Icon(Icons.light_mode_outlined, color: iconColor),
                        onChanged: (value) { if (value != null) appThemeMode.value = value; },
                      ),
                      RadioListTile<ThemeMode>(
                        contentPadding: EdgeInsets.zero,
                        activeColor: iconColor,
                        value: ThemeMode.dark,
                        groupValue: selectedMode,
                        title: Text('Dark', style: TextStyle(color: primaryText)),
                        secondary: Icon(Icons.dark_mode_outlined, color: iconColor),
                        onChanged: (value) { if (value != null) appThemeMode.value = value; },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _outlineAction({required IconData icon, required String label, required VoidCallback onTap, bool danger = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = danger ? Colors.red.shade400 : (isDark ? Colors.white : ink);
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Align(alignment: Alignment.centerLeft, child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: danger ? Colors.red.shade200 : const Color(0xFFD7CBC2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          padding: const EdgeInsets.symmetric(horizontal: 17),
        ),
      ),
    );
  }

  Widget _accordion({required IconData icon, required String title, required bool open, required VoidCallback onTap, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
              Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(48, 0, 18, 16), child: child),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final name = _profileValue('full_name', 'KLEENOVA Customer');
    final phone = _profileValue('phone', 'Phone not set');
    final address = _profileValue('address', 'Address not set');
    final roleRaw = widget.profile?['role']?.toString().trim() ?? '';
    final role = roleRaw.isEmpty
        ? 'Customer'
        : '${roleRaw[0].toUpperCase()}${roleRaw.substring(1)}';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF12171B) : const Color(0xFFF7F1EA);
    final card = isDark ? const Color(0xFF1B2227) : Colors.white;
    final navy = const Color(0xFF183D52);
    final terracotta = const Color(0xFFD66A48);
    final inkColor = isDark ? Colors.white : const Color(0xFF24313A);
    final muted = isDark ? const Color(0xFFB9C2C8) : const Color(0xFF6C747A);

    Widget infoTile(IconData icon, String label, String value) {
      return Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE9DDD3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? .08 : .035),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (icon == Icons.phone_outlined ? const Color(0xFFE9F3F4) : const Color(0xFFFFEEE6)),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 17, color: icon == Icons.phone_outlined ? const Color(0xFF247184) : terracotta),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), style: TextStyle(fontSize: 9, letterSpacing: .7, fontWeight: FontWeight.w800, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted))),
                    const SizedBox(height: 4),
                    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: inkColor, height: 1.2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget actionCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, bool danger = false}) {
      final accent = danger ? const Color(0xFFE45757) : navy;
      return Material(
        color: card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: danger ? const Color(0xFFF2BABA) : (isDark ? Colors.white10 : const Color(0xFFE9DDD3))),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: danger ? const Color(0xFFFFEAEA) : const Color(0xFFEAF1F4),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: danger ? const Color(0xFFD94D4D) : inkColor)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted))),
              ])),
              Icon(Icons.arrow_forward_ios_rounded, size: 15, color: muted),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 272,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF173E55), Color(0xFF236579), Color(0xFFD56A49)],
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Stack(children: [
              Positioned(right: -55, top: -60, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.07)))),
              Positioned(left: -75, bottom: -80, child: Container(width: 210, height: 210, decoration: BoxDecoration(shape: BoxShape.circle, color: terracotta.withOpacity(.18)))),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('My Profile', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))),
                      Material(
                        color: Colors.white.withOpacity(.13),
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          onTap: _showEditProfile,
                          borderRadius: BorderRadius.circular(13),
                          child: const Padding(padding: EdgeInsets.all(11), child: Icon(Icons.edit_rounded, color: Colors.white, size: 20)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 16, offset: const Offset(0, 8))],
                        ),
                        child: Icon(Icons.person_rounded, size: 43, color: navy),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
                          child: Text(role, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4)),
                        ),
                        if ((user?.email ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(user!.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.82), fontSize: 12)),
                        ],
                      ])),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(children: [
                Row(children: [
                  infoTile(Icons.phone_outlined, 'Phone', phone),
                  const SizedBox(width: 10),
                  infoTile(Icons.location_on_outlined, 'Address', address),
                ]),
                const SizedBox(height: 22),
                Align(alignment: Alignment.centerLeft, child: Text('Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: inkColor))),
                const SizedBox(height: 10),
                actionCard(icon: Icons.edit_rounded, title: 'Edit Profile', subtitle: 'Update your name, phone and address', onTap: _showEditProfile),
                const SizedBox(height: 10),
                actionCard(icon: Icons.tune_rounded, title: 'Settings', subtitle: 'Appearance and app preferences', onTap: _showSettings),
                const SizedBox(height: 22),
                Align(alignment: Alignment.centerLeft, child: Text('Help & Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: inkColor))),
                const SizedBox(height: 10),
                _accordion(icon: Icons.info_outline, title: 'About KLEENOVA', open: _aboutOpen, onTap: () => setState(() => _aboutOpen = !_aboutOpen), child: Text(
                  'KLEENOVA lets customers browse cleaning services, book a schedule, pay through QR Ph, receive booking updates, and review completed services.',
                  style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted), height: 1.45),
                )),
                _accordion(icon: Icons.help_outline, title: 'How to Use KLEENOVA', open: _howToOpen, onTap: () => setState(() => _howToOpen = !_howToOpen), child: Text(
                  'Choose a service, select your preferred date and time, enter your location, confirm the booking, then complete the QR Ph payment. Track updates under Bookings and Alerts.',
                  style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted), height: 1.45),
                )),
                const SizedBox(height: 8),
                actionCard(icon: Icons.logout_rounded, title: 'Log Out', subtitle: 'Sign out of this KLEENOVA account', onTap: widget.onLogout, danger: true),
                const SizedBox(height: 24),
                Text('KLEENOVA  •  CLEAN SPACES. BETTER DAYS.', style: TextStyle(fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w700, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted))),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCleanerDialog extends StatefulWidget {
  final Map<String, dynamic>? cleaner;
  const _AddCleanerDialog({this.cleaner});

  @override
  State<_AddCleanerDialog> createState() => _AddCleanerDialogState();
}

class _AddCleanerDialogState extends State<_AddCleanerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cleaner = widget.cleaner;
    if (cleaner != null) {
      _nameController.text = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? '').toString();
      _emailController.text = (cleaner['email'] ?? '').toString();
      _phoneController.text = (cleaner['phone'] ?? '').toString();
      _addressController.text = (cleaner['address'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(<String, String>{
      'full_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.cleaner == null ? 'Add cleaner' : 'Edit cleaner'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => v == null || v.trim().isEmpty ? "Enter the cleaner's full name" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Enter an email address';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter a phone number' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter an address' : null,
            ),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: Text(widget.cleaner == null ? 'Add cleaner' : 'Save changes')),
    ],
  );
}

class _ReportLinePainter extends CustomPainter {
  final List<int> values;
  final Color lineColor;
  final Color gridColor;
  const _ReportLinePainter({required this.values, required this.lineColor, required this.gridColor});
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b).toDouble();
    final maxY = maxValue <= 0 ? 1.0 : maxValue;
    final chart = Rect.fromLTWH(30, 8, size.width - 40, size.height - 34);
    final gridPaint = Paint()..color = gridColor.withOpacity(.55)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? chart.center.dx : chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - (values[i] / maxY) * chart.height;
      if (i == 0) { path.moveTo(x, y); fill.moveTo(x, chart.bottom); fill.lineTo(x, y); } else { path.lineTo(x, y); fill.lineTo(x, y); }
      if (i == values.length - 1) fill.lineTo(x, chart.bottom);
    }
    fill.close();
    canvas.drawPath(fill, Paint()..color = lineColor.withOpacity(.10));
    canvas.drawPath(path, Paint()..color = lineColor..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    final dot = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? chart.center.dx : chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - (values[i] / maxY) * chart.height;
      canvas.drawCircle(Offset(x, y), 3.5, dot);
    }
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final labels = values.length <= 7 ? values.length : 7;
    for (var j = 0; j < labels; j++) {
      final index = labels == 1 ? 0 : ((values.length - 1) * j / (labels - 1)).round();
      final x = values.length == 1 ? chart.center.dx : chart.left + chart.width * index / (values.length - 1);
      tp.text = TextSpan(text: '${index + 1}', style: const TextStyle(fontSize: 9, color: Color(0xFF81736C)));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 8));
    }
  }
  @override bool shouldRepaint(covariant _ReportLinePainter old) => old.values != values || old.lineColor != lineColor;
}

class _ReportBarPainter extends CustomPainter {
  final List<int> values;
  final Color barColor;
  final Color gridColor;
  const _ReportBarPainter({required this.values, required this.barColor, required this.gridColor});
  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(30, 8, size.width - 40, size.height - 34);
    final maxValue = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
    final gridPaint = Paint()..color = gridColor.withOpacity(.55)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    if (values.isEmpty) return;
    final gap = 8.0;
    final barWidth = ((chart.width - gap * (values.length + 1)) / values.length).clamp(8.0, 60.0).toDouble();
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + gap + i * (barWidth + gap);
      final h = maxValue == 0 ? 0.0 : chart.height * values[i] / maxValue;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, chart.bottom - h, barWidth, h), const Radius.circular(7));
      canvas.drawRRect(rect, Paint()..color = barColor);
      tp.text = TextSpan(text: 'W${i + 1}', style: const TextStyle(fontSize: 9, color: Color(0xFF81736C)));
      tp.layout();
      tp.paint(canvas, Offset(x + barWidth / 2 - tp.width / 2, chart.bottom + 8));
    }
  }
  @override bool shouldRepaint(covariant _ReportBarPainter old) => old.values != values || old.barColor != barColor;
}

class _ReportDonutPainter extends CustomPainter {
  final int active;
  final int completed;
  final int cancelled;
  const _ReportDonutPainter({required this.active, required this.completed, required this.cancelled});
  @override
  void paint(Canvas canvas, Size size) {
    final total = active + completed + cancelled;
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 18..strokeCap = StrokeCap.butt..color = const Color(0xFFEDE3DA);
    canvas.drawArc(rect, 0, 6.28318, false, base);
    if (total == 0) return;
    final paints = [Paint()..style = PaintingStyle.stroke..strokeWidth = 18..color = deepSage, Paint()..style = PaintingStyle.stroke..strokeWidth = 18..color = sage, Paint()..style = PaintingStyle.stroke..strokeWidth = 18..color = coral];
    final vals = [active, completed, cancelled];
    var start = -1.5708;
    for (var i = 0; i < vals.length; i++) {
      if (vals[i] == 0) continue;
      final sweep = 6.28318 * vals[i] / total;
      canvas.drawArc(rect, start, sweep, false, paints[i]);
      start += sweep;
    }
  }
  @override bool shouldRepaint(covariant _ReportDonutPainter old) => old.active != active || old.completed != completed || old.cancelled != cancelled;
}


class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override State<AdminPage> createState() => _AdminPageState();
}


class _AdminPageState extends State<AdminPage> {
  Timer? _autoRefreshTimer;
  RealtimeChannel? _adminRealtimeChannel;
  bool _autoRefreshing = false;

  static const _sections = <String, IconData>{
    'Overview': Icons.home_outlined,
    'Users': Icons.people_outline,
    'Bookings': Icons.calendar_month_outlined,
    'Cleaners': Icons.people_alt_outlined,
    'Services': Icons.cleaning_services_outlined,
    'Payments': Icons.payment_outlined,
    'Notifications': Icons.notifications_none,
    'Reviews': Icons.star_outline,
    'Reports': Icons.bar_chart_rounded,
    'Reschedule Requests': Icons.event_repeat_rounded,
    'Activity Log': Icons.history_toggle_off_rounded,
  };

  String section = 'Overview';
  late Future<List<Map<String, dynamic>>> bookingsFuture;
  late Future<List<Map<String, dynamic>>> servicesFuture;
  Future<List<Map<String, dynamic>>> cleanersFuture = Future.value(<Map<String, dynamic>>[]);
  late Future<List<Map<String, dynamic>>> usersFuture;
  late Future<List<Map<String, dynamic>>> notificationsFuture;
  late Future<List<Map<String, dynamic>>> reviewsFuture;
  String reviewServiceFilter = 'All services';
  String reviewRatingFilter = 'All ratings';
  // Show the complete active queue by default; admins can narrow it with status/date/search.
  String bookingStatusFilter = 'All';
  String paymentStatusFilter = 'All';
  final TextEditingController adminBookingSearchController = TextEditingController();
  String adminBookingSearch = '';
  final TextEditingController bookingHistorySearchController = TextEditingController();
  String bookingHistorySearch = '';
  DateTime? bookingDateFilter;
  String adminNotificationFilter = 'All';

  // Red notification counts shown beside admin navigation items.
  int bookingHistoryBadgeCount = 0;
  int reviewsBadgeCount = 0;
  int reportsBadgeCount = 0;
  int rescheduleBadgeCount = 0;
  int activityLogBadgeCount = 0;
  int _unreadBookingNotificationCount = 0;
  int _unreadPaymentNotificationCount = 0;
  // Counts already acknowledged by the admin for the current booking lists.
  int _pendingBookingsAcknowledged = 0;
  int _cancelledBookingsAcknowledged = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    // Listen for live changes. The 10-second refresh remains as a fallback if
    // Realtime is not enabled for a table in Supabase.
    final adminId = supabase.auth.currentUser?.id;
    if (adminId != null) {
      _adminRealtimeChannel = supabase.channel('kleenova-admin-live-$adminId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: adminId,
          ),
          callback: (_) => _silentAutoRefresh(),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _silentAutoRefresh(),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'admin_activity_logs',
          callback: (_) => _refreshAdminBadgeCounts(),
        )
        ..subscribe();
    }
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentAutoRefresh());
  }

  Future<void> _silentAutoRefresh() async {
    if (!mounted || _autoRefreshing) return;
    _autoRefreshing = true;
    try {
      final nextBookings = _loadBookings();
      final nextServices = _loadServices();
      final nextCleaners = _loadCleaners();
      final nextUsers = _loadUsers();
      final nextNotifications = _loadNotifications();
      final nextReviews = _loadReviews();
      final results = await Future.wait([
        nextBookings,
        nextServices,
        nextCleaners,
        nextUsers,
        nextNotifications,
        nextReviews,
      ]);
      if (!mounted) return;
      setState(() {
        bookingsFuture = Future.value(List<Map<String, dynamic>>.from(results[0] as List));
        servicesFuture = Future.value(List<Map<String, dynamic>>.from(results[1] as List));
        cleanersFuture = Future.value(List<Map<String, dynamic>>.from(results[2] as List));
        usersFuture = Future.value(List<Map<String, dynamic>>.from(results[3] as List));
        notificationsFuture = Future.value(List<Map<String, dynamic>>.from(results[4] as List));
        reviewsFuture = Future.value(List<Map<String, dynamic>>.from(results[5] as List));
      });
      _refreshAdminBadgeCounts();
    } catch (_) {
      // Keep the existing screen data if a background refresh fails.
    } finally {
      _autoRefreshing = false;
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    final channel = _adminRealtimeChannel;
    if (channel != null) supabase.removeChannel(channel);
    adminBookingSearchController.dispose();
    bookingHistorySearchController.dispose();
    super.dispose();
  }

  void _reload() {
    bookingsFuture = _loadBookings();
    servicesFuture = _loadServices();
    cleanersFuture = _loadCleaners();
    usersFuture = _loadUsers();
    notificationsFuture = _loadNotifications();
    reviewsFuture = _loadReviews();
    _refreshAdminBadgeCounts();
  }

  Future<void> _refreshAdminBadgeCounts() async {
    try {
      final data = await Future.wait<List<Map<String, dynamic>>>([
        bookingsFuture,
        reviewsFuture,
        _loadRescheduleRequests(),
        _loadActivityLogs(),
      ]);

      final bookings = data[0];
      final reviews = data[1];
      final rescheduleRequests = data[2];
      final activityLogs = data[3];
      final ownNotifications = await _loadNotifications();
      // Booking and payment acknowledgement states are independent from the
      // general notification read state. Requires the two columns in the SQL
      // migration supplied alongside this file.
      bool isPaymentAlert(Map<String, dynamic> n) {
        final type = (n['type'] ?? '').toString().toLowerCase();
        final title = (n['title'] ?? '').toString().toLowerCase();
        final message = (n['message'] ?? '').toString().toLowerCase();
        return type == 'payment' || title.contains('payment') || title.contains('paid') ||
            message.contains('payment') || message.contains('paid');
      }
      final unreadBookingRows = ownNotifications.where((n) =>
          (n['type'] ?? '').toString().toLowerCase() == 'booking' &&
          n['booking_is_read'] != true && !isPaymentAlert(n)).toList();
      final unreadPaymentRows = ownNotifications.where((n) =>
          isPaymentAlert(n) && n['payment_is_read'] != true).toList();
      int uniqueBookingCount(List<Map<String, dynamic>> rows) => rows
          .map((n) => (n['booking_id'] ?? n['id']).toString())
          .where((id) => id.isNotEmpty).toSet().length;
      final unreadBookingNotifications = uniqueBookingCount(unreadBookingRows);
      final unreadPaymentNotifications = uniqueBookingCount(unreadPaymentRows);

      final pendingReschedules = rescheduleRequests.where((r) =>
          (r['status'] ?? 'pending').toString().toLowerCase() == 'pending').length;
      final unreadHistory = bookings.where((b) =>
          b['history_is_read'] != true &&
          (b['status'] ?? '').toString().toLowerCase() == 'completed').length;
      final unreadReviews = reviews.where((r) => r['is_read'] != true).length;
      final unreadReschedules = rescheduleRequests.where((r) => r['is_read'] != true).length;
      final unreadActivity = activityLogs.where((r) => r['is_read'] != true).length;

      if (!mounted) return;
      setState(() {
        bookingHistoryBadgeCount = unreadHistory;
        reviewsBadgeCount = unreadReviews;
        reportsBadgeCount = 0;
        rescheduleBadgeCount = unreadReschedules;
        activityLogBadgeCount = unreadActivity;
        _unreadBookingNotificationCount = unreadBookingNotifications;
        _unreadPaymentNotificationCount = unreadPaymentNotifications;
      });
    } catch (_) {
      // Badge counts are supplemental; keep the admin screen usable if one
      // of the optional count queries fails.
    }
  }

  Future<List<Map<String, dynamic>>> _loadBookings({bool includeDeleted = false}) async {
    dynamic raw;
    try {
      final query = supabase.from('bookings').select();
      raw = includeDeleted
          ? await query.order('created_at', ascending: false)
          : await query.isFilter('admin_deleted_at', null).order('created_at', ascending: false);
    } catch (_) {
      // Keep the admin screen usable with older/legacy booking schemas.
      // Reports can include archived rows; normal admin lists hide them.
      final query = supabase.from('bookings').select();
      raw = includeDeleted ? await query : await query.isFilter('admin_deleted_at', null);
    }

    final rows = raw is List
        ? raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : <Map<String, dynamic>>[];
    final ids = rows.map((b) => b['customer_id']?.toString()).whereType<String>()
        .where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isNotEmpty) {
      try {
        final profiles = await supabase.from('profiles')
            .select('id, full_name, email, phone').inFilter('id', ids);
        final profileList = profiles is List
            ? profiles.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
            : <Map<String, dynamic>>[];
        final byId = <String, Map<String, dynamic>>{
          for (final profile in profileList)
            profile['id']?.toString() ?? '': profile,
        }..remove('');
        for (final booking in rows) {
          final profile = byId[booking['customer_id']?.toString()];
          if (profile != null) {
            booking['customer_name'] = profile['full_name'];
            booking['customer_email'] = profile['email'];
            booking['customer_phone'] = profile['phone'];
          }
        }
      } catch (_) {}
    }
    try {
      final cleanerRows = await supabase.from('cleaners').select();
      final cleanerMap = <String, String>{};
      for (final cleaner in (cleanerRows is List
          ? cleanerRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
          : const <Map<String, dynamic>>[])) {
        final id = cleaner['id']?.toString();
        if (id != null) cleanerMap[id] = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? 'Cleaner').toString();
      }
      for (final booking in rows) {
        final ids = <String>{};
        final multiIds = booking['cleaner_ids'];
        if (multiIds is List) ids.addAll(multiIds.map((id) => id.toString()));
        final singleId = booking['cleaner_id']?.toString();
        if (singleId != null && singleId.isNotEmpty) ids.add(singleId);
        final names = ids.map((id) => cleanerMap[id]).whereType<String>().toList();
        booking['cleaner_names'] = names;
        booking['cleaner_name'] = names.join(', ');
      }
    } catch (_) {}
    try {
      // Unread state is private to the currently signed-in admin.
      final currentAdmin = supabase.auth.currentUser;
      if (currentAdmin != null) {
        final unreadRows = await supabase.from('notifications')
            .select('booking_id, user_id, type, title, message, booking_is_read, payment_is_read')
            .eq('user_id', currentAdmin.id);
        final unreadBookingIds = <String>{};
        final unreadPaymentIds = <String>{};
        for (final n in List<Map<String, dynamic>>.from(unreadRows)) {
          final id = n['booking_id']?.toString();
          if (id == null || id.isEmpty) continue;
          final type = (n['type'] ?? '').toString().toLowerCase();
          final title = (n['title'] ?? '').toString().toLowerCase();
          final message = (n['message'] ?? '').toString().toLowerCase();
          final paymentAlert = type == 'payment' || title.contains('payment') ||
              title.contains('paid') || message.contains('payment') || message.contains('paid');
          if (paymentAlert) {
            if (n['payment_is_read'] != true) unreadPaymentIds.add(id);
          } else if (type == 'booking' && n['booking_is_read'] != true) {
            unreadBookingIds.add(id);
          }
        }
        for (final booking in rows) {
          final id = booking['id']?.toString();
          booking['_admin_unread'] = id != null && unreadBookingIds.contains(id);
          booking['_admin_payment_unread'] = id != null && unreadPaymentIds.contains(id);
        }
      }
    } catch (_) {}
    return rows;
  }
  Future<List<Map<String, dynamic>>> _loadServices() =>
      supabase.from('services').select().order('created_at', ascending: false);
  Future<List<Map<String, dynamic>>> _loadCleaners() async {
    List<Map<String, dynamic>> cleaners;
    try {
      final data = await supabase.from('cleaners').select().order('created_at', ascending: false);
      cleaners = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      final data = await supabase.from('cleaners').select();
      cleaners = List<Map<String, dynamic>>.from(data);
    }

    final assignedIds = <String>{};
    try {
      final bookings = await supabase.from('bookings').select();
      for (final booking in List<Map<String, dynamic>>.from(bookings)) {
        final status = (booking['status'] ?? '').toString().toLowerCase();
        if (status == 'completed' || status == 'cancelled' || status == 'canceled') continue;
        final legacyId = booking['cleaner_id']?.toString();
        if (legacyId != null && legacyId.isNotEmpty) assignedIds.add(legacyId);
        final ids = booking['cleaner_ids'];
        if (ids is List) assignedIds.addAll(ids.map((id) => id.toString()));
      }
    } catch (_) {}

    for (final cleaner in cleaners) {
      cleaner['_assignment_status'] =
          assignedIds.contains(cleaner['id']?.toString()) ? 'Assigned' : 'Available';
    }
    return cleaners;
  }
  Future<List<Map<String, dynamic>>> _loadUsers() =>
      supabase.from('profiles').select().order('created_at', ascending: false);
  Future<List<Map<String, dynamic>>> _loadNotifications() async {
    // Admin notifications are private to the signed-in admin account.
    // Do not load customer notifications into the admin panel.
    final user = supabase.auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(
      await supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false),
    );
  }
  Future<List<Map<String, dynamic>>> _loadReviews() async {
    final reviewRows = await supabase
        .from('reviews')
        .select('id, booking_id, service_id, service_name, customer_id, rating, comment, created_at, is_read, read_at')
        .order('created_at', ascending: false);
    final reviews = List<Map<String, dynamic>>.from(reviewRows);
    if (reviews.isEmpty) return reviews;

    final customerIds = reviews.map((r) => r['customer_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
    final bookingIds = reviews.map((r) => r['booking_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList();

    final names = <String, String>{};
    final bookingDetails = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      try {
        final rows = await supabase.from('profiles').select('id, full_name')
            .inFilter('id', customerIds);
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          names[row['id'].toString()] = (row['full_name'] ?? 'KLEENOVA customer').toString();
        }
      } catch (_) {}
    }
    if (bookingIds.isNotEmpty) {
      try {
        final rows = await supabase.from('bookings')
            .select('id, service_name, booking_date, booking_time')
            .inFilter('id', bookingIds);
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          bookingDetails[row['id'].toString()] = row;
        }
      } catch (_) {}
    }

    for (final review in reviews) {
      final customerId = review['customer_id']?.toString() ?? '';
      final bookingId = review['booking_id']?.toString() ?? '';
      final booking = bookingDetails[bookingId] ?? <String, dynamic>{};
      review['reviewer_name'] = names[customerId] ?? 'KLEENOVA customer';
      review['service_name'] = review['service_name'] ?? booking['service_name'] ?? 'Cleaning service';
      review['booking_date'] = booking['booking_date'];
      review['booking_time'] = booking['booking_time'];
    }
    return reviews;
  }

  void refresh() => setState(_reload);

  Future<void> _logAdminActivity(String action, String entityType, String? entityId, [Map<String, dynamic>? details]) async {
    try {
      final user = supabase.auth.currentUser;
      await supabase.from('admin_activity_logs').insert({
        'admin_id': user?.id,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details ?? <String, dynamic>{},
      });
    } catch (_) {
      // Activity logging must not block the primary admin action.
    }
  }

  Future<void> status(String id, String value) async {
    final normalized = value.toLowerCase();
    final isComplete = normalized == 'completed';
    final isCancel = normalized == 'cancelled' || normalized == 'canceled';

    if (isComplete || isCancel) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(isComplete ? 'Complete this booking?' : 'Cancel this booking?'),
          content: Text(isComplete
              ? 'Please confirm that this cleaning booking has been completed.'
              : 'Are you sure you want to cancel this booking? This will notify the customer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              style: isCancel ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isComplete ? 'Yes, complete' : 'Yes, cancel'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final booking = await supabase
          .from('bookings')
          .select('customer_id, service_name')
          .eq('id', id)
          .maybeSingle();
      final updated = await supabase
          .from('bookings')
          .update({'status': value})
          .eq('id', id)
          .select('id,status')
          .maybeSingle();
      if (updated == null) {
        throw Exception('The booking status was not updated. Please refresh and try again.');
      }

      await _logAdminActivity('Changed booking status to $value', 'booking', id, {'status': value});
      final customerId = booking?['customer_id']?.toString();
      final serviceName = (booking?['service_name'] ?? 'cleaning').toString();
      if (customerId != null && customerId.isNotEmpty) {
        try {
          await createKleenovaNotification(
            userId: customerId,
            title: isComplete
                ? 'Booking completed!'
                : isCancel
                    ? 'Booking cancelled'
                    : normalized == 'in_progress'
                        ? 'Your cleaning is in progress!'
                        : 'Booking update',
            message: isComplete
                ? 'Your $serviceName service has been completed successfully. Thank you for choosing KLEENOVA!'
                : isCancel
                    ? 'Your $serviceName booking has been cancelled by the KLEENOVA admin. Please contact us if you have questions.'
                    : normalized == 'in_progress'
                        ? 'Good news! Your $serviceName booking is now in progress.'
                        : 'Your $serviceName booking status is now ${_prettyValue(value)}.',
            type: 'booking',
            bookingId: id,
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          bookingsFuture = _loadBookings();
          cleanersFuture = _loadCleaners();
          notificationsFuture = _loadNotifications();
        });
        _message(isComplete
            ? 'Booking completed successfully. The customer has been notified.'
            : isCancel
                ? 'Booking cancelled successfully. The customer has been notified.'
                : 'Booking status updated successfully.');
      }
    } catch (e) {
      if (mounted) _message('Update failed: $e');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> addService() async {
    final added = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const ServiceEditorPage()));
    if (added == true && mounted) setState(() { servicesFuture = _loadServices(); });
  }

  Future<void> editService(Map<String, dynamic> service) async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => ServiceEditorPage(service: service)));
    if (updated == true && mounted) setState(() { servicesFuture = _loadServices(); });
  }

  Future<void> addCleaner() async {
    // Keep the form and its controllers in a dedicated widget so they remain
    // alive for the entire dialog route lifecycle.
    final details = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddCleanerDialog(),
    );
    if (details == null || !mounted) return;
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Add cleaner?',
      message: 'Are you sure you want to add this cleaner?',
      confirmLabel: 'Yes, add',
      cancelLabel: 'No',
    );
    if (!confirmed) return;

    try {
      try {
        await supabase.from('cleaners').insert(details);
      } catch (_) {
        // Support schemas that use `name` or `cleaner_name` for the name field.
        final payload = Map<String, String>.from(details);
        payload['name'] = payload.remove('full_name')!;
        try {
          await supabase.from('cleaners').insert(payload);
        } catch (_) {
          final alternate = Map<String, String>.from(details);
          alternate['cleaner_name'] = alternate.remove('full_name')!;
          await supabase.from('cleaners').insert(alternate);
        }
      }
      if (mounted) {
        setState(() { cleanersFuture = _loadCleaners(); });
        _message('Cleaner added. You can now assign them to a booking.');
      }
    } catch (e) {
      if (mounted) _message('Could not add cleaner: $e');
    }
  }

  Future<void> editCleaner(Map<String, dynamic> cleaner) async {
    final details = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddCleanerDialog(cleaner: cleaner),
    );
    if (details == null || !mounted) return;
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Save cleaner changes?',
      message: 'Are you sure you want to save these cleaner details?',
      confirmLabel: 'Yes, save',
      cancelLabel: 'No',
    );
    if (!confirmed) return;

    try {
      try {
        await supabase.from('cleaners').update(details).eq('id', cleaner['id']);
      } catch (_) {
        final payload = Map<String, String>.from(details);
        payload['name'] = payload.remove('full_name')!;
        try {
          await supabase.from('cleaners').update(payload).eq('id', cleaner['id']);
        } catch (_) {
          final alternate = Map<String, String>.from(details);
          alternate['cleaner_name'] = alternate.remove('full_name')!;
          await supabase.from('cleaners').update(alternate).eq('id', cleaner['id']);
        }
      }
      if (mounted) {
        setState(() {
          cleanersFuture = _loadCleaners();
          bookingsFuture = _loadBookings();
        });
        _message('Cleaner details updated.');
      }
    } catch (e) {
      if (mounted) _message('Could not update cleaner: $e');
    }
  }

  Future<void> deleteCleaner(Map<String, dynamic> cleaner) async {
    final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? 'this cleaner').toString();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete cleaner?'),
      content: Text('Remove $name from the cleaner list?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try {
      await supabase.from('cleaners').delete().eq('id', cleaner['id']);
      if (mounted) {
        setState(() { cleanersFuture = _loadCleaners(); bookingsFuture = _loadBookings(); });
        _message('Cleaner deleted.');
      }
    } catch (e) {
      if (mounted) _message('Could not delete cleaner: $e');
    }
  }

  Future<void> deleteService(Map<String, dynamic> service) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Delete service?'),
      content: Text('Remove “${service['name']}” from your service list?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Keep')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try {
      await supabase.from('services').delete().eq('id', service['id']);
      if (mounted) setState(() { servicesFuture = _loadServices(); });
    } catch (e) {
      if (mounted) _message('Could not delete service: $e');
    }
  }

  void _selectSection(String value) {
    // Opening or switching admin sections must NEVER mark notifications as read.
    // Unread badges remain until the admin explicitly presses Mark as read.
    Navigator.of(context).maybePop();
    setState(() => section = value);
  }

  Future<void> _markSectionRead(String value) async {
    try {
      switch (value) {
        case 'Notifications':
          final user = supabase.auth.currentUser;
          if (user != null) {
            await supabase.from('notifications').update({
              'is_read': true,
              'read_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('user_id', user.id).eq('is_read', false);
          }
          break;
        case 'Bookings':
          // Booking acknowledgements are handled per booking in the Bookings section.
          break;
        case 'Payments':
          // Payment acknowledgements are handled per payment in the Payments section.
          break;
        case 'Booking History':
          await supabase.from('bookings').update({
            'history_is_read': true,
            'history_read_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('status', 'completed').eq('history_is_read', false);
          break;
        case 'Reviews':
          await supabase.from('reviews').update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('is_read', false);
          break;
        case 'Reschedule Requests':
          await supabase.from('booking_reschedule_requests').update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('is_read', false);
          break;
        case 'Activity Log':
          final updated = await supabase
              .from('admin_activity_logs')
              .update({
                'is_read': true,
                'read_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('is_read', false)
              .select('id, is_read, read_at');

          // If Supabase returned no updated rows, verify whether unread rows
          // still exist. This prevents the UI badge from being cleared when
          // the database update was silently blocked by RLS.
          if (updated.isEmpty) {
            final remaining = await supabase
                .from('admin_activity_logs')
                .select('id')
                .eq('is_read', false)
                .limit(1);
            if (remaining.isNotEmpty) {
              throw Exception(
                'Activity logs could not be marked as read. Check the admin_activity_logs UPDATE policy.',
              );
            }
          }
          break;
        case 'Reports':
          // Reports are informational, not unread notifications; keep the badge cleared.
          break;
      }
      if (!mounted) return;
      setState(() {
        if (value == 'Notifications') {} else if (value == 'Booking History') bookingHistoryBadgeCount = 0;
        else if (value == 'Reviews') reviewsBadgeCount = 0;
        else if (value == 'Reschedule Requests') rescheduleBadgeCount = 0;
        else if (value == 'Activity Log') activityLogBadgeCount = 0;
        else if (value == 'Reports') reportsBadgeCount = 0;
      });
      _refreshAdminBadgeCounts();
    } catch (e) {
      if (mounted) _message('Could not mark $value as read: $e');
    }
  }

  Future<void> _markAllBookingNotificationsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Your admin session has expired. Please sign in again.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await supabase
        .from('notifications')
        .update({'is_read': true, 'read_at': now})
        .eq('user_id', user.id)
        .eq('is_read', false)
        .eq('type', 'booking');

    // Read back the signed-in admin's rows. If RLS blocked the update,
    // keep the badge honest and show a useful error instead of clearing it
    // temporarily and letting it return after the next login.
    final remaining = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_read', false)
        .eq('type', 'booking')
        .limit(1);

    if (remaining.isNotEmpty) {
      throw Exception(
        'Booking notifications could not be saved as read. Check the notifications UPDATE policy in Supabase (RLS).',
      );
    }
  }

  Future<void> _markAllForSection(String value) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      switch (value) {
        case 'Notifications':
          final user = supabase.auth.currentUser;
          if (user != null) await supabase.from('notifications').update({'is_read': true, 'read_at': now}).eq('user_id', user.id).eq('is_read', false);
          break;
        case 'Bookings':
          // Booking acknowledgements are handled per booking in the Bookings section.
          break;
        case 'Payments':
          // Payment acknowledgements are handled per payment in the Payments section.
          break;
        case 'Booking History':
          await supabase.from('bookings').update({'history_is_read': true, 'history_read_at': now}).eq('status', 'completed').eq('history_is_read', false);
          break;
        case 'Reviews':
          await supabase.from('reviews').update({'is_read': true, 'read_at': now}).eq('is_read', false);
          break;
        case 'Reschedule Requests':
          await supabase.from('booking_reschedule_requests').update({'is_read': true, 'read_at': now}).eq('is_read', false);
          break;
        case 'Activity Log':
          final updated = await supabase
              .from('admin_activity_logs')
              .update({'is_read': true, 'read_at': now})
              .eq('is_read', false)
              .select('id, is_read, read_at');
          if (updated.isEmpty) {
            // Nothing to update is also valid when there are no unread logs.
            final remaining = await supabase
                .from('admin_activity_logs')
                .select('id')
                .eq('is_read', false)
                .limit(1);
            if (remaining.isNotEmpty) {
              throw Exception('Activity logs could not be marked as read. Check the admin_activity_logs UPDATE policy.');
            }
          }
          break;
        default: return;
      }
      if (mounted) {
        setState(() {
          if (value == 'Booking History') bookingHistoryBadgeCount = 0;
          if (value == 'Reviews') reviewsBadgeCount = 0;
          if (value == 'Reschedule Requests') rescheduleBadgeCount = 0;
          if (value == 'Activity Log') activityLogBadgeCount = 0;
          if (value == 'Reports') reportsBadgeCount = 0;
        });
        _reloadSectionData();
        if (value == 'Activity Log') {
          // Force a fresh query so the cards immediately reflect is_read=true.
          _reloadActivityLogSection();
        }
        _refreshAdminBadgeCounts();
        _message('All ${value == 'Booking History' ? 'booking history' : value.toLowerCase()} marked as read.');
      }
    } catch (e) { if (mounted) _message('Could not mark all as read: $e'); }
  }

  void _reloadActivityLogSection() {
    if (!mounted || section != 'Activity Log') return;
    setState(() {});
  }

  void _reloadSectionData() {
    if (!mounted) return;
    setState(() {
      if (section == 'Notifications') notificationsFuture = _loadNotifications();
      if (section == 'Reviews') reviewsFuture = _loadReviews();
      if (section == 'Bookings' || section == 'Booking History' || section == 'Payments' || section == 'Reports') bookingsFuture = _loadBookings();
    });
  }

  Widget _drawer({double width = 375}) => Drawer(
    width: width,
    backgroundColor: const Color(0xFF0B4A5F),
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    child: SafeArea(
      child: Column(
        children: [
          // KLEENOVA brand header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
            child: Column(
              children: [
                const KleenovaBrand(size: 30, onDark: true),
                const SizedBox(height: 8),
                Text(
                  'Admin Dashboard',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0x24FFFFFF)),

          // Main navigation
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: notificationsFuture,
              builder: (context, snapshot) {
                final notifications = _deduplicateAdminNotifications(snapshot.data ?? const <Map<String, dynamic>>[]);
                final unread = notifications.where((n) => n['is_read'] != true).toList();
                final unreadTotal = unread.length;
                final unreadBookingCount = _unreadBookingNotificationCount;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  children: [
                    for (final item in _sections.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(17),
                            onTap: () => _selectSection(item.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 50,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: section == item.key
                                    ? const LinearGradient(colors: [Color(0xFF2BA5BC), Color(0xFF1B8AA0)])
                                    : null,
                                color: section == item.key
                                    ? null
                                    : (item.key == 'Booking History' && bookingHistoryBadgeCount > 0
                                        ? const Color(0xFFFFE4E4)
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(17),
                                border: item.key == 'Booking History' && bookingHistoryBadgeCount > 0 && section != item.key
                                    ? Border.all(color: const Color(0xFFE53935), width: 1.2)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.value,
                                    size: 22,
                                    color: section == item.key
                                        ? Colors.white
                                        : (item.key == 'Booking History' && bookingHistoryBadgeCount > 0
                                            ? const Color(0xFFC62828)
                                            : Colors.white70),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      item.key,
                                      style: TextStyle(
                                        color: section == item.key
                                            ? Colors.white
                                            : (item.key == 'Booking History' && bookingHistoryBadgeCount > 0
                                                ? const Color(0xFFC62828)
                                                : Colors.white),
                                        fontSize: 14.5,
                                        fontWeight: section == item.key
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (item.key == 'Notifications' && unreadTotal > 0)
                                    _adminBadge(unreadTotal),
                                  if (item.key == 'Bookings' && unreadBookingCount > 0)
                                    _adminBadge(unreadBookingCount),
                                  if (item.key == 'Booking History' && bookingHistoryBadgeCount > 0)
                                    _adminBadge(bookingHistoryBadgeCount),
                                  if (item.key == 'Reviews' && reviewsBadgeCount > 0)
                                    _adminBadge(reviewsBadgeCount),
                                  if (item.key == 'Reports' && reportsBadgeCount > 0)
                                    _adminBadge(reportsBadgeCount),
                                  if (item.key == 'Reschedule Requests' && rescheduleBadgeCount > 0)
                                    _adminBadge(rescheduleBadgeCount),
                                  if (item.key == 'Activity Log' && activityLogBadgeCount > 0)
                                    _adminBadge(activityLogBadgeCount),
                                  if (item.key == 'Payments' && _unreadPaymentNotificationCount > 0)
                                    _adminBadge(_unreadPaymentNotificationCount),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // Footer / logout area
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () async {
                      try {
                        appThemeMode.value = ThemeMode.light;
                        await supabase.auth.signOut(scope: SignOutScope.local);
                        if (!mounted) return;
                        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                          MaterialPageRoute<void>(builder: (_) => const AuthGate()),
                          (route) => false,
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not log out. Please try again. ($e)')),
                        );
                      }
                    },
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: const [
                          Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                          SizedBox(width: 18),
                          Text(
                            'Log out',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Clean spaces, happier lives.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _adminBadge(int count) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.redAccent,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );

  Widget _panel({required String title, required Future<List<Map<String, dynamic>>> future,
      required String emptyText, required Widget Function(Map<String, dynamic>) itemBuilder}) =>
    FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      if (snapshot.hasError) return _errorCard('Could not load $title: ${snapshot.error}');
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return _emptyCard(emptyText);
      return Column(children: rows.map(itemBuilder).toList());
    });

  Widget _errorCard(String text) => Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: _cardDecoration(), child: Text(text, style: TextStyle(color: Colors.redAccent)));
  Widget _emptyCard(String text) => Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: _cardDecoration(), child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
  BoxDecoration _cardDecoration() => BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: beige));

  String _adminBookingStatus(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? 'pending').toString().trim().toLowerCase();
    final cleanerIds = booking['cleaner_ids'];
    final hasCleanerIds = cleanerIds is List && cleanerIds.any((id) => id.toString().trim().isNotEmpty);
    final hasCleanerId = (booking['cleaner_id'] ?? '').toString().trim().isNotEmpty;
    final hasCleanerName = (booking['cleaner_names'] is List &&
            (booking['cleaner_names'] as List).any((name) => name.toString().trim().isNotEmpty)) ||
        (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '').toString().trim().isNotEmpty;
    final hasAssignedCleaner = hasCleanerIds || hasCleanerId || hasCleanerName;

    if (status == 'completed' || status == 'cancelled' || status == 'canceled') {
      return status == 'canceled' ? 'cancelled' : status;
    }
    if (status == 'currently_cleaning' || status == 'on_the_way' || status == 'in_progress') return status;
    if (hasAssignedCleaner && (status == 'pending' || status.isEmpty || status == 'confirmed')) return 'in_progress';
    return status;
  }

  String _bookingStatus(Map<String, dynamic> b) =>
      _prettyValue(_adminBookingStatus(b));

  String _bookingDateTime(Map<String, dynamic> b) {
    final date = (b['booking_date'] ?? '').toString();
    final time = (b['booking_time'] ?? '').toString();
    return [date, time].where((v) => v.isNotEmpty).join(' • ');
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final unread = section == 'Booking History' ? b['history_is_read'] != true : b['_admin_unread'] == true;
    final status = _adminBookingStatus(b);
    final payment = (b['payment_status'] ?? 'pending').toString().toLowerCase();
    final customer = (b['customer_name'] ?? 'KLEENOVA customer').toString();
    final service = (b['service_name'] ?? 'Cleaning service').toString();
    final amount = (b['service_price'] as num?)?.toDouble() ?? 0;
    final bookingId = b['id']?.toString() ?? '';
    final shortId = bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId;
    final location = [(b['barangay'] ?? '').toString(), (b['municipality'] ?? '').toString()]
        .where((v) => v.trim().isNotEmpty).join(', ');
    final cleanerNames = <String>[];
    if (b['cleaner_names'] is List) {
      cleanerNames.addAll((b['cleaner_names'] as List).map((v) => v.toString().trim()).where((v) => v.isNotEmpty));
    }
    final oldCleaner = (b['cleaner_name'] ?? b['assigned_cleaner_name'] ?? '').toString().trim();
    if (cleanerNames.isEmpty && oldCleaner.isNotEmpty) cleanerNames.add(oldCleaner);

    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    final isInProgress = ['in_progress', 'currently_cleaning', 'on_the_way'].contains(status);
    final statusColor = isCompleted ? const Color(0xFF2E7D32)
        : isCancelled ? const Color(0xFFC94B4B)
        : isInProgress || status == 'confirmed' ? const Color(0xFF176B87)
        : const Color(0xFFB7791F);
    final statusLabel = isCompleted ? 'Completed'
        : isCancelled ? 'Cancelled'
        : isInProgress ? 'Cleaning in progress'
        : status == 'confirmed' ? 'Confirmed'
        : 'Pending';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final text = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unread ? (dark ? const Color(0xFF263A2A) : const Color(0xFFF0FAF1)) : surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: unread ? const Color(0xFF78B67E) : (dark ? const Color(0xFF51413B) : const Color(0xFFE5D7CC)), width: unread ? 1.6 : 1),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: dark ? const Color(0xFF3B302C) : const Color(0xFFF1E1D6), borderRadius: BorderRadius.circular(15)),
            alignment: Alignment.center,
            child: const Icon(Icons.cleaning_services_rounded, color: coffee, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, color: text))),
              if (unread) ...[
                const SizedBox(width: 7),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
              ],
            ]),
            const SizedBox(height: 3),
            Text(service, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('Booking #$shortId', style: TextStyle(color: muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ])),
        ]),
        const SizedBox(height: 13),

        // Status and payment intentionally use separate labels so staff do not
        // confuse the service progress with the payment state.
        Row(children: [
          Expanded(child: _adminTransactionBadge(
            label: 'BOOKING STATUS', value: statusLabel, icon: isCompleted ? Icons.check_circle_rounded : isCancelled ? Icons.cancel_outlined : isInProgress ? Icons.cleaning_services_rounded : Icons.schedule_rounded, color: statusColor)),
          const SizedBox(width: 9),
          Expanded(child: _adminTransactionBadge(
            label: 'PAYMENT', value: payment == 'paid' ? 'Paid' : 'Payment pending', icon: payment == 'paid' ? Icons.check_circle_outline : Icons.payments_outlined, color: payment == 'paid' ? const Color(0xFF2E7D32) : const Color(0xFFB7791F))),
        ]),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 18, color: coffee),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SCHEDULE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .6, color: muted)),
                const SizedBox(height: 3),
                Text(_bookingDateTime(b).isEmpty ? 'Schedule not set' : _bookingDateTime(b), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: text)),
              ])),
            ]),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 9),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.location_on_outlined, size: 17, color: muted),
                const SizedBox(width: 9),
                Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted))),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(child: _adminTransactionBadge(
            label: 'CLEANER', value: cleanerNames.isEmpty ? 'Not assigned' : cleanerNames.join(', '), icon: cleanerNames.isEmpty ? Icons.person_off_outlined : Icons.person_outline, color: cleanerNames.isEmpty ? muted : coffee)),
          const SizedBox(width: 9),
          Expanded(child: _adminTransactionBadge(
            label: 'TOTAL', value: '₱${amount.toStringAsFixed(2)}', icon: Icons.payments_outlined, color: coffee)),
        ]),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _showBookingDetails(b),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(section == 'Booking History' ? 'View completed booking' : 'View booking details', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _adminTransactionBadge({required String label, required String value, required IconData icon, required Color color}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(dark ? .16 : .075),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .55, color: color)),
          const SizedBox(height: 3),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: color)),
        ])),
      ]),
    );
  }

  Future<void> statusFnForAdmin(Map<String, dynamic> booking, String value) async {
    await status(booking['id'].toString(), value);
    if (!mounted) return;
    setState(() {
      bookingsFuture = _loadBookings();
      cleanersFuture = _loadCleaners();
    });
  }

  Future<void> _markBookingNotificationsRead(String bookingId) async {
    if (bookingId.isEmpty) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase.from('notifications').update({
        'booking_is_read': true,
        'booking_read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', user.id).eq('booking_id', bookingId).eq('type', 'booking').eq('booking_is_read', false);
    } catch (_) {}
  }

  Future<void> _markPaymentNotificationsRead(String bookingId) async {
    if (bookingId.isEmpty) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase.from('notifications').update({
        'payment_is_read': true,
        'payment_read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', user.id).eq('booking_id', bookingId).eq('payment_is_read', false);
      if (!mounted) return;
      setState(() { notificationsFuture = _loadNotifications(); });
      await _refreshAdminBadgeCounts();
    } catch (e) {
      if (mounted) _message('Could not mark payment as read: $e');
    }
  }

  Future<void> _showBookingDetails(Map<String, dynamic> booking) async {
    // Opening booking details acknowledges the related booking notification.
    // This keeps the booking card and badge in sync without a separate action.
    final bookingId = booking['id']?.toString() ?? '';
    await _markBookingNotificationsRead(bookingId);
    if (mounted) {
      setState(() {
        bookingsFuture = _loadBookings();
        notificationsFuture = _loadNotifications();
      });
      await _refreshAdminBadgeCounts();
    }
    Map<String, dynamic> customer = {
      'full_name': booking['customer_name'],
      'email': booking['customer_email'],
      'phone': booking['customer_phone'],
    };
    try {
      final customerId = booking['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        final profile = await supabase.from('profiles').select('full_name, email, phone').eq('id', customerId).maybeSingle();
        if (profile != null) customer = profile;
      }
    } catch (_) {}

    List<Map<String, dynamic>> cleaners = [];
    try { cleaners = await _loadCleaners(); } catch (_) {}

    // Details can be opened from a notification, which supplies a raw booking
    // row rather than the enriched row returned by _loadBookings(). Resolve
    // the saved cleaner IDs here too, so approving a reschedule never makes an
    // existing assignment appear to disappear in the details sheet.
    final assignedIds = <String>{};
    final savedIds = booking['cleaner_ids'];
    if (savedIds is List) {
      assignedIds.addAll(savedIds.map((id) => id.toString().trim()).where((id) => id.isNotEmpty));
    } else if (savedIds is String && savedIds.trim().isNotEmpty) {
      // Also tolerate JSON/array text returned by older database rows.
      try {
        final decoded = jsonDecode(savedIds);
        if (decoded is List) {
          assignedIds.addAll(decoded.map((id) => id.toString().trim()).where((id) => id.isNotEmpty));
        }
      } catch (_) {}
    }
    final singleCleanerId = (booking['cleaner_id'] ?? '').toString().trim();
    if (singleCleanerId.isNotEmpty) assignedIds.add(singleCleanerId);

    if (assignedIds.isNotEmpty) {
      final namesById = <String, String>{};
      for (final cleaner in cleaners) {
        final id = (cleaner['id'] ?? '').toString().trim();
        final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? '').toString().trim();
        if (id.isNotEmpty && name.isNotEmpty) namesById[id] = name;
      }
      final resolvedNames = assignedIds.map((id) => namesById[id]).whereType<String>().toList();
      if (resolvedNames.isNotEmpty) {
        booking['cleaner_names'] = resolvedNames;
        booking['cleaner_name'] = resolvedNames.join(', ');
      }
    }
    if (!mounted) return;

    final statusValue = _adminBookingStatus(booking);
    final paymentStatus = (booking['payment_status'] ?? 'pending').toString().toLowerCase();
    final statusColor = statusValue == 'completed' ? const Color(0xFF2E7D32)
        : statusValue == 'cancelled' || statusValue == 'canceled' ? const Color(0xFFC94B4B)
        : statusValue == 'in_progress' || statusValue == 'confirmed' ? const Color(0xFF176B87)
        : const Color(0xFFB7791F);
    final service = (booking['service_name'] ?? 'Cleaning service').toString();
    final customerName = (customer['full_name'] ?? 'Customer').toString();
    final amount = (booking['service_price'] as num?)?.toDouble() ?? 0;
    final displayedCleanerNames = (booking['cleaner_names'] as List?)
            ?.map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList() ?? <String>[];
    final legacyCleanerName = (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '').toString().trim();
    final hasAssignedCleaners = assignedIds.isNotEmpty || displayedCleanerNames.isNotEmpty || legacyCleanerName.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .94,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.only(top: 9, bottom: 4), child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFCAB8AE), borderRadius: BorderRadius.circular(10)))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 10, 14, 4), child: Row(children: [
              Expanded(child: Text('Booking details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface))),
              IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
            ])),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 22), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF1DED4), Color(0xFFE8F0F3)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE0CEC3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 50, height: 50, decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A211E) : Colors.white.withOpacity(.78), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.cleaning_services_rounded, color: coffee, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(customerName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink))),
                    const SizedBox(height: 4),
                    Text(service, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Color(0xFF705B55)), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(children: [Icon(Icons.schedule_rounded, size: 15, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Color(0xFF705B55))), const SizedBox(width: 5), Expanded(child: Text(_bookingDateTime(booking), style: TextStyle(fontSize: 12, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Color(0xFF705B55)))))]),
                  ])),
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: statusColor.withOpacity(.13), borderRadius: BorderRadius.circular(18)), child: Text(_prettyValue(statusValue), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900))),
                ]),
              ),
              const SizedBox(height: 12),
              _detailSection('Customer information', [
                _detailLine('Email', customer['email'] ?? 'Not provided'),
                _detailLine('Phone', customer['phone'] ?? 'Not provided'),
              ]),
              _detailSection('Service location', [
                _detailLine('Address', booking['address'] ?? '—'),
                _detailLine('Barangay', booking['barangay'] ?? '—'),
                _detailLine('Municipality', booking['municipality'] ?? '—'),
                _detailLine('Province', booking['province'] ?? '—'),
                _detailLine('Instructions', (booking['instructions'] ?? '').toString().trim().isEmpty ? 'None' : booking['instructions']),
              ]),
              Container(
                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5D7CC))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Payment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: paymentStatus == 'paid' ? const Color(0xFFE4F4E6) : const Color(0xFFF7ECD8), borderRadius: BorderRadius.circular(14)), child: Text(paymentStatus == 'paid' ? 'PAID' : 'PENDING', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: paymentStatus == 'paid' ? const Color(0xFF2E7D32) : const Color(0xFFB7791F)))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text('Amount', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    Text('₱${amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : coffee), fontSize: 16)),
                  ]),
                  const SizedBox(height: 8),
                  _detailLine('Method', _prettyValue(booking['payment_method'] ?? 'Not set')),
                  if ((booking['payment_reference'] ?? '').toString().isNotEmpty) _detailLine('Reference', booking['payment_reference']),
                ]),
              ),
              _detailSection('Cleaner assignment', [
                ...(() {
                  final names = (booking['cleaner_names'] as List?)?.map((value) => value.toString()).where((value) => value.isNotEmpty).toList() ?? <String>[];
                  if (names.isEmpty) {
                    final oldName = (booking['cleaner_name'] ?? booking['assigned_cleaner_name'] ?? '').toString();
                    if (oldName.isNotEmpty) names.add(oldName);
                  }
                  if (names.isEmpty) return <Widget>[Container(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [const Icon(Icons.person_off_outlined, size: 18, color: Color(0xFF9A8A82)), const SizedBox(width: 8), Text('No cleaner assigned', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]))];
                  return names.map((name) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [const CircleAvatar(radius: 15, backgroundColor: beige, child: Icon(Icons.person_outline, color: coffee, size: 17)), const SizedBox(width: 9), Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)))]))).toList();
                })(),
              ]),
              _detailSection('Booking reference', [_detailLine('Booking ID', bookingId)]),
              const SizedBox(height: 3),
              if ((booking['status'] ?? '').toString().toLowerCase() == 'completed' || section == 'Booking History')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F4E6),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFB8DDBD)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 20),
                      SizedBox(width: 8),
                      Text('Completed', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                )
              else if ((booking['status'] ?? '').toString().toLowerCase() == 'cancelled' || (booking['status'] ?? '').toString().toLowerCase() == 'canceled')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBE9E7),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE7B9B5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cancel_rounded, color: Color(0xFFC62828), size: 20),
                      SizedBox(width: 8),
                      Text('Cancelled', style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                )
              else ...[
                Text('Admin actions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 9),
                Row(children: [
                  if (paymentStatus != 'paid')
                    Expanded(child: OutlinedButton.icon(onPressed: () async { Navigator.pop(sheetContext); await _setPayment(booking, 'paid'); }, icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('Mark paid')))
                  else
                    const Expanded(child: Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Text('Payment paid', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))))),
                  const SizedBox(width: 9),
                  Expanded(child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: hasAssignedCleaners ? const Color(0xFFE4F4E6) : coffee,
                      foregroundColor: hasAssignedCleaners ? const Color(0xFF2E7D32) : Colors.white,
                      disabledBackgroundColor: const Color(0xFFE4F4E6),
                      disabledForegroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: hasAssignedCleaners ? null : () async { Navigator.pop(sheetContext); await _assignCleaner(booking, cleaners); },
                    icon: Icon(hasAssignedCleaners ? Icons.groups_rounded : Icons.person_add_alt_1, size: 18),
                    label: Text(hasAssignedCleaners ? 'Cleaners assigned' : 'Assign cleaner'),
                  )),
                ]),
                const SizedBox(height: 9),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () async { Navigator.pop(sheetContext); await statusFnForAdmin(booking, 'confirmed'); }, icon: const Icon(Icons.check_circle_outline, size: 17), label: const Text('Confirm')),
                  FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: sage, foregroundColor: Colors.white), onPressed: () async { Navigator.pop(sheetContext); await statusFnForAdmin(booking, 'completed'); }, icon: const Icon(Icons.done_all_rounded, size: 17), label: const Text('Complete')),
                ]),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: TextButton.icon(style: TextButton.styleFrom(foregroundColor: const Color(0xFFC94B4B)), onPressed: () async { Navigator.pop(sheetContext); await _deleteBooking(booking); }, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Delete booking'))),
              ],
            ])),
          ]),
        ),
      ),
    ));
    if (mounted) setState(() { bookingsFuture = _loadBookings(); notificationsFuture = _loadNotifications(); });
  }


  Widget _detailSection(String title, List<Widget> children) => Container(
    width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE9E9E9))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 10), ...children,
    ]),
  );

  Widget _detailLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text('$label:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: Text((value ?? '—').toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
    ]),
  );

  String _prettyValue(dynamic value) => value.toString().replaceAll('_', ' ').replaceAll('-', ' ')
      .split(' ').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');

  Future<void> _setPayment(Map<String, dynamic> booking, String value) async {
    try {
      await supabase.from('bookings').update({'payment_status': value}).eq('id', booking['id']);
      final customerId = booking['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        await createKleenovaNotification(
          userId: customerId,
          title: 'Payment status updated',
          message: 'Your ${booking['service_name'] ?? 'booking'} payment is now ${_prettyValue(value)}.',
          type: 'payment',
          bookingId: booking['id'].toString(),
        );
      }
      if (mounted) setState(() { bookingsFuture = _loadBookings(); notificationsFuture = _loadNotifications(); });
      if (mounted) _message('Payment marked as $value.');
    } catch (e) { if (mounted) _message('Could not update payment: $e'); }
  }

  Future<void> _deleteBooking(Map<String, dynamic> booking) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete booking?'),
      content: const Text('This booking will be removed from the admin lists. Continue?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try {
      final bookingId = booking['id'];
      if (bookingId == null) throw Exception('This booking has no valid ID.');

      final deleted = await supabase
          .from('bookings')
          .update({'admin_deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', bookingId)
          .isFilter('admin_deleted_at', null)
          .select('id');

      if (deleted.isEmpty) {
        throw Exception('No booking was archived. Check that the admin_deleted_at column exists and your Supabase RLS UPDATE policy allows this action.');
      }

      await _logAdminActivity('Deleted booking', 'booking', bookingId.toString());

      try {
        final customerId = booking['customer_id']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          await createKleenovaNotification(
            userId: customerId,
            title: 'Booking removed',
            message: 'Your ${booking['service_name'] ?? 'booking'} booking was removed by an administrator.',
            type: 'booking',
            bookingId: bookingId.toString(),
          );
        }
      } catch (_) {}

      if (mounted) {
        setState(() { bookingsFuture = _loadBookings(); notificationsFuture = _loadNotifications(); });
        _message('Booking deleted');
      }
    } catch (e) {
      if (mounted) _message('Could not delete booking: $e');
    }
  }

  int? _minutesFromBookingTime(dynamic value) {
    var raw = (value ?? '').toString().trim().toUpperCase();
    raw = raw.replaceFirst(RegExp(r':\d{2}$'), '');
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(raw);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final meridiem = match.group(3);
    if (meridiem == 'PM' && hour < 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  Future<List<String>> _cleanerConflictMessages(Map<String, dynamic> target, Set<String> selectedIds) async {
    final date = (target['booking_date'] ?? '').toString();
    final targetStart = _minutesFromBookingTime(target['booking_time']);
    if (date.isEmpty || targetStart == null || selectedIds.isEmpty) return <String>[];
    final targetDuration = int.tryParse((target['duration_hours'] ?? '').toString()) ?? 2;
    final targetEnd = targetStart + targetDuration * 60;
    final rows = await supabase.from('bookings').select().eq('booking_date', date);
    final conflicts = <String>[];
    try {
      final availabilityRows = await supabase.from('cleaner_availability').select().inFilter('cleaner_id', selectedIds.toList()).eq('available_date', date);
      final availability = List<Map<String, dynamic>>.from(availabilityRows);
      for (final cleanerId in selectedIds) {
        final windows = availability.where((a) => a['cleaner_id']?.toString() == cleanerId).toList();
        if (windows.isEmpty) continue; // No schedule entered means no extra schedule restriction.
        final fits = windows.any((a) {
          if (a['is_available'] == false) return false;
          final start = _minutesFromBookingTime(a['start_time']);
          final end = _minutesFromBookingTime(a['end_time']);
          return start != null && end != null && targetStart >= start && targetEnd <= end;
        });
        if (!fits) {
          final cleaner = await supabase.from('cleaners').select('full_name').eq('id', cleanerId).maybeSingle();
          conflicts.add('${cleaner?['full_name'] ?? 'Selected cleaner'} is not available for the requested time.');
        }
      }
    } catch (_) {
      // If availability has not been configured, continue with booking overlap checks.
    }
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      if (row['id']?.toString() == target['id']?.toString()) continue;
      final st = (row['status'] ?? 'pending').toString().toLowerCase();
      if (st == 'completed' || st == 'cancelled' || st == 'canceled') continue;
      final assigned = <String>{};
      if (row['cleaner_ids'] is List) assigned.addAll((row['cleaner_ids'] as List).map((x) => x.toString()));
      final one = row['cleaner_id']?.toString();
      if (one != null && one.isNotEmpty) assigned.add(one);
      final overlapIds = assigned.intersection(selectedIds);
      if (overlapIds.isEmpty) continue;
      final otherStart = _minutesFromBookingTime(row['booking_time']);
      if (otherStart == null) continue;
      final otherDuration = int.tryParse((row['duration_hours'] ?? '').toString()) ?? 2;
      final otherEnd = otherStart + otherDuration * 60;
      if (targetStart < otherEnd && otherStart < targetEnd) {
        for (final cleanerId in overlapIds) {
          final cleaner = (await supabase.from('cleaners').select('full_name').eq('id', cleanerId).maybeSingle());
          final name = (cleaner?['full_name'] ?? 'Selected cleaner').toString();
          conflicts.add('$name already has a booking at ${row['booking_time'] ?? 'that time'}.');
        }
      }
    }
    return conflicts.toSet().toList();
  }

  Future<void> _assignCleaner(Map<String, dynamic> booking, List<Map<String, dynamic>> cleaners) async {
    // Only offer cleaners who are not already assigned to another active booking.
    // Existing assignments on this booking are also omitted to prevent duplicates
    // when the admin opens the assignment dialog again.
    final initial = <String>{};
    final existing = booking['cleaner_ids'];
    if (existing is List) initial.addAll(existing.map((id) => id.toString()));
    final oldId = booking['cleaner_id']?.toString();
    if (oldId != null && oldId.isNotEmpty) initial.add(oldId);

    final availableCleaners = cleaners.where((cleaner) {
      final id = cleaner['id']?.toString() ?? '';
      return id.isNotEmpty &&
          (cleaner['_assignment_status'] ?? 'Available').toString().toLowerCase() != 'assigned' &&
          !initial.contains(id);
    }).toList();
    if (availableCleaners.isEmpty) {
      _message(cleaners.isEmpty
          ? 'No cleaners found. Add a cleaner first.'
          : 'No available cleaners. Already-assigned cleaners are hidden to prevent duplicate assignments.');
      return;
    }

    final selectedIds = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final selected = Set<String>.from(initial);
        return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign cleaners'),
          content: SizedBox(
            width: 380,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, children: availableCleaners.map((cleaner) {
                final id = cleaner['id'].toString();
                final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? 'Cleaner').toString();
                final subtitle = (cleaner['phone'] ?? cleaner['email'] ?? '').toString();
                return CheckboxListTile(
                  value: selected.contains(id),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(name),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) { selected.add(id); } else { selected.remove(id); }
                  }),
                );
              }).toList()),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Assign')),
          ],
        ));
      },
    );
    if (selectedIds == null) return;

    try {
      final conflicts = await _cleanerConflictMessages(booking, selectedIds);
      if (conflicts.isNotEmpty) {
        if (mounted) _message('Cannot assign due to schedule conflict: ${conflicts.join(' ')}');
        return;
      }
      final ids = selectedIds.toList();
      final bookingId = booking['id']?.toString() ?? '';

      final updates = <String, dynamic>{
        'cleaner_ids': ids,
        'cleaner_id': ids.isEmpty ? null : ids.first,
      };
      final currentStatus = (booking['status'] ?? 'pending').toString().trim().toLowerCase();
      if (ids.isNotEmpty && currentStatus != 'completed' &&
          currentStatus != 'cancelled' && currentStatus != 'canceled') {
        // Assignment means the cleaning service has started.
        updates['status'] = 'in_progress';
      }
      await supabase.from('bookings').update(updates).eq('id', booking['id']);

      await _logAdminActivity(
        ids.isEmpty ? 'Cleared cleaner assignment' : 'Assigned cleaners',
        'booking',
        bookingId,
        {
          'cleaner_ids': ids,
          if (updates.containsKey('status')) 'status': updates['status'],
        },
      );

      // Notify the customer when a cleaner is actually assigned.
      if (ids.isNotEmpty && bookingId.isNotEmpty) {
        final names = <String>[];
        for (final cleanerId in ids) {
          final cleaner = cleaners.firstWhere(
            (c) => c['id']?.toString() == cleanerId,
            orElse: () => <String, dynamic>{},
          );
          final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? '').toString().trim();
          if (name.isNotEmpty) names.add(name);
        }

        final customerId = booking['customer_id']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          await createKleenovaNotification(
            userId: customerId,
            title: 'Cleaner assigned',
            message: names.isEmpty
                ? 'A cleaner has been assigned to your ${booking['service_name'] ?? 'cleaning'} booking.'
                : '${names.join(', ')} ${names.length == 1 ? 'has' : 'have'} been assigned to your ${booking['service_name'] ?? 'cleaning'} booking.',
            type: 'booking',
            bookingId: bookingId,
          );
        }
      }

      if (mounted) {
        setState(() {
          bookingsFuture = _loadBookings();
          cleanersFuture = _loadCleaners();
        });
        _message(ids.isEmpty ? 'Cleaner assignments cleared.' : 'Cleaners successfully assigned! This booking is now in progress.');
      }
    } catch (e) {
      if (mounted) _message('Could not save assignments. Ensure bookings.cleaner_ids (UUID[]) exists. Details: $e');
    }
  }

  Future<void> _manageCleaningChecklist(Map<String, dynamic> booking) async {
    final bookingId = booking['id']?.toString() ?? '';
    if (bookingId.isEmpty) return;
    final defaults = <String>['Dust and wipe surfaces', 'Sweep and mop floors', 'Clean bathroom/kitchen', 'Collect and dispose of rubbish', 'Final inspection'];
    List<Map<String, dynamic>> items = [];
    try {
      items = List<Map<String, dynamic>>.from(await supabase.from('booking_checklist_items').select().eq('booking_id', bookingId).order('created_at'));
      if (items.isEmpty) {
        await supabase.from('booking_checklist_items').insert(defaults.map((label) => {'booking_id': bookingId, 'item_label': label}).toList());
        items = List<Map<String, dynamic>>.from(await supabase.from('booking_checklist_items').select().eq('booking_id', bookingId).order('created_at'));
      }
    } catch (e) { if (mounted) _message('Could not load checklist. Check the checklist table and policies: $e'); return; }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Cleaning checklist'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: items.map((item) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text((item['item_label'] ?? '').toString()),
        value: item['is_completed'] == true,
        onChanged: (checked) async {
          try {
            await supabase.from('booking_checklist_items').update({'is_completed': checked == true, 'completed_at': checked == true ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', item['id']);
            setDialogState(() { item['is_completed'] = checked == true; });
          } catch (e) { if (mounted) _message('Could not update checklist: $e'); }
        },
      )).toList()))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
    )));
  }

  Future<void> _uploadBookingProof(Map<String, dynamic> booking, String type) async {
    final bookingId = booking['id']?.toString() ?? '';
    if (bookingId.isEmpty) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final path = '$bookingId/${type}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await supabase.storage.from('booking-proof').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: false));
      await supabase.from('booking_proof_photos').insert({'booking_id': bookingId, 'photo_type': type, 'storage_path': path, 'uploaded_by': supabase.auth.currentUser?.id});
      await _logAdminActivity('Uploaded $type cleaning photo', 'booking', bookingId, {'storage_path': path});
      if (mounted) _message('${_prettyValue(type)} photo uploaded.');
    } catch (e) { if (mounted) _message('Photo upload failed: $e'); }
  }

  Widget _reportChartCard({required String title, required String subtitle, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5D7CC)),
      boxShadow: const [BoxShadow(color: Color(0x07000000), blurRadius: 12, offset: Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      child,
    ]),
  );

  Widget _reportLineChart(List<int> values) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: CustomPaint(
        painter: _ReportLinePainter(values: values, lineColor: coffee, gridColor: beige),
      ),
    );
  }

  Widget _reportBarChart(List<int> values) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: _ReportBarPainter(values: values, barColor: deepSage, gridColor: beige),
      ),
    );
  }

  Widget _reportStatusChart({required int active, required int completed, required int cancelled}) {
    final total = active + completed + cancelled;
    return Row(children: [
      SizedBox(
        width: 142,
        height: 142,
        child: CustomPaint(
          painter: _ReportDonutPainter(active: active, completed: completed, cancelled: cancelled),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            Text('total', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ),
      ),
      const SizedBox(width: 18),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _reportLegend('Active', active, deepSage),
        const SizedBox(height: 12),
        _reportLegend('Completed', completed, sage),
        const SizedBox(height: 12),
        _reportLegend('Cancelled', cancelled, coral),
      ])),
    ]);
  }

  Widget _reportLegend(String label, int value, Color color) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
    Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
  ]);

  Future<void> _showReports() async {
    final rows = await _loadBookings();
    if (!mounted) return;
    final now = DateTime.now();
    final monthRows = rows.where((b) {
      final d = DateTime.tryParse((b['booking_date'] ?? '').toString());
      return d != null && d.year == now.year && d.month == now.month;
    }).toList();
    final completed = monthRows.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'completed').length;
    final cancelled = monthRows.where((b) => ['cancelled','canceled'].contains((b['status'] ?? '').toString().toLowerCase())).length;
    final active = monthRows.length - completed - cancelled;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Monthly booking report'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _detailLine('Month', '${now.year}-${now.month.toString().padLeft(2,'0')}'),
        _detailLine('Bookings', '${monthRows.length}'),
        _detailLine('Completed', '$completed'),
        _detailLine('Active', '$active'),
        _detailLine('Cancelled', '$cancelled'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  Future<void> _deleteSectionRecords(String value) async {
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Delete $value?',
      message: 'This will permanently remove these records from the admin list. This action cannot be undone.',
      confirmLabel: 'Yes, delete all',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      switch (value) {
        case 'Notifications':
          final user = supabase.auth.currentUser;
          if (user != null) await supabase.from('notifications').delete().eq('user_id', user.id);
          break;
        case 'Booking History':
          await supabase.from('bookings').update({'admin_deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('status', 'completed').isFilter('admin_deleted_at', null);
          break;
        case 'Reviews': {
          final rows = await supabase.from('reviews').select('id');
          final ids = List<Map<String, dynamic>>.from(rows)
              .map((row) => row['id'])
              .where((id) => id != null)
              .toList();
          if (ids.isNotEmpty) {
            final deleted = await supabase
                .from('reviews')
                .delete()
                .inFilter('id', ids)
                .select('id');
            if (deleted.isEmpty) {
              throw Exception('No reviews were deleted. Check the Supabase DELETE policy for the reviews table.');
            }
          }
          break;
        }
        case 'Reschedule Requests': {
          final rows = await supabase
              .from('booking_reschedule_requests')
              .select('id');
          final ids = List<Map<String, dynamic>>.from(rows)
              .map((row) => row['id'])
              .where((id) => id != null)
              .toList();
          if (ids.isNotEmpty) {
            final deleted = await supabase
                .from('booking_reschedule_requests')
                .delete()
                .inFilter('id', ids)
                .select('id');
            if (deleted.isEmpty) {
              throw Exception('No reschedule requests were deleted. Check the Supabase DELETE policy for booking_reschedule_requests.');
            }
          }
          break;
        }
        case 'Activity Log': {
          final rows = await supabase.from('admin_activity_logs').select('id');
          final ids = List<Map<String, dynamic>>.from(rows)
              .map((row) => row['id'])
              .where((id) => id != null)
              .toList();
          if (ids.isNotEmpty) {
            final deleted = await supabase
                .from('admin_activity_logs')
                .delete()
                .inFilter('id', ids)
                .select('id');
            if (deleted.isEmpty) {
              throw Exception('No activity logs were deleted. Check the Supabase DELETE policy for admin_activity_logs.');
            }
          }
          break;
        }
        default: return;
      }
      if (!mounted) return;
      _reload();
      setState(() {
        bookingHistoryBadgeCount = 0;
        reviewsBadgeCount = 0;
        rescheduleBadgeCount = 0;
        activityLogBadgeCount = 0;
        if (value == 'Reports') reportsBadgeCount = 0;
      });
      _message('$value deleted.');
    } catch (e) { if (mounted) _message('Could not delete $value: $e'); }
  }

  Future<List<Map<String, dynamic>>> _loadRescheduleRequests() async {
    final requests = List<Map<String, dynamic>>.from(
      await supabase
          .from('booking_reschedule_requests')
          .select()
          .order('created_at', ascending: false)
          .limit(200),
    );
    if (requests.isEmpty) return requests;

    // Use the same booking/profile enrichment as the main admin booking list.
    // This avoids briefly displaying the generic KLEENOVA customer label when
    // the request row itself does not contain a customer_name field.
    final bookingById = <String, Map<String, dynamic>>{};
    try {
      final bookings = await _loadBookings(includeDeleted: true);
      for (final booking in bookings) {
        final id = booking['id']?.toString();
        if (id != null && id.isNotEmpty) bookingById[id] = booking;
      }
    } catch (_) {}

    // Also resolve profiles directly as a fallback for older/deleted bookings.
    final customerIds = <String>{};
    for (final request in requests) {
      final requestId = request['customer_id']?.toString().trim();
      final bookingId = request['booking_id']?.toString();
      final bookingCustomerId = bookingById[bookingId]?['customer_id']?.toString().trim();
      if (requestId != null && requestId.isNotEmpty) customerIds.add(requestId);
      if (bookingCustomerId != null && bookingCustomerId.isNotEmpty) customerIds.add(bookingCustomerId);
    }

    final nameById = <String, String>{};
    if (customerIds.isNotEmpty) {
      try {
        final profiles = List<Map<String, dynamic>>.from(
          await supabase.from('profiles').select('*').inFilter('id', customerIds.toList()),
        );
        for (final profile in profiles) {
          final id = profile['id']?.toString();
          final name = (profile['full_name'] ?? profile['display_name'] ?? profile['name'] ?? profile['username'])?.toString().trim();
          if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
            nameById[id] = name;
          }
        }
      } catch (_) {}
    }

    for (final request in requests) {
      final booking = bookingById[request['booking_id']?.toString()];
      final requestCustomerId = request['customer_id']?.toString();
      final bookingCustomerId = booking?['customer_id']?.toString();
      final profileName = nameById[requestCustomerId] ?? nameById[bookingCustomerId];
      final requestName = request['customer_name']?.toString().trim();
      final bookingName = booking?['customer_name']?.toString().trim();
      final resolvedName = [profileName, requestName, bookingName]
          .whereType<String>()
          .map((name) => name.trim())
          .firstWhere((name) => name.isNotEmpty, orElse: () => 'Customer name unavailable');

      request['customer_name'] = resolvedName;
      request['service_name'] = (booking?['service_name'] ?? request['service_name'] ?? '').toString();
    }
    return requests;
  }

  Future<void> _reviewReschedule(Map<String, dynamic> request, bool approve) async {
    try {
      if (approve) {
        await supabase.from('bookings').update({
          'booking_date': request['requested_date'],
          'booking_time': request['requested_time'],
        }).eq('id', request['booking_id']);
      }
      await supabase.from('booking_reschedule_requests').update({
        'status': approve ? 'approved' : 'rejected',
        'reviewed_by': supabase.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request['id']);
      await _logAdminActivity(approve ? 'Approved reschedule request' : 'Rejected reschedule request', 'booking', request['booking_id']?.toString(), {'request_id': request['id']});
      final bookingRows = await supabase
          .from('bookings')
          .select('customer_id,service_name')
          .eq('id', request['booking_id'])
          .maybeSingle();
      final customerId = bookingRows?['customer_id']?.toString();
      final bookingId = request['booking_id']?.toString();
      final requestedDate = (request['requested_date'] ?? '').toString();
      final requestedTime = (request['requested_time'] ?? '').toString();
      final serviceName = (bookingRows?['service_name'] ?? 'Booking').toString();

      if (customerId != null && customerId.isNotEmpty) {
        await createKleenovaNotification(
          userId: customerId,
          title: 'Reschedule request ${approve ? 'approved' : 'rejected'}',
          message: approve
              ? 'Your $serviceName booking has been rescheduled to $requestedDate at $requestedTime.'
              : 'Your requested booking time change was not approved.',
          type: 'booking',
          bookingId: bookingId,
        );
      }

      // Notify the admin inbox as well, so the accepted change is visible
      // under Admin > Notifications / Bookings and includes the new schedule.
      if (approve) {
        await notifyAdmins(
          title: 'Booking rescheduled',
          message: '$serviceName booking has been updated to $requestedDate at $requestedTime.',
          type: 'booking',
          bookingId: bookingId,
        );
      }

      if (mounted) {
        setState(() {
          bookingsFuture = _loadBookings();
          notificationsFuture = _loadNotifications();
        });
        await _refreshAdminBadgeCounts();
      }
      if (mounted) _message(approve ? 'Reschedule approved.' : 'Reschedule rejected.');
    } catch (e) { if (mounted) _message('Could not process reschedule request: $e'); }
  }

  Future<List<Map<String, dynamic>>> _loadActivityLogs() async => List<Map<String, dynamic>>.from(
    await supabase.from('admin_activity_logs').select().order('created_at', ascending: false).limit(150));

  Future<void> _showRescheduleDetails(Map<String, dynamic> request) async {
    final oldDate = (request['old_date'] ?? '').toString().trim();
    final oldTime = (request['old_time'] ?? '').toString().trim();
    final newDate = (request['requested_date'] ?? '').toString().trim();
    final newTime = (request['requested_time'] ?? '').toString().trim();
    final reason = (request['reason'] ?? '').toString().trim();
    final status = (request['status'] ?? 'pending').toString();
    final bookingId = (request['booking_id'] ?? '').toString();
    final requestId = (request['id'] ?? '').toString();
    final createdAt = (request['created_at'] ?? '').toString();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text(
            'Reschedule Details',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Booking ID', bookingId),
                if (requestId.isNotEmpty) _detailRow('Request ID', requestId),
                if (createdAt.isNotEmpty) _detailRow('Requested', createdAt),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EEE9),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('OLD SCHEDULE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                              color: Color(0xFF76665F), letterSpacing: .6)),
                      const SizedBox(height: 6),
                      Text(
                        oldDate.isEmpty && oldTime.isEmpty
                            ? 'Not recorded'
                            : '${oldDate.isEmpty ? '—' : oldDate}  •  ${oldTime.isEmpty ? '—' : oldTime}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5F3),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NEW REQUESTED SCHEDULE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                              color: deepSage, letterSpacing: .6)),
                      const SizedBox(height: 6),
                      Text(
                        '${newDate.isEmpty ? '—' : newDate}  •  ${newTime.isEmpty ? '—' : newTime}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Status: ${_prettyValue(status)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('REASON',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                          color: Color(0xFF76665F), letterSpacing: .6)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(reason,
                        style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (request['is_read'] != true)
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _markRescheduleRead(request['id'].toString());
                },
                icon: const Icon(Icons.done_rounded, size: 17),
                label: const Text('Mark read'),
              ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withOpacity(.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 115,
              child: Text(
                label,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markRescheduleRead(String id) async { try { await supabase.from('booking_reschedule_requests').update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id); if (mounted) { setState(() { rescheduleBadgeCount = 0; }); _refreshAdminBadgeCounts(); } } catch (e) { if (mounted) _message('Could not mark request as read: $e'); } }
  Future<void> _deleteReschedule(String id) async {
    final ok = await confirmKleenovaAction(
      context,
      title: 'Delete reschedule request?',
      message: 'Delete this request permanently?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!ok) return;
    try {
      final deleted = await supabase
          .from('booking_reschedule_requests')
          .delete()
          .eq('id', id)
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          'The request still exists. Supabase may be blocking deletion; check the DELETE policy for booking_reschedule_requests.',
        );
      }
      if (mounted) {
        setState(() {});
        _refreshAdminBadgeCounts();
        _message('Reschedule request deleted.');
      }
    } catch (e) {
      if (mounted) _message('Could not delete request: $e');
    }
  }
  Future<void> _markActivityRead(String id) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await supabase
          .from('admin_activity_logs')
          .update({'is_read': true, 'read_at': now})
          .eq('id', id)
          .select('id, is_read, read_at');

      if (updated.isEmpty) {
        throw Exception('No activity log was updated. Check the admin_activity_logs UPDATE policy.');
      }

      if (!mounted) return;
      setState(() {});
      _reloadSectionData();
      await _refreshAdminBadgeCounts();
      _message('Activity marked as read.');
    } catch (e) {
      if (mounted) _message('Could not mark activity as read: $e');
    }
  }
  Future<void> _deleteActivity(String id) async {
    final ok = await confirmKleenovaAction(
      context,
      title: 'Delete activity log?',
      message: 'Delete this activity log permanently?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!ok) return;
    try {
      final deleted = await supabase
          .from('admin_activity_logs')
          .delete()
          .eq('id', id)
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          'The activity log still exists. Check the Supabase DELETE policy for admin_activity_logs.',
        );
      }
      if (mounted) {
        setState(() {});
        _refreshAdminBadgeCounts();
        _message('Activity log deleted.');
      }
    } catch (e) {
      if (mounted) _message('Could not delete activity log: $e');
    }
  }

  
  Widget _adminGeometricBackground({required Widget child}) {
    // Plain beige dashboard: no decorative squares or geometric overlays.
    return child;
  }

Widget _overview() =>_adminGeometricBackground(child: FutureBuilder<List<List<Map<String, dynamic>>>>(
    future: Future.wait<List<Map<String, dynamic>>>([
      bookingsFuture,
      servicesFuture,
      cleanersFuture,
      reviewsFuture,
      notificationsFuture,
      usersFuture,
    ]),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(30),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return _errorCard('Could not load dashboard: ${snapshot.error}');
      }

      final data = snapshot.data ?? const <List<Map<String, dynamic>>>[];
      final bookings = data.isNotEmpty ? data[0] : <Map<String, dynamic>>[];
      final services = data.length > 1 ? data[1] : <Map<String, dynamic>>[];
      final cleaners = data.length > 2 ? data[2] : <Map<String, dynamic>>[];
      final reviews = data.length > 3 ? data[3] : <Map<String, dynamic>>[];
      final notifications = data.length > 4 ? data[4] : <Map<String, dynamic>>[];
      final users = data.length > 5 ? data[5] : <Map<String, dynamic>>[];

      final todayBookings = bookings.where(_isBookingToday).toList();
      final pending = bookings.where((b) =>
          (b['status'] ?? 'pending').toString().toLowerCase() == 'pending').length;
      final completed = bookings.where((b) =>
          (b['status'] ?? '').toString().toLowerCase() == 'completed').length;
      final paid = bookings.where((b) =>
          (b['payment_status'] ?? '').toString().toLowerCase() == 'paid').length;
      final assignedCleaners = cleaners.where((c) =>
          (c['_assignment_status'] ?? '').toString().toLowerCase() == 'assigned').length;
      final availableCleaners = cleaners.length - assignedCleaners;
      final activeServices = services.where((s) => s['is_active'] != false).length;

      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final medium = constraints.maxWidth >= 600;
          final columns = wide ? 4 : (medium ? 3 : 2);
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final bg = isDark ? const Color(0xFF171312) : const Color(0xFFF4F7F8);
          final navy = isDark ? const Color(0xFF2C6578) : const Color(0xFF173F52);
          final terracotta = const Color(0xFFE86F4E);
          final ink = isDark ? const Color(0xFFF8F2EB) : const Color(0xFF2B211D);
          final muted = isDark ? const Color(0xFFBDB2AC) : const Color(0xFF765F55);

          return Container(
            color: bg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0B4A5F), Color(0xFF0F5C73), Color(0xFF1B8AA0)],
                      stops: [0.0, 0.58, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: navy.withOpacity(.18),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -18,
                        top: -30,
                        child: Container(
                          width: 125,
                          height: 125,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(.08),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 55,
                        bottom: -45,
                        child: Container(
                          width: 105,
                          height: 105,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(.06),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.14),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 21),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'KLEENOVA  •  ADMIN',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Welcome back, Admin',
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'serif',
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.45,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Everything you need to manage KLEENOVA, at a glance.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.82),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _overviewBadge(Icons.calendar_today_outlined, _formatToday()),
                              _overviewBadge(Icons.verified_outlined, 'System active'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Business snapshot', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink), fontSize: 23, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text('A quick look at your current records.', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted), fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A211E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? const Color(0xFF51413B) : const Color(0xFFE7D6C8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF49A56A), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('Live', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink), fontSize: 11, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: wide ? 1.55 : (medium ? 1.45 : 1.34),
                  children: [
                    _dashboardStat('Total Bookings', '${bookings.length}', Icons.calendar_month_outlined, const Color(0xFF1B9AAA), 'All bookings'),
                    _dashboardStat('Today', '${todayBookings.length}', Icons.today_outlined, const Color(0xFFFFA726), 'Scheduled today'),
                    _dashboardStat('Pending', '$pending', Icons.hourglass_top_rounded, const Color(0xFF8C6FD0), 'Needs attention'),
                    _dashboardStat('Completed', '$completed', Icons.check_circle_outline, const Color(0xFF3FA36B), 'Finished bookings'),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Management', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink), fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text('Open a section to manage your business.', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : muted), fontSize: 12.5)),
                const SizedBox(height: 11),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: wide ? 2.15 : (medium ? 1.95 : 1.72),
                  children: [
                    _overviewShortcut('Today’s Bookings', '${todayBookings.length} scheduled today', Icons.today_rounded, navy, () => _showTodayBookingsDialog(todayBookings)),
                    _overviewShortcut('Booking Status', '${bookings.length} total bookings', Icons.donut_large_rounded, const Color(0xFF76518C), () => _showBookingStatusDialog(bookings)),
                    _overviewShortcut('Cleaner Availability', '$availableCleaners available • $assignedCleaners assigned', Icons.groups_rounded, const Color(0xFF5A8A63), () => _showCleanerAvailabilityDialog(cleaners)),
                    _overviewShortcut('Payments', '$paid paid bookings', Icons.payments_outlined, const Color(0xFF3F7956), () => _showPaymentsDialog(bookings)),
                    _overviewShortcut('Services', '$activeServices active services', Icons.cleaning_services_outlined, terracotta, () => _showServicesDialog(services)),
                    _overviewShortcut('Customers', '${users.length} registered profiles', Icons.people_outline_rounded, const Color(0xFF8A6A55), () => _showCustomersDialog(users)),
                    _overviewShortcut('Reviews', '${reviews.length} customer reviews', Icons.star_outline_rounded, const Color(0xFFD49A25), () => _showReviewsDialog(reviews)),
                    _overviewShortcut('Notifications', '${notifications.length} notification records', Icons.notifications_none_rounded, const Color(0xFFB45F55), () => _showNotificationsDialog(notifications)),
                    _overviewShortcut('All Bookings', 'Open booking management', Icons.calendar_month_outlined, navy, () => _showAllBookingsDialog(bookings)),
                    _overviewShortcut('Cleaners', 'Manage cleaner list', Icons.person_search_outlined, const Color(0xFF5A8A63), () => _showCleanersDialog(cleaners)),
                  ],
                ),
                const SizedBox(height: 18),
              ],
            ),
          );
        },
      );
    },
  ));

  Widget _overviewShortcut(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF51413B) : beige),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? .12 : .035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(.11),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showTodayBookingsDialog(List<Map<String, dynamic>> rows) async {
    await _showOverviewPopup(
      title: 'Today’s Bookings',
      icon: Icons.today_rounded,
      accent: coffee,
      manageLabel: 'All Bookings',
      onManage: () => setState(() => section = 'Bookings'),
      child: Column(
        children: [
          _miniMetric('Scheduled today', '${rows.length}', Icons.event_available_outlined),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            _overviewEmpty('No bookings are scheduled for today.', Icons.event_available_outlined)
          else
            ...rows.map(_todayBookingTile),
        ],
      ),
    );
  }

  Future<void> _showBookingStatusDialog(List<Map<String, dynamic>> rows) async {
    final counts = <String, int>{};
    for (final booking in rows) {
      final status = (booking['status'] ?? 'pending').toString().toLowerCase().replaceAll('_', ' ');
      counts[status] = (counts[status] ?? 0) + 1;
    }
    final order = ['pending', 'confirmed', 'assigned', 'in progress', 'ongoing', 'completed', 'cancelled'];
    final colors = <String, Color>{
      'pending': const Color(0xFFB7791F),
      'confirmed': sage,
      'assigned': const Color(0xFF7A5C8E),
      'in progress': caramel,
      'ongoing': caramel,
      'completed': const Color(0xFF4F7B58),
      'cancelled': const Color(0xFFB44A4A),
    };
    await _showOverviewPopup(
      title: 'Booking Status',
      icon: Icons.donut_large_rounded,
      accent: const Color(0xFF7A5C8E),
      manageLabel: 'Manage Bookings',
      onManage: () => setState(() => section = 'Bookings'),
      child: rows.isEmpty
          ? _overviewEmpty('No booking records yet.', Icons.calendar_month_outlined)
          : Column(
              children: [
                _miniMetric('Total bookings', '${rows.length}', Icons.calendar_month_outlined, color: const Color(0xFF7A5C8E)),
                const SizedBox(height: 14),
                ...order.where((status) => (counts[status] ?? 0) > 0).map(
                  (status) => _statusOverviewRow(
                    _prettyValue(status),
                    counts[status] ?? 0,
                    rows.length,
                    colors[status] ?? coffee,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showCleanerAvailabilityDialog(List<Map<String, dynamic>> cleaners) async {
    final assigned = cleaners.where((c) =>
        (c['_assignment_status'] ?? '').toString().toLowerCase() == 'assigned').toList();
    final available = cleaners.where((c) =>
        (c['_assignment_status'] ?? '').toString().toLowerCase() != 'assigned').toList();
    await _showOverviewPopup(
      title: 'Cleaner Availability',
      icon: Icons.groups_rounded,
      accent: sage,
      manageLabel: 'Manage Cleaners',
      onManage: () => setState(() => section = 'Cleaners'),
      child: Column(
        children: [
          if (cleaners.isEmpty)
            _overviewEmpty('No cleaners have been added yet.', Icons.person_search_outlined)
          else ...[
            Row(children: [
              Expanded(child: _miniMetric('Total', '${cleaners.length}', Icons.groups_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _miniMetric('Available', '${available.length}', Icons.check_circle_outline, color: sage)),
              const SizedBox(width: 8),
              Expanded(child: _miniMetric('Assigned', '${assigned.length}', Icons.assignment_ind_outlined, color: caramel)),
            ]),
            const SizedBox(height: 14),
            if (available.isNotEmpty)
              ...available.take(8).map(_cleanerOverviewTile)
            else
              _overviewEmpty('All cleaners are currently assigned.', Icons.event_busy_outlined),
          ],
        ],
      ),
    );
  }

  Future<void> _showOverviewPopup({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget child,
    required String manageLabel,
    required VoidCallback onManage,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final maxHeight = size.height * .78;
        final double dialogHeight = size.height < 650 ? size.height * .72 : maxHeight.clamp(500.0, 680.0).toDouble();
        return Dialog(
          backgroundColor: const Color(0xFFF9E8E2),
          insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
          child: SizedBox(
            width: size.width > 700 ? 525 : double.infinity,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: accent, size: 23),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          onManage();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: coffee,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        ),
                        child: Text(manageLabel),
                      ),
                      const SizedBox(width: 5),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: FilledButton.styleFrom(
                          backgroundColor: coffee,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPaymentsDialog(List<Map<String, dynamic>> bookings) async {
    final paid = bookings.where((b) => (b['payment_status'] ?? 'pending').toString().toLowerCase() == 'paid').toList();
    final pending = bookings.where((b) => (b['payment_status'] ?? 'pending').toString().toLowerCase() == 'pending').toList();
    final failed = bookings.where((b) => (b['payment_status'] ?? '').toString().toLowerCase() == 'failed').toList();
    final total = paid.fold<double>(0, (sum, b) => sum + ((b['service_price'] as num?)?.toDouble() ?? 0));
    await _showOverviewPopup(
      title: 'Payments', icon: Icons.payments_outlined, accent: const Color(0xFF4F7B58),
      manageLabel: 'Manage Payments', onManage: () => setState(() => section = 'Payments'),
      child: Column(children: [
        Row(children: [
          Expanded(child: _miniMetric('Paid', '${paid.length}', Icons.check_circle_outline, color: const Color(0xFF4F7B58))),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Pending', '${pending.length}', Icons.schedule, color: const Color(0xFFB7791F))),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Failed', '${failed.length}', Icons.error_outline, color: const Color(0xFFB44A4A))),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: coffee), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total collected', style: TextStyle(fontSize: 11, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Color(0xFF705B55)))),
              const SizedBox(height: 2),
              Text(_peso(total), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink))),
            ])),
            Text('QRPH', style: TextStyle(fontWeight: FontWeight.w800, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : coffee))),
          ]),
        ),
        const SizedBox(height: 12),
        if (bookings.isEmpty)
          _overviewEmpty('No payment records yet.', Icons.receipt_long_outlined)
        else
          ...bookings.take(8).map((b) => _paymentOverviewTile(b)),
      ]),
    );
  }

  Future<void> _showServicesDialog(List<Map<String, dynamic>> services) async {
    final active = services.where((s) => s['is_active'] != false).toList();
    await _showOverviewPopup(
      title: 'Services', icon: Icons.cleaning_services_outlined, accent: caramel,
      manageLabel: 'Manage Services', onManage: () => setState(() => section = 'Services'),
      child: Column(children: [
        Row(children: [
          Expanded(child: _miniMetric('Total', '${services.length}', Icons.cleaning_services_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Active', '${active.length}', Icons.check_circle_outline, color: sage)),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Hidden', '${services.length - active.length}', Icons.visibility_off_outlined, color: caramel)),
        ]),
        const SizedBox(height: 14),
        if (services.isEmpty)
          _overviewEmpty('No services have been added yet.', Icons.cleaning_services_outlined)
        else
          ...services.take(8).map(_serviceOverviewTile),
      ]),
    );
  }

  Future<void> _showCustomersDialog(List<Map<String, dynamic>> users) async {
    final customers = users.where((u) => (u['role'] ?? 'customer').toString().toLowerCase() != 'admin').toList();
    await _showOverviewPopup(
      title: 'Customers', icon: Icons.people_outline_rounded, accent: const Color(0xFF8A6A55),
      manageLabel: 'Manage Customers', onManage: () => setState(() => section = 'Users'),
      child: Column(children: [
        _miniMetric('Registered customers', '${customers.length}', Icons.people_outline_rounded, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF8A6A55))),
        const SizedBox(height: 14),
        if (customers.isEmpty)
          _overviewEmpty('No customer profiles yet.', Icons.person_add_alt_1_outlined)
        else
          ...customers.take(8).map(_customerOverviewTile),
      ]),
    );
  }

  Future<void> _showReviewsDialog(List<Map<String, dynamic>> reviews) async {
    final average = reviews.isEmpty ? 0.0 : reviews.fold<double>(0, (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0)) / reviews.length;
    await _showOverviewPopup(
      title: 'Reviews', icon: Icons.star_outline_rounded, accent: const Color(0xFFD49A25),
      manageLabel: 'Manage Reviews', onManage: () => setState(() => section = 'Reviews'),
      child: Column(children: [
        Row(children: [
          Expanded(child: _miniMetric('Average', reviews.isEmpty ? '—' : average.toStringAsFixed(1), Icons.star_rounded, color: const Color(0xFFD49A25))),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Reviews', '${reviews.length}', Icons.rate_review_outlined, color: sage)),
        ]),
        const SizedBox(height: 14),
        if (reviews.isEmpty)
          _overviewEmpty('No customer reviews yet.', Icons.rate_review_outlined)
        else
          ...reviews.take(8).map(_reviewOverviewTile),
      ]),
    );
  }

  Future<void> _showNotificationsDialog(List<Map<String, dynamic>> notifications) async {
    await _showOverviewPopup(
      title: 'Notifications', icon: Icons.notifications_none_rounded, accent: const Color(0xFFB45F55),
      manageLabel: 'Manage Notifications', onManage: () => setState(() => section = 'Notifications'),
      child: notifications.isEmpty
          ? _overviewEmpty('No notification records yet.', Icons.notifications_none_rounded)
          : Column(children: notifications.take(10).map(_notificationOverviewTile).toList()),
    );
  }

  Future<void> _showAllBookingsDialog(List<Map<String, dynamic>> bookings) async {
    await _showOverviewPopup(
      title: 'All Bookings', icon: Icons.calendar_month_outlined, accent: coffee,
      manageLabel: 'Manage Bookings', onManage: () => setState(() => section = 'Bookings'),
      child: bookings.isEmpty
          ? _overviewEmpty('No booking records yet.', Icons.calendar_month_outlined)
          : Column(children: bookings.take(12).map(_recentBookingTile).toList()),
    );
  }

  Future<void> _showCleanersDialog(List<Map<String, dynamic>> cleaners) async {
    final assigned = cleaners.where((c) => (c['_assignment_status'] ?? '').toString().toLowerCase() == 'assigned').length;
    final available = cleaners.length - assigned;
    await _showOverviewPopup(
      title: 'Cleaners', icon: Icons.person_search_outlined, accent: sage,
      manageLabel: 'Manage Cleaners', onManage: () => setState(() => section = 'Cleaners'),
      child: Column(children: [
        Row(children: [
          Expanded(child: _miniMetric('Total', '${cleaners.length}', Icons.groups_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Available', '$available', Icons.check_circle_outline, color: sage)),
          const SizedBox(width: 8),
          Expanded(child: _miniMetric('Assigned', '$assigned', Icons.assignment_ind_outlined, color: caramel)),
        ]),
        const SizedBox(height: 14),
        if (cleaners.isEmpty)
          _overviewEmpty('No cleaners have been added yet.', Icons.person_search_outlined)
        else
          ...cleaners.take(10).map(_cleanerOverviewTile),
      ]),
    );
  }

  Widget _paymentOverviewTile(Map<String, dynamic> b) {
    final status = (b['payment_status'] ?? 'pending').toString().toLowerCase();
    final color = status == 'paid' ? const Color(0xFF4F7B58) : status == 'failed' ? const Color(0xFFB44A4A) : const Color(0xFFB7791F);
    final amount = (b['service_price'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 37, height: 37, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.receipt_long_outlined, color: coffee, size: 18)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((b['customer_name'] ?? b['service_name'] ?? 'Booking').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
          Text(_peso(amount), style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        _statusPill(status),
      ]),
    );
  }

  Widget _serviceOverviewTile(Map<String, dynamic> service) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Container(width: 37, height: 37, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.cleaning_services_outlined, color: coffee, size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((service['name'] ?? 'Cleaning service').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        Text('${_peso((service['price'] as num?)?.toDouble() ?? 0)} • ${service['duration_hours'] ?? 2} hrs', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
      _statusPill(service['is_active'] == false ? 'hidden' : 'active'),
    ]),
  );

  Widget _customerOverviewTile(Map<String, dynamic> user) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      const CircleAvatar(radius: 18, backgroundColor: beige, child: Icon(Icons.person_outline, color: coffee, size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((user['full_name'] ?? 'KLEENOVA customer').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        Text((user['email'] ?? user['phone'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ]),
  );

  Widget _overviewBadge(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _overviewSectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ],
  );

  Widget _dashboardStat(String label, String value, IconData icon, Color color, String caption) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color, Color.lerp(color, Colors.black, .14)!],
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: color.withOpacity(.30), blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white.withOpacity(.22), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 19)),
        const Spacer(),
        Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ]),
      const SizedBox(height: 9),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
    ]),
  );

  Widget _overviewPanel({required String title, required IconData icon, Widget? trailing, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF51413B) : beige),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? .12 : .035), blurRadius: 12, offset: const Offset(0, 5))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 35, height: 35, decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF40302A) : beige, borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFB18F) : coffee, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
        if (trailing != null) trailing,
      ]),
      const SizedBox(height: 13),
      child,
    ]),
  );

  Widget _statusOverviewRow(String label, int count, int total, Color color) {
    final ratio = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface))),
          Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 7, backgroundColor: beige, valueColor: AlwaysStoppedAnimation<Color>(color))),
      ]),
    );
  }

  Widget _miniMetric(String label, String value, IconData icon, {Color color = coffee}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
    decoration: BoxDecoration(color: beige.withOpacity(.55), borderRadius: BorderRadius.circular(13)),
    child: Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
      Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );

  Widget _todayBookingTile(Map<String, dynamic> b) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => _showBookingDetails(b),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.cleaning_services_outlined, color: coffee, size: 19)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((b['customer_name'] ?? 'KLEENOVA customer').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text((b['service_name'] ?? 'Cleaning service').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text((b['booking_time'] ?? 'Time not set').toString(), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        _statusPill((b['status'] ?? 'pending').toString()),
      ]),
    ),
  );

  Widget _cleanerOverviewTile(Map<String, dynamic> cleaner) {
    final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? 'Cleaner').toString();
    final assigned = (cleaner['_assignment_status'] ?? '').toString().toLowerCase() == 'assigned';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [
        const CircleAvatar(radius: 18, backgroundColor: beige, child: Icon(Icons.person_outline, color: coffee, size: 18)),
        const SizedBox(width: 9),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: assigned ? const Color(0xFFF0E8F6) : const Color(0xFFE8F4E8), borderRadius: BorderRadius.circular(16)), child: Text(assigned ? 'Assigned' : 'Available', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: assigned ? const Color(0xFF6E4C7E) : const Color(0xFF47704D)))),
      ]),
    );
  }

  Widget _popularServiceTile(String name, int bookings, double revenue) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cleaning_services_rounded, color: coffee, size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text('$bookings booking${bookings == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
      Text(_peso(revenue), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : coffee))),
    ]),
  );

  Widget _reviewOverviewTile(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final name = (review['reviewer_name'] ?? review['customer_name'] ?? review['full_name'] ?? review['user_name'] ?? 'Customer').toString();
    final service = (review['service_name'] ?? 'Cleaning service').toString();
    final comment = (review['comment'] ?? review['review'] ?? review['message'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
          Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, size: 14, color: const Color(0xFFD49A25)))),
        ]),
        const SizedBox(height: 3),
        Text(service, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (comment.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(comment, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _notificationOverviewTile(Map<String, dynamic> n) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.notifications_none_rounded, color: coffee, size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((n['title'] ?? 'Notification').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 3),
        Text((n['message'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ]),
  );

  Widget _recentBookingTile(Map<String, dynamic> b) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(13)),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.receipt_long_outlined, color: coffee, size: 18)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((b['customer_name'] ?? 'Customer').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text('${b['service_name'] ?? 'Cleaning service'} • ${_bookingDateTime(b)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
      _statusPill((b['status'] ?? 'pending').toString()),
    ]),
  );

  Widget _statusPill(String value) {
    final status = value.toLowerCase().replaceAll('_', ' ');
    Color color = coffee;
    if (status == 'completed') color = const Color(0xFF4F7B58);
    else if (status == 'pending') color = const Color(0xFFB7791F);
    else if (status == 'cancelled') color = const Color(0xFFB44A4A);
    else if (status == 'confirmed') color = sage;
    else if (status == 'assigned') color = const Color(0xFF7A5C8E);
    else if (status == 'in progress' || status == 'ongoing') color = caramel;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(15)), child: Text(_prettyValue(status), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)));
  }

  Widget _overviewEmpty(String message, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(child: Column(children: [Icon(icon, size: 28, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 7), Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
  );

  Widget _quickAction(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label),
    style: FilledButton.styleFrom(backgroundColor: coffee, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );

  bool _isBookingToday(Map<String, dynamic> booking) {
    final raw = (booking['booking_date'] ?? '').toString();
    if (raw.isEmpty) return false;
    final date = DateTime.tryParse(raw);
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  String _formatToday() {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  String _peso(double value) => '₱${value.toStringAsFixed(2)}';

  Widget _servicesSection() => FutureBuilder<List<Map<String, dynamic>>>(
    future: servicesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (snapshot.hasError) {
        return _errorCard('Could not load services: ${snapshot.error}');
      }

      final serviceRows = snapshot.data ?? <Map<String, dynamic>>[];
      final activeCount = serviceRows.where((s) => s['is_active'] != false).length;
      final hiddenCount = serviceRows.length - activeCount;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final onSurface = Theme.of(context).colorScheme.onSurface;
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The page title is supplied by the admin shell. Keep this area focused
          // on service management, matching the compact phone-style reference.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage services',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Add, edit, hide, or remove services customers can book.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF30272A) : const Color(0xFFF4E9DF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cleaning_services_rounded, size: 15, color: coffee),
                    const SizedBox(width: 5),
                    Text(
                      '${serviceRows.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (serviceRows.isNotEmpty)
            Row(
              children: [
                _serviceCountChip(
                  icon: Icons.visibility_outlined,
                  label: 'Visible',
                  value: activeCount,
                  color: sage,
                ),
                const SizedBox(width: 8),
                _serviceCountChip(
                  icon: Icons.visibility_off_outlined,
                  label: 'Hidden',
                  value: hiddenCount,
                  color: coral,
                ),
              ],
            ),
          if (serviceRows.isNotEmpty) const SizedBox(height: 12),
          if (serviceRows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 38, 24, 38),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: isDark ? const Color(0xFF51413B) : beige),
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF40302A) : const Color(0xFFF4E9DF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cleaning_services_outlined, color: coffee, size: 32),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No services yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: onSurface),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Add your first service so customers can book it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
              ),
            )
          else
            ...serviceRows.map(_adminServiceCard),
        ],
      );
    },
  );

  Widget _serviceCountChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: dark ? color.withOpacity(.12) : color.withOpacity(.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 4),
          Text('$value', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _adminServiceCard(Map<String, dynamic> service) {
    final image = (service['image_url'] ?? '').toString().trim();
    final name = (service['name'] ?? 'Service').toString();
    final category = (service['category'] ?? 'Cleaning').toString();
    final description = (service['description'] ?? '').toString().trim();
    final price = (service['price'] as num?)?.toDouble() ?? 0;
    final duration = (service['duration_hours'] as num?)?.toDouble() ?? 2;
    final active = service['is_active'] != false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final durationLabel = duration == duration.roundToDouble()
        ? duration.toStringAsFixed(0)
        : duration.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: isDark ? const Color(0xFF51413B) : const Color(0xFFE4D8CF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? .12 : .035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 98,
              height: 98,
              child: image.isEmpty
                  ? Container(
                      color: isDark ? const Color(0xFF40302A) : const Color(0xFFE9DED4),
                      alignment: Alignment.center,
                      child: const Icon(Icons.cleaning_services_rounded, color: coffee, size: 32),
                    )
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: isDark ? const Color(0xFF40302A) : const Color(0xFFE9DED4),
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported_outlined, color: coffee, size: 30),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$category  •  ₱${price.toStringAsFixed(0)}  •  $durationLabel hours',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Description: $description',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        color: muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    active ? 'Visible to customers' : 'Hidden from customers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? sage : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 3),
          SizedBox(
            width: 38,
            child: Column(
              children: [
                IconButton(
                  tooltip: 'Edit service',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () => editService(service),
                  icon: const Icon(Icons.edit_rounded, color: coffee, size: 23),
                ),
                IconButton(
                  tooltip: 'Delete service',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () => deleteService(service),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 23),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cleanersSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Text('Manage cleaners', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface))),
    ]),
    const SizedBox(height: 12),
    _panel(title: 'cleaners', future: cleanersFuture,
      emptyText: 'No cleaners added yet. Tap “Add cleaner” to create your cleaner list.',
      itemBuilder: (cleaner) {
        final name = (cleaner['full_name'] ?? cleaner['name'] ?? cleaner['cleaner_name'] ?? 'Cleaner').toString();
        final email = (cleaner['email'] ?? '').toString();
        final phone = (cleaner['phone'] ?? '').toString();
        final address = (cleaner['address'] ?? '').toString();
        return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: _cardDecoration(),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(backgroundColor: beige, child: Icon(Icons.person_outline, color: coffee)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 7),
              Align(alignment: Alignment.centerLeft, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cleaner['_assignment_status'] == 'Assigned'
                      ? const Color(0xFFE3F0FF) : const Color(0xFFE5F4E1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8,
                    color: cleaner['_assignment_status'] == 'Assigned'
                        ? const Color(0xFF1976D2) : const Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  Text((cleaner['_assignment_status'] ?? 'Available').toString(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: cleaner['_assignment_status'] == 'Assigned'
                          ? const Color(0xFF1565C0) : const Color(0xFF2E7D32))),
                ]),
              )),
              if (email.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Email: $email', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              if (phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Phone: $phone', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              if (address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Address: $address', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            ])),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit cleaner',
                  onPressed: () => editCleaner(cleaner),
                  icon: const Icon(Icons.edit_outlined, color: coffee),
                ),
                IconButton(
                  tooltip: 'Delete cleaner',
                  onPressed: () => deleteCleaner(cleaner),
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ),
          ]));
      }),
  ]);

  Future<void> _sendNotification() async {
    final title = TextEditingController();
    final message = TextEditingController();
    String target = 'all';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Send notification'),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: message, maxLines: 4, decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: target,
            decoration: const InputDecoration(labelText: 'Audience'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All customers')),
              DropdownMenuItem(value: 'admins', child: Text('All admins')),
            ],
            onChanged: (v) => setDialogState(() => target = v ?? 'all'),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      )),
    ) ?? false;
    if (!result || title.text.trim().isEmpty || message.text.trim().isEmpty) {
      title.dispose(); message.dispose(); return;
    }
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Send notification?',
      message: 'Are you sure you want to send this notification to ${target == 'admins' ? 'all admins' : 'all customers'}?',
      confirmLabel: 'Yes, send',
      cancelLabel: 'No',
    );
    if (!confirmed) {
      title.dispose();
      message.dispose();
      return;
    }
    try {
      final role = target == 'admins' ? 'admin' : 'customer';
      final users = await supabase.from('profiles').select('id').eq('role', role);
      for (final user in List<Map<String, dynamic>>.from(users)) {
        final id = user['id']?.toString();
        if (id != null && id.isNotEmpty) {
          await createKleenovaNotification(userId: id, title: title.text.trim(), message: message.text.trim(), type: 'announcement');
        }
      }
      if (mounted) { final future = _loadNotifications(); setState(() { notificationsFuture = future; }); _message('Notification sent.'); }
    } catch (e) {
      if (mounted) _message('Could not send notification: $e');
    } finally {
      title.dispose(); message.dispose();
    }
  }

  Future<void> _deleteAdminNotification(String id) async {
    final confirmed = await confirmKleenovaAction(
      context,
      title: 'Delete notification?',
      message: 'Are you sure you want to delete this notification?',
      confirmLabel: 'Yes, delete',
      cancelLabel: 'No',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await deleteNotification(id);
      if (mounted) { final future = _loadNotifications(); setState(() { notificationsFuture = future; }); }
    } catch (e) { if (mounted) _message('Could not delete notification: $e'); }
  }

  Future<void> _markAdminNotificationRead(String id) async {
    try {
      await markNotificationRead(id);
      if (!mounted) return;
      setState(() {
        notificationsFuture = _loadNotifications();
      });
      // Refresh the drawer count from the saved notification records.
      await notificationsFuture;
    } catch (e) {
      if (mounted) _message('Could not update notification: $e');
    }
  }

  List<Map<String, dynamic>> _deduplicateAdminNotifications(
      List<Map<String, dynamic>> notifications) {
    final sorted = List<Map<String, dynamic>>.from(notifications);
    sorted.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    final seenBookingIds = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final notification in sorted) {
      final bookingId = (notification['booking_id'] ?? '').toString().trim();
      if (bookingId.isEmpty) {
        result.add(notification);
        continue;
      }
      // A booking should have one current admin alert at a time. Because rows are
      // newest-first, a paid/cancelled/rescheduled update replaces older alerts.
      if (seenBookingIds.add(bookingId)) result.add(notification);
    }
    return result;
  }

  Widget _adminNotificationsContent() => FutureBuilder<List<Map<String, dynamic>>>(
    future: notificationsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      if (snapshot.hasError) return _errorCard('Could not load notifications: ${snapshot.error}');
      final rawRows = snapshot.data ?? <Map<String, dynamic>>[];
      final rows = _deduplicateAdminNotifications(rawRows);
      final unread = rows.where((n) => n['is_read'] != true).length;
      final filteredRows = rows.where((n) => adminNotificationFilter == 'All' || (adminNotificationFilter == 'Unread' ? n['is_read'] != true : n['is_read'] == true)).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$unread unread • ${rows.length} total', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          if (unread > 0) TextButton.icon(onPressed: () => _markAllForSection('Notifications'), icon: const Icon(Icons.done_all_rounded, size: 17), label: const Text('Mark all read')),
          if (rows.isNotEmpty) IconButton(tooltip: 'Delete all', onPressed: () => _deleteSectionRecords('Notifications'), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
        ]),
        const SizedBox(height: 10),
        _filterChips(const ['All', 'Unread', 'Read'], adminNotificationFilter, (v) => setState(() => adminNotificationFilter = v)),
        const SizedBox(height: 10),
        if (filteredRows.isEmpty) _emptyCard(rows.isEmpty ? 'No notification records yet.' : 'No notifications match this filter.'),
        ...filteredRows.map((n) => Container(
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: n['is_read'] == true ? Theme.of(context).colorScheme.surface : const Color(0xFFFFF1EC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: n['is_read'] == true ? beige : const Color(0xFFFF8A65), width: n['is_read'] == true ? 1 : 1.5),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: n['is_read'] == true ? beige : coffee, child: Icon(n['is_read'] == true ? Icons.notifications_none : Icons.notifications_active, color: n['is_read'] == true ? coffee : Colors.white)),
            const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text('${n['title'] ?? 'Notification'}', style: TextStyle(fontWeight: n['is_read'] == true ? FontWeight.w600 : FontWeight.w800))), if (n['is_read'] != true) const Text('UNREAD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: caramel))]),
              const SizedBox(height: 4), Text('${n['message'] ?? ''}'),
              const SizedBox(height: 6), Text('User: ${n['user_id'] ?? '—'} • ${n['created_at'] ?? ''}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
            ])),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (n['is_read'] != true) IconButton(tooltip: 'Mark as read', onPressed: () => _markAdminNotificationRead(n['id'].toString()), icon: const Icon(Icons.done_rounded, color: coffee)),
              if ((n['booking_id'] ?? '').toString().isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final id = n['booking_id'].toString();
                    try {
                      final found = await supabase.from('bookings').select().eq('id', id).maybeSingle();
                      if (found == null) { if (mounted) _message('The related booking could not be found.'); return; }
                      if (!mounted) return;
                      await _showBookingDetails(Map<String, dynamic>.from(found));
                    } catch (e) { if (mounted) _message('Could not open booking details: $e'); }
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View Details'),
                ),
              IconButton(tooltip: 'Delete', onPressed: () => _deleteAdminNotification(n['id'].toString()), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
            ]),
          ]),
        )),
      ]);
    },
  );

  Widget _adminMiniStat(String label, String value, IconData icon, Color tint) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE5D7CC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: tint.withOpacity(.11), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: tint, size: 17)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 1),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );

  Widget _content() {
    switch (section) {
      case 'Users':
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
            if (snapshot.hasError) return _errorCard('Could not load users: ${snapshot.error}');
            final users = snapshot.data ?? <Map<String, dynamic>>[];
            final customers = users.where((u) => (u['role'] ?? 'customer').toString().toLowerCase() == 'customer').length;
            final admins = users.where((u) => (u['role'] ?? '').toString().toLowerCase() == 'admin').length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Manage users', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 3),
                  Text('Customer and admin accounts', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ])),
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.people_alt_rounded, color: coffee)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _adminMiniStat('Total', '${users.length}', Icons.groups_rounded, const Color(0xFF176B87))),
                const SizedBox(width: 9),
                Expanded(child: _adminMiniStat('Customers', '$customers', Icons.person_outline_rounded, coffee)),
                const SizedBox(width: 9),
                Expanded(child: _adminMiniStat('Admins', '$admins', Icons.admin_panel_settings_outlined, const Color(0xFF7B61A8))),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: Text('User accounts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface))),
                Text('${users.length}', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : coffee), fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 10),
              if (users.isEmpty) _emptyCard('No user profiles found.'),
              ...users.map((u) {
                final name = (u['full_name'] ?? 'Unnamed user').toString();
                final email = (u['email'] ?? 'No email').toString();
                final role = (u['role'] ?? 'customer').toString().toLowerCase();
                final isAdmin = role == 'admin';
                final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((v) => v[0]).join().toUpperCase();
                return Material(color: Colors.transparent, borderRadius: BorderRadius.circular(21), child: InkWell(onTap: () => _showUserDetails(u), borderRadius: BorderRadius.circular(21), child: Container(
                  margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(21), border: Border.all(color: const Color(0xFFE5D7CC)), boxShadow: const [BoxShadow(color: Color(0x07000000), blurRadius: 12, offset: Offset(0, 4))]),
                  child: Row(children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(color: isAdmin ? const Color(0xFFE8DEF4) : const Color(0xFFF0DED0), shape: BoxShape.circle), alignment: Alignment.center, child: Text(initials, style: TextStyle(color: isAdmin ? const Color(0xFF6D4C93) : coffee, fontWeight: FontWeight.w900))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 3),
                      Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 7),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: isAdmin ? const Color(0xFFEDE4F7) : const Color(0xFFF4E9DF), borderRadius: BorderRadius.circular(14)), child: Text(isAdmin ? 'ADMIN' : 'CUSTOMER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .4, color: isAdmin ? const Color(0xFF6D4C93) : coffee))),
                    ])),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: coffee),
                  ]),
                )));
              }),
            ]);
          },
        );
      case 'Bookings':
        return _bookingsContent();
      case 'Cleaners':
        return _cleanersSection();
      case 'Services':
        return _servicesSection();
      case 'Payments':
        return _paymentsContent();
      case 'Notifications':
        return _adminNotificationsContent();
      case 'Reviews':
        return _reviewsContent();
      case 'Reports':
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadBookings(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError) return _errorCard('Could not load reports: ${snap.error}');

            final rows = snap.data ?? <Map<String, dynamic>>[];
            final now = DateTime.now();
            final month = rows.where((b) {
              final d = DateTime.tryParse((b['booking_date'] ?? '').toString());
              return d != null && d.year == now.year && d.month == now.month;
            }).toList();

            final completed = month.where(
              (b) => (b['status'] ?? '').toString().toLowerCase() == 'completed',
            ).length;
            final cancelled = month.where(
              (b) => ['cancelled', 'canceled'].contains(
                (b['status'] ?? '').toString().toLowerCase(),
              ),
            ).length;
            final active = month.length - completed - cancelled;

            final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
            final daily = List<int>.filled(daysInMonth, 0);
            for (final b in month) {
              final d = DateTime.tryParse((b['booking_date'] ?? '').toString());
              if (d != null && d.day >= 1 && d.day <= daysInMonth) {
                daily[d.day - 1]++;
              }
            }

            final weekCount = ((daysInMonth + 6) ~/ 7);
            final weekly = List<int>.filled(weekCount, 0);
            for (var i = 0; i < daily.length; i++) {
              weekly[i ~/ 7] += daily[i];
            }

            final revenue = month.fold<double>(0, (sum, b) {
              final status = (b['status'] ?? '').toString().toLowerCase();
              if (status == 'cancelled' || status == 'canceled') return sum;
              return sum + ((b['service_price'] as num?)?.toDouble() ?? 0);
            });

            final surface = Theme.of(context).colorScheme.surface;
            final onSurface = Theme.of(context).colorScheme.onSurface;
            final muted = Theme.of(context).colorScheme.onSurfaceVariant;

            Widget reportMetric({
              required String label,
              required String value,
              required String caption,
              required IconData icon,
              required Color accent,
            }) {
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: beige.withOpacity(.75)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.035),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(.11),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, size: 19, color: accent),
                          ),
                          const Spacer(),
                          Icon(Icons.arrow_outward_rounded, size: 15, color: muted),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Text(
                        value,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // REPORT HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6F3E32), Color(0xFF8A5140)],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: coffee.withOpacity(.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.13),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withOpacity(.18)),
                        ),
                        child: const Icon(
                          Icons.insights_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Performance overview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${now.month}/${now.year} • Booking activity at a glance',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // KPI GRID
                Row(
                  children: [
                    reportMetric(
                      label: 'Bookings',
                      value: '${month.length}',
                      caption: 'Total this month',
                      icon: Icons.calendar_month_rounded,
                      accent: deepSage,
                    ),
                    const SizedBox(width: 10),
                    reportMetric(
                      label: 'Completed',
                      value: '$completed',
                      caption: 'Successfully finished',
                      icon: Icons.check_circle_outline_rounded,
                      accent: sage,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    reportMetric(
                      label: 'Active',
                      value: '$active',
                      caption: 'Still in progress',
                      icon: Icons.timelapse_rounded,
                      accent: sky,
                    ),
                    const SizedBox(width: 10),
                    reportMetric(
                      label: 'Cancelled',
                      value: '$cancelled',
                      caption: 'Cancelled bookings',
                      icon: Icons.cancel_outlined,
                      accent: coral,
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // REVENUE STRIP
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEAD8C9)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: champagne.withOpacity(.18),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.payments_outlined,
                          color: Color(0xFFB47A19),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimated booking value',
                              style: TextStyle(
                                color: muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₱${revenue.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.trending_up_rounded, color: sage),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // DAILY ACTIVITY
                _reportChartCard(
                  title: 'Daily activity',
                  subtitle: 'Bookings recorded for each day',
                  child: _reportLineChart(daily),
                ),

                // WEEKLY ACTIVITY
                _reportChartCard(
                  title: 'Weekly volume',
                  subtitle: 'Compare booking volume across this month',
                  child: _reportBarChart(weekly),
                ),

                // STATUS
                _reportChartCard(
                  title: 'Booking status',
                  subtitle: 'Current monthly status distribution',
                  child: _reportStatusChart(
                    active: active,
                    completed: completed,
                    cancelled: cancelled,
                  ),
                ),

                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _showReports,
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('View full report'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        );

      case 'Reschedule Requests':
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadRescheduleRequests(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError) {
              return _errorCard('Could not load reschedule requests: ${snap.error}');
            }

            final requests = snap.data ?? <Map<String, dynamic>>[];
            final pending = requests.where(
              (r) => (r['status'] ?? 'pending').toString().toLowerCase() == 'pending',
            ).length;

            if (requests.isEmpty) {
              return _emptyCard('No reschedule requests yet.');
            }

            final onSurface = Theme.of(context).colorScheme.onSurface;
            final muted = Theme.of(context).colorScheme.onSurfaceVariant;

            Widget scheduleTile({
              required String title,
              required String date,
              required String time,
              required bool requested,
            }) {
              return Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: requested
                      ? const Color(0xFFEAF7F5)
                      : const Color(0xFFF5F0EC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: requested
                        ? const Color(0xFFCBE9E4)
                        : const Color(0xFFE5D9D1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: requested
                            ? deepSage.withOpacity(.12)
                            : coffee.withOpacity(.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        requested
                            ? Icons.event_repeat_rounded
                            : Icons.event_available_rounded,
                        color: requested ? deepSage : coffee,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: requested ? deepSage : muted,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            date.isEmpty && time.isEmpty
                                ? 'Not recorded'
                                : '$date  •  $time',
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // REQUEST HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: beige),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x09000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: mist,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.event_repeat_rounded,
                          color: deepSage,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule changes',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              pending == 0
                                  ? 'No requests waiting for approval'
                                  : '$pending request${pending == 1 ? '' : 's'} waiting for review',
                              style: TextStyle(color: muted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: pending > 0
                              ? const Color(0xFFFFE7DE)
                              : const Color(0xFFE8F3E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '$pending PENDING',
                          style: TextStyle(
                            color: pending > 0 ? coral : sage,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Delete all',
                      onPressed: requests.isNotEmpty
                          ? () => _deleteSectionRecords('Reschedule Requests')
                          : null,
                      style: IconButton.styleFrom(
                        foregroundColor: coral,
                        backgroundColor: const Color(0xFFFFECE7),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ...requests.map((r) {
                  final unread = r['is_read'] != true;
                  final status = (r['status'] ?? 'pending').toString().toLowerCase();
                  final isPending = status == 'pending';
                  final isApproved = status == 'approved';
                  final oldDate = (r['old_date'] ?? '').toString();
                  final oldTime = (r['old_time'] ?? '').toString();
                  final newDate = (r['requested_date'] ?? '').toString();
                  final newTime = (r['requested_time'] ?? '').toString();

                  final statusColor = isPending
                      ? const Color(0xFFC17A16)
                      : isApproved
                          ? sage
                          : coral;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 13),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: unread ? const Color(0xFFFF9A7A) : beige,
                        width: unread ? 1.4 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.035),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: unread
                                      ? const Color(0xFFFFEEE8)
                                      : const Color(0xFFF2EAE4),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  unread
                                      ? Icons.notifications_active_outlined
                                      : Icons.event_repeat_rounded,
                                  color: unread ? coral : coffee,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (r['customer_name'] ?? 'KLEENOVA customer').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: onSurface,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Reschedule request · Booking ${r['booking_id'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (unread)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFECE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: coral,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Schedule comparison
                          scheduleTile(
                            title: 'CURRENT SCHEDULE',
                            date: oldDate,
                            time: oldTime,
                            requested: false,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: SizedBox(
                              height: 20,
                              child: Row(
                                children: [
                                  Container(
                                    width: 1.5,
                                    color: beige,
                                  ),
                                  const SizedBox(width: 9),
                                  const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 16,
                                    color: deepSage,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          scheduleTile(
                 



           title: 'REQUESTED SCHEDULE',
                            date: newDate,
                            time: newTime,
                            requested: true,
                          ),

                          if ((r['reason'] ?? '').toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 13),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF9F5),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 17,
                                    color: coffee,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      (r['reason'] ?? '').toString(),
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 13),
                          Row(
                            children: [
                              Text(
                                _prettyValue(status),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => _showRescheduleDetails(r),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                ),
                                label: const Text('Details'),
                              ),
                              if (unread)
                                IconButton(
                                  tooltip: 'Mark read',
                                  onPressed: () => _markRescheduleRead(
                                    r['id'].toString(),
                                  ),
                                  icon: const Icon(Icons.done_rounded, size: 19),
                                ),
                            ],
                          ),

                          if (isPending) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _reviewReschedule(r, false),
                                    child: const Text('Reject'),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _reviewReschedule(r, true),
                                    icon: const Icon(Icons.check_rounded, size: 18),
                                    label: const Text('Approve'),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: 'Delete request',
                              onPressed: () => _deleteReschedule(
                                r['id'].toString(),
                              ),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: coral,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );

      case 'Activity Log':
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadActivityLogs(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError) {
              return _errorCard('Could not load activity logs: ${snap.error}');
            }

            final logs = snap.data ?? <Map<String, dynamic>>[];
            if (logs.isEmpty) return _emptyCard('No admin activity recorded yet.');

            final onSurface = Theme.of(context).colorScheme.onSurface;
            final muted = Theme.of(context).colorScheme.onSurfaceVariant;

            String activityTime(dynamic raw) {
              final parsed = DateTime.tryParse((raw ?? '').toString());
              if (parsed == null) return (raw ?? '').toString();
              final local = parsed.toLocal();
              final hour = local.hour == 0
                  ? 12
                  : local.hour > 12
                      ? local.hour - 12
                      : local.hour;
              final minute = local.minute.toString().padLeft(2, '0');
              final suffix = local.hour >= 12 ? 'PM' : 'AM';
              return '${local.month}/${local.day}/${local.year} • $hour:$minute $suffix';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ACTIVITY HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF5E8DE), Color(0xFFEAF2F2)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: beige),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: coffee,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin activity',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${logs.length} recorded action${logs.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.72),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${logs.where((l) => l['is_read'] != true).length} new',
                          style: const TextStyle(
                            color: coral,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Delete all',
                      onPressed: logs.isNotEmpty
                          ? () => _deleteSectionRecords('Activity Log')
                          : null,
                      style: IconButton.styleFrom(
                        foregroundColor: coral,
                        backgroundColor: const Color(0xFFFFECE7),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // TIMELINE
                ...List.generate(logs.length, (index) {
                  final log = logs[index];
                  final unread = log['is_read'] != true;
                  final isLast = index == logs.length - 1;
                  final action = (log['action'] ?? 'Admin action').toString();
                  final entity = (log['entity_type'] ?? 'record').toString();
                  final entityId = (log['entity_id'] ?? '').toString();

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 32,
                        child: Column(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: unread ? coral : coffee,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.surface,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (unread ? coral : coffee).withOpacity(.20),
                                    blurRadius: 0,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Container(
                                width: 2,
                                height: 155,
                                color: beige,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 13),
                          padding: const EdgeInsets.fromLTRB(15, 14, 12, 11),
                          decoration: BoxDecoration(
                            color: unread
                                ? const Color(0xFFFFF4EE)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: unread
                                  ? const Color(0xFFFFB095)
                                  : beige,
                              width: unread ? 1.2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.028),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      action,
                                      style: TextStyle(
                                        color: onSurface,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w900,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  if (unread)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFE2D9),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: coral,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4EEE9),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.folder_open_outlined,
                                      size: 15,
                                      color: coffee,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        '$entity${entityId.isEmpty ? '' : ' • $entityId'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                activityTime(log['created_at']),
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  if (unread)
                                    TextButton.icon(
                                      onPressed: () => _markActivityRead(
                                        log['id'].toString(),
                                      ),
                                      icon: const Icon(
                                        Icons.done_rounded,
                                        size: 15,
                                      ),
                                      label: const Text('Mark read'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: 'Delete log',
                                    onPressed: () => _deleteActivity(
                                      log['id'].toString(),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: coral,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            );
          },
        );

      default:
        return _overview();
    }
  }

  Future<void> _showUserDetails(Map<String, dynamic> user) async {
    final name = (user['full_name'] ?? 'User').toString();
    final email = (user['email'] ?? 'Not provided').toString();
    final phone = (user['phone'] ?? 'Not provided').toString();
    final role = (user['role'] ?? 'customer').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((v) => v[0]).join().toUpperCase();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .72,
        child: Container(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 24), children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFCAB8AE), borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('User profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface))),
              IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF1DED4), Color(0xFFE8F0F3)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE0CEC3))),
              child: Row(children: [
                Container(width: 62, height: 62, decoration: BoxDecoration(color: isAdmin ? const Color(0xFFE8DEF4) : const Color(0xFFF0DED0), shape: BoxShape.circle), alignment: Alignment.center, child: Text(initials, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: isAdmin ? const Color(0xFF6D4C93) : coffee))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink))),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: isAdmin ? const Color(0xFFEDE4F7) : const Color(0xFFF4E9DF), borderRadius: BorderRadius.circular(14)), child: Text(isAdmin ? 'ADMIN' : 'CUSTOMER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: isAdmin ? const Color(0xFF6D4C93) : coffee))),
                ])),
              ]),
            ),
            const SizedBox(height: 12),
            _detailSection('Contact information', [
              _detailLine('Email', email),
              _detailLine('Phone', phone),
            ]),
            _detailSection('Account', [
              _detailLine('Role', _prettyValue(role)),
              _detailLine('User ID', user['id'] ?? '—'),
            ]),
          ])),
        ),
      ),
    );
  }


  Widget _bookingStatusFilterChips({required int pending, required int cancelled}) {
    // These are booking-status filters, not notification indicators.
    // Do not show red unread-style badges based on pending/cancelled totals.
    const values = ['All', 'Pending', 'In Progress', 'Completed', 'Cancelled'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: values.map((value) {
          final selected = bookingStatusFilter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => setState(() => bookingStatusFilter = value),
              backgroundColor: null,
              selectedColor: const Color(0xFFDCEFE0),
              side: BorderSide.none,
              label: Text(value),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected
                    ? const Color(0xFF2E7D32)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _filterChips(List<String> values, String selected, ValueChanged<String> onSelected) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: values.map((value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(value),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
            selectedColor: const Color(0xFFDCEFE0),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: selected == value ? const Color(0xFF2E7D32) : Theme.of(context).colorScheme.onSurface),
          ),
        )).toList()),
      );

  Future<void> _pickAdminBookingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: bookingDateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Filter bookings by date',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: coffee,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    setState(() => bookingDateFilter = picked);
  }

  String _adminBookingDateLabel() {
    final date = bookingDateFilter;
    if (date == null) return 'Filter by date';
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _matchesAdminBookingDate(Map<String, dynamic> booking) {
    final filter = bookingDateFilter;
    if (filter == null) return true;

    final raw = (booking['booking_date'] ?? '').toString().trim();
    if (raw.isEmpty) return false;

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;

    return parsed.year == filter.year &&
        parsed.month == filter.month &&
        parsed.day == filter.day;
  }

  Widget _bookingsContent() =>_adminGeometricBackground(child: FutureBuilder<List<Map<String, dynamic>>>(
    future: bookingsFuture,
    builder: (context, snapshot) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      if (snapshot.hasError) return _errorCard('Could not load bookings: ${snapshot.error}');
      final records = snapshot.data ?? <Map<String, dynamic>>[];
      // Keep active and completed bookings together in one admin section.
      final all = records;
      final pending = all.where((b) => _adminBookingStatus(b) == 'pending').length;
      final cancelled = all.where((b) => ['cancelled', 'canceled'].contains(_adminBookingStatus(b))).length;
      final inProgress = all.where((b) => ['in_progress', 'currently_cleaning', 'on_the_way', 'confirmed'].contains(_adminBookingStatus(b))).length;
      final completed = records.where((b) => _adminBookingStatus(b) == 'completed').length;
      final search = adminBookingSearch.trim().toLowerCase();
      final filtered = all.where((b) {
        final value = _adminBookingStatus(b);
        final matchesStatus = bookingStatusFilter == 'All' ||
            (bookingStatusFilter == 'In Progress' && ['in_progress', 'currently_cleaning', 'on_the_way', 'confirmed'].contains(value)) ||
            value == bookingStatusFilter.toLowerCase().replaceAll(' ', '_');
        final matchesSearch = search.isEmpty || [
          b['customer_name'], b['service_name'], b['id'], b['customer_email'], b['customer_phone'],
        ].any((v) => (v ?? '').toString().toLowerCase().contains(search));
        return matchesStatus && matchesSearch && _matchesAdminBookingDate(b);
      }).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Booking management', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 3),
            Text('Review schedules, payments and assignments', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF2F2630), Color(0xFF3A2B2A)]
                    : const [Color(0xFFFFE4D7), Color(0xFFFFF1E7)],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isDark ? const Color(0xFF51413B) : const Color(0xFFE8C9B7),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? .10 : .045),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: InkWell(
              onTap: _pickAdminBookingDate,
              borderRadius: BorderRadius.circular(15),
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.calendar_month_rounded, color: coffee),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickAdminBookingDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_adminBookingDateLabel()),
              style: OutlinedButton.styleFrom(
                foregroundColor: coffee,
                side: const BorderSide(color: beige),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (bookingDateFilter != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear date filter',
              onPressed: () => setState(() => bookingDateFilter = null),
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                foregroundColor: coffee,
                backgroundColor: const Color(0xFFF1E1D6),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: adminBookingSearchController,
          onChanged: (value) => setState(() => adminBookingSearch = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search customer, service, booking ID or contact',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: adminBookingSearch.isEmpty ? null : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                adminBookingSearchController.clear();
                setState(() => adminBookingSearch = '');
              },
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _adminMiniStat('Pending', '$pending', Icons.schedule_rounded, const Color(0xFFB7791F))),
          const SizedBox(width: 9),
          Expanded(child: _adminMiniStat('In Progress', '$inProgress', Icons.cleaning_services_rounded, const Color(0xFF176B87))),
          const SizedBox(width: 9),
          Expanded(child: _adminMiniStat('Completed', '$completed', Icons.task_alt_rounded, const Color(0xFF2E7D32))),
          const SizedBox(width: 9),
          Expanded(child: _adminMiniStat('Cancelled', '$cancelled', Icons.cancel_outlined, const Color(0xFFD9534F))),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface))),
          Text('${filtered.length}', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : coffee), fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        _bookingStatusFilterChips(pending: pending, cancelled: cancelled),
        const SizedBox(height: 13),
        if (filtered.isEmpty) _emptyCard(search.isNotEmpty ? 'No bookings match “${adminBookingSearch.trim()}”.' : bookingDateFilter == null ? 'No bookings in this category.' : 'No bookings found for ${_adminBookingDateLabel()}.'),
        ...filtered.map(_bookingCard),
      ]);
    },
  ));

  Widget _bookingHistoryContent() => FutureBuilder<List<Map<String, dynamic>>>(
    future: bookingsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        return const Center(child: Padding(
          padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return _errorCard('Could not load booking history: ${snapshot.error}');
      }

      final completed = (snapshot.data ?? <Map<String, dynamic>>[])
          .where((b) => (b['status'] ?? '').toString().toLowerCase() == 'completed')
          .where((b) {
            // Search is intentionally limited to the customer's name only.
            final name = (b['customer_name'] ?? '').toString().toLowerCase();
            return name.contains(bookingHistorySearch.trim().toLowerCase());
          }).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Completed bookings are kept here for reference.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: bookingHistorySearchController,
            onChanged: (value) => setState(() => bookingHistorySearch = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search customer name',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: bookingHistorySearch.isEmpty ? null : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  bookingHistorySearchController.clear();
                  setState(() => bookingHistorySearch = '');
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text('Completed bookings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface))),
            Text('${completed.length}', style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(width: 6),
            if (completed.any((b) => b['history_is_read'] != true)) TextButton.icon(onPressed: () => _markAllForSection('Booking History'), icon: const Icon(Icons.done_all_rounded, size: 17), label: const Text('Mark all read')),
            if (completed.isNotEmpty) IconButton(tooltip: 'Delete history', onPressed: () => _deleteSectionRecords('Booking History'), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
          ]),
          const SizedBox(height: 10),
          if (completed.isEmpty)
            _emptyCard(bookingHistorySearch.trim().isEmpty
              ? 'No completed bookings yet.'
              : 'No completed bookings found for that customer name.'),
          ...completed.map(_bookingCard),
        ],
      );
    },
  );

  Future<void> _updatePaymentStatus(Map<String, dynamic> booking, String status) async {
    try {
      await supabase.from('bookings').update({'payment_status': status}).eq('id', booking['id']);
      await _markBookingNotificationsRead(booking['id']?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        bookingsFuture = _loadBookings();
        notificationsFuture = _loadNotifications();
      });
      await _refreshAdminBadgeCounts();
      _message('Payment marked ${status.toLowerCase()}.');
    } catch (e) {
      if (mounted) _message('Could not update payment status: $e');
    }
  }

  Widget _paymentStat(String label, String value, IconData icon, Color tint) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _cardDecoration(),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: tint.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: tint, size: 21),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
      ])),
    ]),
  );

  Future<void> _deletePaymentRecord(Map<String, dynamic> booking) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove payment record from admin?'),
      content: const Text('This hides the record from the admin side only. The customer will still see the booking.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep record')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
      ],
    )) ?? false;
    if (!ok) return;
    try {
      // Admin deletion is an internal record-management action. Do not create
      // a user notification here, otherwise the deleted record reappears in
      // the customer's notification list as a new 'payment record removed' item.
      final updated = await supabase.from('bookings')
          .update({'admin_deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', booking['id'])
          .select('id, admin_deleted_at');
      if (updated.isEmpty) throw Exception('No record was removed. Check the admin_deleted_at column and RLS UPDATE policy.');
      if (!mounted) return;
      setState(() { bookingsFuture = _loadBookings(); notificationsFuture = _loadNotifications(); });
      _message('Payment/booking record removed from admin view.');
    } catch (e) { if (mounted) _message('Could not delete payment record: $e'); }
  }

  Widget _paymentsContent() =>_adminGeometricBackground(child: FutureBuilder<List<Map<String, dynamic>>>(
    future: bookingsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      if (snapshot.hasError) return _errorCard('Could not load payments: ${snapshot.error}');
      final all = snapshot.data ?? <Map<String, dynamic>>[];
      // Admin Payments shows only successful payments. Pending, failed, and
      // cancelled bookings are intentionally excluded from this screen.
      final filtered = all.where((b) {
        final bookingStatus = (b['status'] ?? '').toString().toLowerCase();
        final paymentStatus = (b['payment_status'] ?? '').toString().toLowerCase();
        return paymentStatus == 'paid' &&
            bookingStatus != 'cancelled' &&
            bookingStatus != 'canceled';
      }).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Paid payments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        if (filtered.isEmpty) _emptyCard('No paid payments yet.'),
        ...filtered.map((b) {
          final paymentStatus = (b['payment_status'] ?? 'pending').toString().toLowerCase();
          final bookingStatus = (b['status'] ?? '').toString().toLowerCase();
          final isCancelled = bookingStatus == 'cancelled' || bookingStatus == 'canceled';
          final status = isCancelled ? 'cancelled' : paymentStatus;
          final isPaid = status == 'paid';
          final unread = b['_admin_payment_unread'] == true;
          final statusValue = paymentStatus;
          final statusColor = const Color(0xFF2E7D32);
          final amount = (b['service_price'] as num?)?.toDouble() ?? 0;
          final method = _prettyValue((b['payment_method'] ?? 'Not set').toString());
          final reference = (b['payment_reference'] ?? '').toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: unread ? const Color(0xFFEAF7EC) : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: unread ? const Color(0xFF4F9A5A) : beige, width: unread ? 1.8 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: unread ? const Color(0xFFDCEFE0) : beige, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.receipt_long_outlined, color: unread ? const Color(0xFF2E7D32) : coffee)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text((b['service_name'] ?? 'Service').toString(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface))), if (unread) const Text('NEW', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 10))]),
                  const SizedBox(height: 3),
                  Text('₱${amount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: statusColor.withOpacity(.12), borderRadius: BorderRadius.circular(20)), child: Text(_prettyValue(statusValue), style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 12),
              _detailLine('Method', method),
              if (reference.isNotEmpty) _detailLine('Reference', reference),
              _detailLine('Booking date', _bookingDateTime(b)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => _showBookingDetails(b), icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('View payment')),
                if (unread) OutlinedButton.icon(
                  onPressed: () async {
                    await _markPaymentNotificationsRead(b['id']?.toString() ?? '');
                    if (!mounted) return;
                    setState(() {
                      bookingsFuture = _loadBookings();
                      notificationsFuture = _loadNotifications();
                    });
                    await _refreshAdminBadgeCounts();
                  },
                  icon: const Icon(Icons.done_rounded, size: 18),
                  label: const Text('Mark read'),
                ),
                OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: () => _deletePaymentRecord(b), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Delete')),
              ]),
            ]),
          );
        }),
      ]);
    },
  ));

  Future<void> _markReviewRead(String id) async {
    try { await supabase.from('reviews').update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id); if (mounted) { reviewsFuture = _loadReviews(); setState(() => reviewsBadgeCount = 0); _refreshAdminBadgeCounts(); } }
    catch (e) { if (mounted) _message('Could not mark review as read: $e'); }
  }

  Future<void> _deleteReview(String id) async {
    final ok = await confirmKleenovaAction(context, title: 'Delete review?', message: 'Delete this customer review permanently?', confirmLabel: 'Delete', cancelLabel: 'Cancel', destructive: true);
    if (!ok) return;
    try { await supabase.from('reviews').delete().eq('id', id); if (mounted) { setState(() => reviewsFuture = _loadReviews()); _refreshAdminBadgeCounts(); } }
    catch (e) { if (mounted) _message('Could not delete review: $e'); }
  }

  Widget _reviewsContent() => FutureBuilder<List<Map<String, dynamic>>>(
    future: reviewsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) return _errorCard('Could not load reviews: ${snapshot.error}');
      final allReviews = snapshot.data ?? <Map<String, dynamic>>[];
      final services = <String>{'All services', ...allReviews.map((r) => (r['service_name'] ?? 'Cleaning service').toString())}.toList()..sort();
      if (!services.contains(reviewServiceFilter)) reviewServiceFilter = 'All services';
      final filtered = allReviews.where((r) {
        final service = (r['service_name'] ?? 'Cleaning service').toString();
        final rating = ((r['rating'] as num?)?.toInt() ?? 0).toString();
        return (reviewServiceFilter == 'All services' || service == reviewServiceFilter) &&
            (reviewRatingFilter == 'All ratings' || rating == reviewRatingFilter);
      }).toList();
      final average = allReviews.isEmpty ? 0.0 : allReviews.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / allReviews.length;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _reviewStat('Average Rating', allReviews.isEmpty ? '—' : average.toStringAsFixed(1), Icons.star_rounded, const Color(0xFFD49A25))),
          const SizedBox(width: 10),
          Expanded(child: _reviewStat('Total Reviews', '${allReviews.length}', Icons.rate_review_outlined, sage)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          if (allReviews.any((r) => r['is_read'] != true)) TextButton.icon(onPressed: () => _markAllForSection('Reviews'), icon: const Icon(Icons.done_all_rounded, size: 17), label: const Text('Mark all read')),
          const Spacer(),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: reviewServiceFilter, isExpanded: true, decoration: const InputDecoration(labelText: 'Filter by service', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)), items: services.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => reviewServiceFilter = v ?? 'All services'))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(value: reviewRatingFilter, isExpanded: true, decoration: const InputDecoration(labelText: 'Filter by rating', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)), items: ['All ratings', '5', '4', '3', '2', '1'].map((v) => DropdownMenuItem(value: v, child: Text(v == 'All ratings' ? v : '$v stars'))).toList(), onChanged: (v) => setState(() => reviewRatingFilter = v ?? 'All ratings'))),
        ]),
        const SizedBox(height: 14),
        if (filtered.isEmpty) _emptyCard(allReviews.isEmpty ? 'No customer reviews yet.' : 'No reviews match these filters.'),
        ...filtered.map(_adminReviewCard),
      ]);
    },
  );

  Widget _reviewStat(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(14), decoration: _cardDecoration(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [Flexible(child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))), if (label == 'Average Rating' && value != '—') ...[const SizedBox(width: 4), Icon(icon, color: color, size: 20)]]),
    ]),
  );

  Widget _adminReviewCard(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = (review['comment'] ?? '').toString().trim();
    final customer = (review['reviewer_name'] ?? 'KLEENOVA customer').toString();
    final service = (review['service_name'] ?? 'Cleaning service').toString();
    final dateValue = (review['created_at'] ?? '').toString();
    final date = dateValue.contains('T') ? dateValue.split('T').first : dateValue;
    final bookingDate = (review['booking_date'] ?? '').toString();
    final bookingId = (review['booking_id'] ?? '').toString();
    final unread = review['is_read'] != true;
    return Container(
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: unread ? const Color(0xFFFFF1EC) : Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: beige), boxShadow: [BoxShadow(color: coffee.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(customer, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFFF8E5), borderRadius: BorderRadius.circular(20)), child: Text('$rating ★', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)))]),
        const SizedBox(height: 7),
        Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, size: 19, color: const Color(0xFFD99016)))),
        const SizedBox(height: 9),
        Text(service, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        if (comment.isNotEmpty) ...[const SizedBox(height: 4), Text(comment, style: TextStyle(height: 1.35))] else ...[const SizedBox(height: 4), Text('No written comment', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic))],
        const SizedBox(height: 8),
        Text('Booking: ${bookingDate.isNotEmpty ? bookingDate : (bookingId.isNotEmpty ? bookingId : 'Unknown')}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        Text('Reviewed on ${date.isNotEmpty ? date : '—'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          if (unread) TextButton.icon(onPressed: () => _markReviewRead(review['id'].toString()), icon: const Icon(Icons.done_rounded, size: 16), label: const Text('Mark read')),
          const Spacer(),
        ]),
      ]),
    );
  }

  Widget _desktopHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = section == 'Bookings' ? 'All Bookings' : section;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        boxShadow: const [BoxShadow(color: Color(0x0F0F5C73), blurRadius: 14, offset: Offset(0, 4))],
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(
          color: isDark ? const Color(0xFF51413B) : const Color(0xFFE3EAEC),
        )),
      ),
      child: Row(children: [
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            Text(section == 'Overview' ? 'Here’s what’s happening today' : 'KLEENOVA Admin Dashboard', style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF30272A) : const Color(0xFFF7EEE8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? const Color(0xFF51413B) : beige),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 14, backgroundColor: coffee, child: Icon(Icons.person_rounded, size: 17, color: Colors.white)),
            const SizedBox(width: 9),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Admin', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              Text('Administrator', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ]),
        ),
      ]),
    );
  }

  Widget _desktopContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF171312) : const Color(0xFFF4F7F8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
        children: [
          if (section != 'Overview' && section != 'Booking History')
            Text(section == 'Bookings' ? 'All Bookings' : section,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          if (section != 'Overview' && section != 'Booking History') const SizedBox(height: 16),
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: _content(),
          )),
        ],
      ),
    );
  }

  Widget _mobileContent() => Container(
    color: const Color(0xFFF4F7F8),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        if (section != 'Overview' && section != 'Booking History')
          Text(section == 'Bookings' ? 'All Bookings' : section,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
        if (section != 'Overview' && section != 'Booking History') const SizedBox(height: 14),
        _content(),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      drawer: desktop ? null : _drawer(),
      appBar: desktop ? null : AppBar(title: Text(section == 'Bookings' ? 'All Bookings' : section)),
      floatingActionButton: section == 'Services'
          ? FloatingActionButton.extended(onPressed: addService, backgroundColor: coffee, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('Add service'))
          : section == 'Cleaners'
              ? FloatingActionButton.extended(onPressed: addCleaner, backgroundColor: coffee, foregroundColor: Colors.white, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add cleaner'))
              : section == 'Notifications'
                  ? FloatingActionButton.extended(onPressed: _sendNotification, backgroundColor: coffee, foregroundColor: Colors.white, icon: const Icon(Icons.send_rounded), label: const Text('Send notification'))
                  : null,
      body: desktop
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 285, child: _drawer(width: 285)),
              Expanded(child: Column(children: [
                _desktopHeader(),
                Expanded(child: _desktopContent()),
              ])),
            ])
          : _mobileContent(),
    );
  }
}


class ServiceEditorPage extends StatefulWidget {
  final Map<String, dynamic>? service;
  const ServiceEditorPage({super.key, this.service});
  @override State<ServiceEditorPage> createState() => _ServiceEditorPageState();
}

class _ServiceEditorPageState extends State<ServiceEditorPage> {
  final name = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final duration = TextEditingController(text: '2');
  static const categories = ['Cleaning', 'Maintenance', 'Repair', 'Home Care', 'Other'];
  String category = 'Cleaning';
  XFile? selectedImage;
  bool saving = false, active = true;
  String? existingImageUrl;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    if (s != null) {
      name.text = (s['name'] ?? '').toString();
      description.text = (s['description'] ?? '').toString();
      price.text = (s['price'] ?? '').toString();
      duration.text = (s['duration_hours'] ?? 2).toString();
      category = categories.contains(s['category']) ? s['category'].toString() : 'Cleaning';
      active = s['is_active'] != false;
      existingImageUrl = (s['image_url'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    name.dispose(); description.dispose(); price.dispose(); duration.dispose();
    super.dispose();
  }

  void message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (picked != null && mounted) setState(() => selectedImage = picked);
    } catch (e) {
      if (mounted) message('Could not open photo picker: $e');
    }
  }

  Future<String?> uploadImage() async {
    if (selectedImage == null) return null;
    final file = selectedImage!;
    final rawExt = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    final ext = ['jpg', 'jpeg', 'png', 'webp'].contains(rawExt) ? rawExt : 'jpg';
    final path = '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final contentType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
    await supabase.storage.from('service-images').uploadBinary(
      path, await file.readAsBytes(),
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return supabase.storage.from('service-images').getPublicUrl(path);
  }

  Future<void> save() async {
    final serviceName = name.text.trim();
    final parsedPrice = num.tryParse(price.text.trim());
    final parsedDuration = num.tryParse(duration.text.trim());
    if (serviceName.isEmpty || parsedPrice == null || parsedPrice < 0 || parsedDuration == null || parsedDuration <= 0) {
      message('Enter a service name, a valid price, and a duration greater than zero.');
      return;
    }
    final confirmed = await confirmKleenovaAction(
      context,
      title: widget.service == null ? 'Save service?' : 'Update service?',
      message: widget.service == null
          ? 'Are you sure you want to add this service?'
          : 'Are you sure you want to save these service changes?',
      confirmLabel: widget.service == null ? 'Yes, save' : 'Yes, update',
      cancelLabel: 'No',
    );
    if (!confirmed) return;

    setState(() => saving = true);
    try {
      final imageUrl = await uploadImage() ?? existingImageUrl;
      final payload = {
        'name': serviceName,
        'category': category,
        'description': description.text.trim(),
        'price': parsedPrice,
        'duration_hours': parsedDuration,
        'image_url': imageUrl,
        'is_active': active,
      };
      if (widget.service == null) {
        await supabase.from('services').insert(payload);
      } else {
        await supabase.from('services').update(payload).eq('id', widget.service!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => saving = false); message('Could not ${widget.service == null ? 'add' : 'update'} service: $e'); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.service == null ? 'Add a service' : 'Edit service')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [coffee, caramel]), borderRadius: BorderRadius.circular(22)),
        child: Row(children: [const Icon(Icons.cleaning_services_outlined, color: Colors.white, size: 32), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.service == null ? 'New cleaning service' : 'Update service details', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(widget.service == null ? 'Add the details customers will see.' : 'Edit the details customers will see.', style: const TextStyle(color: Colors.white70)),
          ]))])),
      const SizedBox(height: 22),
      InkWell(onTap: saving ? null : pickImage, borderRadius: BorderRadius.circular(18), child: Container(
        height: 190, decoration: BoxDecoration(color: beige, borderRadius: BorderRadius.circular(18), border: Border.all(color: caramel)),
        clipBehavior: Clip.antiAlias,
        child: selectedImage != null
          ? ImageBytesPreview(file: selectedImage!)
          : (existingImageUrl != null && existingImageUrl!.isNotEmpty
              ? Image.network(existingImageUrl!, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Center(child: Text('Choose service photo', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink)))))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, size: 44, color: coffee), SizedBox(height: 8), Text('Choose service photo', style: TextStyle(fontWeight: FontWeight.w600, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink))), Text('Tap to select from your device', style: TextStyle(fontSize: 12, color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : ink)))])),
      )),
      if (selectedImage != null) ...[
        const SizedBox(height: 6),
        TextButton.icon(onPressed: saving ? null : pickImage, icon: const Icon(Icons.photo_library_outlined), label: const Text('Change photo')),
      ],
      const SizedBox(height: 12),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Service name *', prefixIcon: Icon(Icons.label_outline))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Service category *', prefixIcon: Icon(Icons.category_outlined)), items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: saving ? null : (value) { if (value != null) setState(() => category = value); }),
      const SizedBox(height: 12),
      TextField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes))),
      const SizedBox(height: 12),
      TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price (₱) *', prefixIcon: Icon(Icons.payments_outlined))),
      const SizedBox(height: 12),
      TextField(controller: duration, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Duration in hours *', prefixIcon: Icon(Icons.schedule_outlined))),
      const SizedBox(height: 12),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Visible to customers'), subtitle: const Text('Turn off to keep this service hidden.'), value: active, activeColor: coffee, onChanged: (v) => setState(() => active = v)),
      const SizedBox(height: 20),
      ElevatedButton.icon(onPressed: saving ? null : save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
        label: Text(saving ? 'Uploading photo & saving…' : (widget.service == null ? 'Save service' : 'Update service'))),
    ]),
  );
}

class ImageBytesPreview extends StatelessWidget {
  final XFile file;
  const ImageBytesPreview({super.key, required this.file});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
    future: file.readAsBytes(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return Image.memory(Uint8List.fromList(snapshot.data!), fit: BoxFit.cover, width: double.infinity, height: 190);
    },
  );
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const KleenovaApp());
}
