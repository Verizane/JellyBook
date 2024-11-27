import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:isar/isar.dart';
import 'package:jellybook/custom_widgets/custom_scroll_behavior.dart';
import 'package:jellybook/screens/loginScreen.dart';
import 'package:jellybook/screens/offlineBookReader.dart';
import 'package:jellybook/models/entry.dart';
import 'package:jellybook/models/folder.dart';
import 'package:jellybook/models/login.dart';
import 'package:jellybook/providers/languageProvider.dart';
import 'package:jellybook/providers/themeProvider.dart';
import 'package:jellybook/variables.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> get _localPath async {
  // get the directory that normally is located at /storage/emulated/0/Documents/
  Directory directory;
  if (Platform.isAndroid) {
    directory = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else {
    directory = await getApplicationDocumentsDirectory();
  }
  return directory.path;
}

Future<void> migrateToNewVersion() async {
  // check if a file exists for com.example.jellybook
  // if it does, move it to the new location
  // if it doesn't, do nothing

  // get the old path
  Directory oldPath = await _localPath.then((value) {
    return Directory(value.replaceFirst(
        "com.KaraWilson.JellyBook", "com.example.jellybook"));
  });
  // if the old path exists, move everything to the new path
  if (await oldPath.exists()) {
    moveFilesRecursive(oldPath);
    // delete the old path
    oldPath.deleteSync(recursive: true);
  }
}

void moveFilesRecursive(Directory dir) {
  dir.listSync().forEach((element) {
    if (element is File) {
      // move the file
      element.copySync(element.path
          .replaceFirst("com.example.jellybook", "com.KaraWilson.JellyBook"));
      element.deleteSync();
    } else if (element is Directory) {
      moveFilesRecursive(element);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // top bar always visible, bottom bar only visible when swiped up
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: [
    SystemUiOverlay.top,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // migrate to new app id
  if (Platform.isAndroid) {
    await migrateToNewVersion();
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();

  bool useSentry = prefs.getBool("useSentry") ?? false;

  // dio allow self signed certificates
  HttpOverrides.global = MyHttpOverrides();

  // path for isar database
  Directory dir = await getApplicationDocumentsDirectory();

  final isar = await Isar.open([EntrySchema, FolderSchema, LoginSchema],
      directory: dir.path);

  // set the localPath variable
  localPath = await _localPath;
  // check if localPath file exists
  if (!await File("$localPath/jellybook.log").exists()) {
    // create the file
    await File("$localPath/jellybook.log").create();
  }
  debugPrint("localPath: $localPath");

  // set the logStoragePath variable
  logStoragePath = "$localPath/Documents/";

  var logins = await isar.logins.where().findAll();
  if (logins.isNotEmpty) {
    prefs.setString("username", logins[0].username);
    if (useSentry) {
      await SentryFlutter.init(
        (options) {
          options.dsn = const String.fromEnvironment('SENTRY_DSN');
          options.tracesSampleRate = 1.0;
        },
        appRunner: () => runApp(MyApp(
          url: logins[0].serverUrl,
          username: logins[0].username,
          password: logins[0].password,
          prefs: prefs,
        )),
      );
    }
    runApp(MyApp(
      url: logins[0].serverUrl,
      username: logins[0].username,
      password: logins[0].password,
      prefs: prefs,
    ));
  } else {
    if (useSentry) {
      await SentryFlutter.init(
        (options) {
          options.dsn = const String.fromEnvironment('SENTRY_DSN');
          options.tracesSampleRate = 1.0;
        },
        appRunner: () => runApp(MyApp(prefs: prefs)),
      );
    }
    runApp(MyApp(prefs: prefs));
  }
}

class MyApp extends StatelessWidget {
  final String? url;
  final String? username;
  final String? password;
  final SharedPreferences prefs;

  const MyApp({
    super.key,
    this.url,
    this.username,
    this.password,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleChangeNotifier>(
            create: (context) => LocaleChangeNotifier(context, prefs)),
        ChangeNotifierProvider<ThemeChangeNotifier>(
            create: (context) => ThemeChangeNotifier(context, prefs)),
      ],
      builder: (context, _) {
        return Consumer2<LocaleChangeNotifier, ThemeChangeNotifier>(
            builder: (context, localeChangeNotifier, themeChangeNotifier, _) {
          Locale locale = localeChangeNotifier.locale;
          ThemeData themeData = themeChangeNotifier.getTheme;
          return MaterialApp(
            title: 'JellyBook',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            theme: themeData,
            scrollBehavior: CustomScrollBehavior(),
            // darkTheme: ThemeData.dark(),
            home: FutureBuilder(
              future: Connectivity().checkConnectivity(),
              builder: (context, snapshot) {
                SharedPreferences.getInstance().then((prefs) {
                  ThemeChangeNotifier themeChangeNotifier =
                      Provider.of<ThemeChangeNotifier>(context, listen: false);
                  // get the theme from shared preferences
                  String theme = prefs.getString('theme') ?? 'dark';
                  // set the theme
                  themeChangeNotifier.setTheme = theme.toString().toLowerCase();
                });
                if (snapshot.hasData) {
                  if (snapshot.data == ConnectivityResult.none) {
                    return OfflineBookReader(prefs: prefs);
                  } else {
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
        });
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
