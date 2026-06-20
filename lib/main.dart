import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'utils/constants.dart';
import 'utils/role_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const BrgySyncApp());
}

class BrgySyncApp extends StatelessWidget {
  const BrgySyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp.router(
        title: 'BrgySync',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kNavy),
          useMaterial3: true,
          textTheme: GoogleFonts.interTextTheme(),
          scaffoldBackgroundColor: kContentBg,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
