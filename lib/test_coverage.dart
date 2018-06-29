// Copyright (c) 2018, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library test_coverage;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

final sep = path.separator;

void generateMainScript() {
  final testsPath = path.join(Directory.current.absolute.path, 'test');
  final testsRoot = new Directory(testsPath);
  final files = testsRoot.listSync(recursive: true);
  List<String> imports = [];
  List<String> mainBody = [];
  for (var item in files) {
    if (item is! File) continue;
    if (!item.path.endsWith('_test.dart')) continue;
    final alias = item.path.split(sep).last.replaceFirst('.dart', '');
    final importPath = item.absolute.path.replaceFirst('$testsPath$sep', '');
    imports.add("import '$importPath' as $alias;");
    mainBody.add('  $alias.main();');
  }
  imports.sort();

  StringBuffer buffer = new StringBuffer();
  buffer.writeln('// Auto-generated by test_coverage. Do not edit by hand.');
  buffer.writeln('// Consider adding this file to your .gitignore.');
  buffer.writeln();
  imports.forEach(buffer.writeln);
  buffer.writeln();
  buffer.writeln('void main() {');
  mainBody.forEach(buffer.writeln);
  buffer.writeln('}');
  final file = new File(path.join(testsPath, '.test_coverage.dart'));
  file.writeAsStringSync(buffer.toString());
}

Future<void> runTestsAndCollectCoverage() async {
  final testRunner = new TestRunner();
  print('Starting tests');
  testRunner.run();
  final port = await testRunner.observatoryPort;
  print('Observatory port $port.');
  final testSuccess = await testRunner.testsDone;
  if (!testSuccess) {
    print('Tests failed. Skipping coverage.');
    testRunner.dispose();
    return;
  }

  print('Tests completed.');
  print('Collecting coverage.');
  Process.runSync('collect_coverage', [
    '--uri=http://127.0.0.1:$port',
    '-o',
    'coverage.json',
    '--resume-isolates'
  ]);
  print('Formatting coverage.');
  Process.runSync('format_coverage', [
    '--packages=.packages',
    '-i',
    'coverage.json',
    '-o',
    'coverage.lcov',
    '-l',
    '--report-on',
    'lib/'
  ]);
  print('Done, results are in coverage.lcov.');
  testRunner.dispose();
}

class TestRunner {
  final Completer<int> _portCompleter = new Completer();
  final Completer<bool> _testsCompleter = new Completer();

  Future<int> get observatoryPort => _portCompleter.future;

  Future<bool> get testsDone => _testsCompleter.future;

  Process _process;
  StreamSubscription<String> _sub1;
  StreamSubscription<String> _sub2;
  Future<void> run() async {
    _process = await Process.start('dart', [
      '--pause-isolates-on-exit',
      '--enable_asserts',
      '--enable-vm-service',
      'test/.test_coverage.dart'
    ]);

    _sub1 = _process.stdout.transform(utf8.decoder).listen(_handleStdout);
    _sub2 = _process.stderr.transform(utf8.decoder).listen(_handleStderr);
  }

  void dispose() {
    _sub1.cancel();
    _sub2.cancel();
    _process.kill();
  }

  StringBuffer _stdout = new StringBuffer();

  void _handleStdout(String chunk) {
    _stdout.write(chunk);
    _checkObservatoryPort(_stdout.toString());
    _checkTestsDone(_stdout.toString());
  }

  void _handleStderr(String chunk) {
    // needed to release allocated resources.
  }

  void _checkObservatoryPort(String data) {
    if (_portCompleter.isCompleted) return;

    // Observatory listening on http://127.0.0.1:8181/
    if (!data.contains('\n')) return;
    final line = data.split('\n').first;
    final uri = Uri.parse(line.replaceFirst('Observatory listening on ', ''));
    _portCompleter.complete(uri.port);
  }

  void _checkTestsDone(String data) {
    if (_testsCompleter.isCompleted) return;
    if (data.contains('Some tests failed.')) {
      _testsCompleter.complete(false);
    }
    if (data.contains('All tests passed!')) {
      _testsCompleter.complete(true);
    }
  }
}
