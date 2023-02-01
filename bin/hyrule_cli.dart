// @dart=2.9
import 'dart:io';
import 'package:clippy/server.dart' as clippy;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:smart_arg/smart_arg.dart';
import 'hyrule_cli.reflectable.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:convert';
import 'package:path/path.dart';

@SmartArg.reflectable
@Parser(
    description:
        'hyrule-cli - a CLI for uploading files to hyrule.pics on UNIX systems')
class Args extends SmartArg {
  @BooleanArgument(
      help: "enable watch mode in the current directory", short: "w")
  var watch = false;

  @FileArgument(help: "the config file to use")
  var configFile = File(Platform.isMacOS
      ? p.join(Platform.environment["HOME"],
          "Library/Application Support/hyrule-cli/hyrule.json")
      : Platform.isWindows
          ? p.join(Platform.environment["APPDATA"], "hyrule.json")
          : p.join(Platform.environment["HOME"], ".config/hyrule.json"));

  @BooleanArgument(help: "enable copying instead of printing to stdout")
  var copy = false;

  @HelpArgument()
  bool help = false;
}

String mapRandom(String input) {
  final exp = RegExp(r"{random:(.*?)}");

  return input.replaceAllMapped(
    exp,
    (match) =>
        match
            .group(1)
            .split("|")
            .elementAt(Random().nextInt(match.group(1).split("|").length)) ??
        "",
  );
}

Future<void> uploadFile(
    String name, List<int> file, String auth, String url, bool copy) async {
  final mimeType = lookupMimeType(name, headerBytes: file) ?? "text/plain";
  final fileName = jsonDecode((await http.put(
    Uri.https("hyrule.pics", "api/upload"),
    body: file,
    headers: {
      "Authorization": auth,
      "Content-Type": mimeType,
    },
  ))
      .body)["fileName"];

  final formattedURL = mapRandom(url).replaceFirst("{json:fileName}", fileName);

  if (copy) {
    await clippy.write(formattedURL);
  } else {
    print(formattedURL);
  }
}

Future<void> main(List<String> arguments) async {
  initializeReflectable();
  var args = Args()..parse(arguments);

  if (args.help) {
    print(args.usage());
    exit(0);
  }

  final configFile = args.configFile;
  if (!await configFile.exists()) {
    print("config file at ${configFile.path} does not exist");
    exit(1);
  }

  final parsedConfig = jsonDecode(await configFile.readAsString());
  final auth = parsedConfig["Headers"]["Authorization"];
  final url = parsedConfig["URL"];
  final copy = args.copy;

  if (args.watch) {
    Directory.current
        .watch(events: FileSystemEvent.create)
        .listen((event) async {
      final fileToUpload = File(event.path);
      if (!await fileToUpload.exists()) return;

      await uploadFile(basename(fileToUpload.path),
          fileToUpload.readAsBytesSync(), auth, url, copy);
    });
  } else if (args.extras.isEmpty) {
    await uploadFile(
        "name",
        ([for (var chunk in await stdin.toList()) ...chunk]).elementAt(0) ?? [],
        auth,
        url,
        copy);
  } else {
    final file = File(args.extras[0]);
    await uploadFile(
        basename(file.path), file.readAsBytesSync(), auth, url, copy);
  }
}
