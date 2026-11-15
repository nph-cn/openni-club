// Downloads the exact catalog URLs for repeatable widget captures only.
// Files stay in .dart_tool, outside application assets and version control.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final catalog = jsonDecode(await File('assets/catalog.json').readAsString());
  final urls = <String>{};
  void collect(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if ([
              'coverUrl',
              'gameIconUrl',
              'bannerUrl',
              'imageUrl',
              'avatarUrl',
            ].contains(entry.key) &&
            '${entry.value}'.startsWith('https://')) {
          urls.add(entry.value as String);
        } else {
          collect(entry.value);
        }
      }
    } else if (value is List) {
      value.forEach(collect);
    }
  }

  collect(catalog);
  final dir = Directory('.dart_tool/catalog-media');
  await dir.create(recursive: true);
  final index = <String, String>{};
  final client = HttpClient();
  try {
    for (final url in urls) {
      final name = 'image-${index.length}.bin';
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      await response.pipe(File('${dir.path}/$name').openWrite());
      index[url] = name;
    }
    await File('${dir.path}/index.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(index));
    stdout.writeln(
      'Cached ${index.length} original catalog images for screenshots.',
    );
  } finally {
    client.close();
  }
}
