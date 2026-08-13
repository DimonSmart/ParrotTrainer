import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.initialize();
  runApp(ParrotTrainerApp(controller: controller));
}

class ParrotTrainerApp extends StatelessWidget {
  const ParrotTrainerApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Попугайчик учится говорить',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B9B31),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F9EA),
      useMaterial3: true,
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFFFEFFFB),
        elevation: 3,
        shadowColor: Color(0x22317724),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
    ),
    home: HomeScreen(controller: controller),
  );
}
