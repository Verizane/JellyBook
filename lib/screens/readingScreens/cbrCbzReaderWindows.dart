// The purpose of this file is to allow the user to read the book/comic they have downloaded

import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jellybook/providers/updatePagenum.dart';
import 'package:isar/isar.dart';
import 'package:jellybook/models/entry.dart';
import 'package:jellybook/providers/progress.dart';
import 'package:jellybook/variables.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:jellybook/screens/AudioPicker.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:jellybook/widgets/AudioPlayerWidget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// cbr/cbz reader
class CbrCbzReaderWindows extends StatefulWidget {

  final String title;
  final String comicId;
  final bool isWindows;

  const CbrCbzReaderWindows({
    super.key,
    required this.title,
    required this.comicId,
    required this.isWindows
  });

  @override
  CbrCbzReaderWindowsState createState() => CbrCbzReaderWindowsState();
}

class CbrCbzReaderWindowsState extends State<CbrCbzReaderWindows> {
  late String title;
  late String comicId;
  int pageNum = 0;
  int pageNums = 0;
  double progress = 0.0;
  late String path;
  late List<String> chapters = [];
  late List<String> pages = [];
  late String direction;
  ZoomFactor zoomFactor = ZoomFactor();

  // audio variables
  String audioPath = '';
  AudioPlayer audioPlayer = AudioPlayer();
  bool isPlaying = false;
  Duration audioPosition = Duration();
  String audioId = '';

  void setDirection() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    direction = prefs.getString('readingDirection') ?? 'ltr';
    logger.f("direction: $direction");
  }

  Future<void> createPageList() async {
    // create a list of chapters
    // call getChaptersFromDirectory with path as a FileSystemEntity
    await getChaptersFromDirectory(Directory(path));
    logger.d("chapters: ${chapters.length}");
    List<String> formats = [
      ".jpg",
      ".jpeg",
      ".png",
      ".gif",
      ".webp",
      ".bmp",
      ".tiff"
      // also include all variations of capitalizations of these
    ];
    List<String> pageFiles = [];
    for (var chapter in chapters) {
      List<String> files =
          Directory(chapter).listSync().map((e) => e.path).toList();
      for (var file in files) {
        if (formats.any((element) => file.toLowerCase().endsWith(element))) {
          pageFiles.add(file);
        }
      }
    }
    pageFiles.sort();
    // reset pages to empty them and not concatenate
    pages = [];
    for (var page in pageFiles) {
      pages.add(page);
      pageNums++;
    }
    logger.d("pages: ${pages.length}");
  }

  Future<void> getData() async {
    final isar = Isar.getInstance();
    return await isar!.entrys
        .where()
        .idEqualTo(comicId)
        .findFirst()
        .then((value) {
      setState(() {
        pageNum = value!.pageNum;
        progress = value.progress;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    title = widget.title;
    comicId = widget.comicId;
    getData();
    setDirection();
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> saveProgress(int page) async {
    final isar = Isar.getInstance();
    final entry = await isar!.entrys.where().idEqualTo(comicId).findFirst();

    // update the entry
    entry!.pageNum = page;

    // update the progress
    entry.progress = (page / pages.length) * 100;

    // delete the old entry and add the new one
    await isar.writeTxn(() async {
      await isar.entrys.put(entry);
    });

    logger.d("saved progress");
    logger.d("page num: ${entry.pageNum}");
    updatePagenum(entry.id, entry.pageNum);
  }

  Future<void> getChapters() async {
    logger.d("getting chapters");
    // var status = await Permission.storage.status;
    // if (!status.isGranted) {
    //   await Permission.storage.request();
    // }

    // get the file path from the database
    final isar = Isar.getInstance();
    final entry = await isar!.entrys.where().idEqualTo(comicId).findFirst();

    // get the path
    path = entry!.folderPath;

    // print the entry
    logger.d("title: ${entry.title}");
    logger.d("path: ${entry.filePath}");
    logger.d("folder path: ${entry.folderPath}");
    logger.d("page num: ${entry.pageNum}");
    logger.d("progress: ${entry.progress}");
    logger.d("id: ${entry.id}");
    logger.d("downloaded: ${entry.downloaded}");
    // check if the entry is downloaded
    if (entry.downloaded) {
      progress = entry.progress;
      pageNum = entry.pageNum;
    }

    logger.d(path);
    File file = File(path);

    getChaptersFromDirectory(file);

    logger.d("Chapters:");
    logger.d(chapters.toString());
  }

  Future<void> getChaptersFromDirectory(FileSystemEntity directory) async {
    // Create a list of file types to check against
    List<String> fileTypes = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.tiff'
    ];

    // Check if the directory ends with any of the file types
    if (fileTypes.any((fileType) => directory.path
          .toLowerCase().endsWith(fileType))) {
      // If it does, add the parent directory to the chapters list if it's not already there
      if (!chapters.contains(directory.parent.path)) {
        chapters.add(directory.parent.path);
        logger.d("added ${directory.parent.path} to chapters");
      }
    } else {
      // If it doesn't, recursively check the files in the directory
      List<FileSystemEntity> files = [];
      try {
        files = Directory(directory.path).listSync();
        for (var file in files) {
          getChaptersFromDirectory(file);
        }
      } catch (e, s) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool useSentry = prefs.getBool('useSentry') ?? false;
        if (useSentry) await Sentry.captureException(e, stackTrace: s);
        logger.d(
          "Error: not a valid directory, its a file",
        );
      }
    }
  }

  Future<void> onAudioPickerPressed() async {
    var result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AudioPicker(),
      ),
    );
    if (result != null) {
      await getAudioId(result);
      logger.d('result: $result');
      setState(() => audioPath = result);
    }
  }

  Future<void> playAudio(String audioPath, Duration position) async {
    logger.d('audioPath: $audioPath');
    await audioPlayer.play(DeviceFileSource(audioPath), position: position);
    await audioPlayer.seek(position);
    FlutterBackgroundService().invoke("setAsForeground");
    setState(() {
      isPlaying = true;
    });

    // Listen to audio position changes and update audioPosition variable
    audioPlayer.onPositionChanged.listen((Duration newPosition) {
      audioPosition = newPosition;
    });
  }

  Future<void> savePosition() async {
    Isar? isar = Isar.getInstance();
    if (isar != null) {
      var entry =
          await isar.entrys.where().filter().idEqualTo(audioId).findFirst();
      if (entry != null) {
        await isar.writeTxn(() async {
          entry.pageNum = audioPosition.inSeconds;
          isar.entrys.put(entry);
        });
        logger.d('saved position: ${entry.pageNum}');
      }
    }
  }

  Future<void> pauseAudio() async {
    await savePosition();
    await audioPlayer.pause();
    FlutterBackgroundService().invoke("setAsBackground");
    setState(() {
      isPlaying = false;
    });
  }

  Future<void> stopAudio() async {
    await savePosition();
    await audioPlayer.stop();
    FlutterBackgroundService().invoke("setAsBackground");
    setState(() {
      isPlaying = false;
    });
  }

  Future<void> getAudioId(String audioPath) async {
    Isar? isar = Isar.getInstance();
    if (isar != null) {
      var entry = await isar.entrys
          .where()
          .filter()
          .filePathEqualTo(audioPath)
          .findFirst();
      if (entry != null) {
        setState(() {
          audioId = entry.id;
        });
      }
    }
  }

  Widget audioPlayerWidget() {
    if (audioPath == '') {
      return IconButton(
        icon: const Icon(Icons.audiotrack),
        onPressed: onAudioPickerPressed,
      );
    }
    return AudioPlayerWidget(
      audioPath: audioPath,
      isPlaying: isPlaying,
      progress: progress,
      onAudioPickerPressed: onAudioPickerPressed,
    );
  }
  // this is like a lock that prevent update the PageView multiple times while is 
  // scrolling
  bool pageIsScrolling = false;
  
  void _onZoomScroll(double offset) {
    if (offset > 0) {
      zoomFactor.zoomOut();
    } else {
      zoomFactor.zoomIn();
    }
    setState(() {
      transformationController.value = Matrix4.identity()..scale(zoomFactor.zoomFactor);
    });
  }

  TransformationController transformationController = TransformationController();
  double scale = 1.0;
  bool isPanEnabled = false;

  @override
  Widget build(BuildContext context) {
    transformationController.value = (Matrix4.identity()..scale(scale));
    // Dynamically fetch window size
    double windowWidth = MediaQuery.of(context).size.width;
    double windowHeight = MediaQuery.of(context).size.height;

    // Print the dynamic values for debugging
    logger.d('Window size: $windowWidth x $windowHeight');

    return FutureBuilder(
      future: getChapters(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
              actions: [
                audioPlayerWidget(),
                const SizedBox(
                  width: 10,
                ),
              ],
            ),
            body: FutureBuilder(
              // get progress requires the comicId
              future: getProgress(comicId),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return FutureBuilder(
                    future: createPageList(),
                    builder: (BuildContext context, AsyncSnapshot snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        return       
                            CustomInteractiveViewer(imageFileStrings: pages
                            );
                      } else {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                    }
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
              }
            )
          );
        } else {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
      }
    );
  }
}

class ZoomFactor {
  double zoomFactor = 1.0; // Initial zoom (1.0 = 100%)
  final double minZoomFactor = 0.3; // Minimum zoom (30%)
  final double maxZoomFactor = 3.0; // Maximum zoom (300%)

  void zoomIn() {
    zoomFactor = (zoomFactor - 0.1).clamp(minZoomFactor, maxZoomFactor);
  }

  void zoomOut() {
    zoomFactor = (zoomFactor + 0.1).clamp(minZoomFactor, maxZoomFactor);
  }
}



class CustomInteractiveViewer extends StatefulWidget {
  final List<String> imageFileStrings;
  const CustomInteractiveViewer({super.key, required this.imageFileStrings});

  @override
  CustomInteractiveViewerState createState() => CustomInteractiveViewerState();
}

class CustomInteractiveViewerState extends State<CustomInteractiveViewer> {
  late List<String> imageFileStrings;

  final TransformationController _transformationController = TransformationController();
  bool _isControlPressed = false;

  @override
  void initState() {
    super.initState();
    imageFileStrings = widget.imageFileStrings;
    logger.d("imageFileStrings: ${imageFileStrings.length}");
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
  
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (_isControlPressed) {
        // Handle zoom
        final scaleChange = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
        _transformationController.value = _transformationController.value.scaled(scaleChange);
      } else {
        // Handle scroll
        final double offsetChange = event.scrollDelta.dy < 0 ? 10.0 : -10.0;
        _transformationController.value = _transformationController.value.absolute()
          ..translate(0.0, -offsetChange);
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight) {
        setState(() {
          _isControlPressed = true;
        });
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight) {
        setState(() {
          _isControlPressed = false;
        });
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically fetch window size
    double windowWidth = MediaQuery.of(context).size.width;
    double windowHeight = MediaQuery.of(context).size.height;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              children: 
              [
                for (var imageFile in imageFileStrings)
                Image.file(
                  File(imageFile),
                  width: windowWidth,
                  height: windowHeight,
                  fit: BoxFit.fitHeight,
                ),
              ],
            ),
          )
        ),
      )
    );
  }
}
