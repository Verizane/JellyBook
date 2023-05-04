import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:jellybook/screens/loginScreen.dart';
import 'package:isar/isar.dart';
import 'package:isar_flutter_libs/isar_flutter_libs.dart';
import 'package:jellybook/screens/offlineBookReader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jellybook/models/entry.dart';
import 'package:jellybook/models/folder.dart';
import 'package:jellybook/models/login.dart';
import 'package:logger/logger.dart';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:jellybook/providers/languageProvider.dart';
import 'package:jellybook/providers/themeProvider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // top bar always visible, bottom bar only visible when swiped up
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: [
    SystemUiOverlay.top,
  ]);

  //
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SharedPreferences prefs = await SharedPreferences.getInstance();

  // dio allow self signed certificates
  HttpOverrides.global = new MyHttpOverrides();

  final isar = await Isar.open([EntrySchema, FolderSchema, LoginSchema]);

  Logger.level = Level.debug;
  var logger = Logger();

  // if (kDebugMode) {
  //   try {
  //     // delete all entries in the database
  //     // get a list of all the entries ids
  //     var entries = await isar.entrys.where().findAll();
  //     var entryIds = entries.map((e) => e.isarId).toList();
  //     await isar.writeTxn(() async {
  //       isar.entrys.deleteAll(entryIds);
  //       logger.d("deleted ${entryIds.length} entries");
  //     });
  //     // delete all folders in the database
  //     // get a list of all the folders ids
  //     var folders = await isar.folders.where().findAll();
  //     var folderIds = folders.map((e) => e.isarId).toList();
  //     await isar.writeTxn(() async {
  //       isar.folders.deleteAll(folderIds);
  //       logger.d("deleted ${folderIds.length} folders");
  //     });
  //   } catch (e) {
  //     logger.e(e);
  //   }
  //   logger.d("cleared Isar boxes");
  // }

  var logins = await isar.logins.where().findAll();
  if (logins.length != 0) {
    logger.d("login username: " + logins[0].username);
    if (kDebugMode) {
      logger.d("login url: " + logins[0].serverUrl);
      logger.d("login password: " + logins[0].password);
    }
    logger.d("login found");
    runApp(MyApp(
      url: logins[0].serverUrl,
      username: logins[0].username,
      password: logins[0].password,
      prefs: prefs,
    ));
  } else {
    runApp(MyApp(prefs: prefs));
  }
}

class MyApp extends StatelessWidget {
  final String? url;
  final String? username;
  final String? password;
  final SharedPreferences? prefs;

  const MyApp({
    Key? key,
    this.url,
    this.username,
    this.password,
    this.prefs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleChangeNotifier>(
            create: (context) => LocaleChangeNotifier(context, prefs!)),
        ChangeNotifierProvider<ThemeChangeNotifier>(
            create: (context) => ThemeChangeNotifier(context, prefs!)),
      ],
      builder: (context, _) {
        final localeChangenotifier = Provider.of<LocaleChangeNotifier>(context);
        Locale locale2 = localeChangenotifier.locale;
        final themeChangenotifier = Provider.of<ThemeChangeNotifier>(context);
        ThemeData themeData = themeChangenotifier.getTheme;
        print("Locale (main.dart): " + locale2.toString());
        return MaterialApp(
          title: 'JellyBook',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale2 != null ? locale2 : Locale('en', 'US'),
          theme: themeData != null ? themeData : ThemeData.dark(),
          // darkTheme: ThemeData.dark(),
          home: FutureBuilder(
            future: Connectivity().checkConnectivity(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                if (snapshot.data == ConnectivityResult.none) {
                  return OfflineBookReader();
                } else {
                  // try to ping 1.1.1.1 or 8.8.8.8 or whatever their dns is and if network is reachable go to login screen
                  // if not, go to offline book reader
                  Socket.connect('1.1.1.1', 53).then((socket) {
                    socket.destroy();
                    return LoginScreen(
                      url: url,
                      username: username,
                      password: password,
                    );
                  }).catchError((e) {
                    return OfflineBookReader();
                  });
                  return LoginScreen(
                    url: url,
                    username: username,
                    password: password,
                  );
                }
              } else {
                return const CircularProgressIndicator();
              }
            },
          ),
        );
      },
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    HttpClient client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }
}
