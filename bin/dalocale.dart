#!/usr/bin/env dart
library dalocale;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';

Future<void> main(List<String> args) async {
  final String input = args[0];
  final String output = args[1];

  final List<File> jsonFiles = getJsonFiles(input);
  final List<LocalizationGroup> groups = await getGroups(jsonFiles);

  generateFile(output, groups);
}

List<File> getJsonFiles(String root) {
  final Directory folder = Directory(root);
  final List<FileSystemEntity> contents =
      folder.listSync(recursive: false, followLinks: false);
  final List<File> result = <File>[];

  for (FileSystemEntity fileOrDir in contents) {
    if (fileOrDir is File) {
      result.add(File(fileOrDir.path));
    }
  }

  return result;
}

Future<List<LocalizationGroup>> getGroups(List<File> files) async {
  final List<LocalizationGroup> groups = <LocalizationGroup>[];

  for (File file in files) {
    final String filename = basename(file.path);
    final List<String> parts = filename.split('.');
    final List<LocalizationEntry> entries = await getEntries(file);

    groups.add(LocalizationGroup(parts[0].toLowerCase(), entries));
  }

  return groups;
}

Future<List<LocalizationEntry>> getEntries(File file) async {
  final String content = await file.readAsString();
  final Map<String, dynamic> json = jsonDecode(content);
  final List<LocalizationEntry> entries = <LocalizationEntry>[];

  for (String entry in json.keys) {
    entries.add(LocalizationEntry.create(entry, json[entry]));
  }

  return entries;
}

Future<void> generateFile(String output, List<LocalizationGroup> groups) async {
  final SourceFile file = SourceFile(output);
  file.clear();

  // imports
  file.write("import 'package:flutter/foundation.dart';\n");
  file.write("import 'package:flutter/widgets.dart';\n");
  file.write('\n');

  // base
  file.write(groups[0].base());

  // concrete
  for (LocalizationGroup group in groups) {
    file.write('\n${group.concrete()}');
  }

  // localized
  file.write('\nclass Localized {\n');
  file.write('  static BaseLocalized get;\n');
  file.write('\n');
  file.write(
      '  static List<Locale> locales = localized.keys.map((l) => Locale(l)).toList();\n');
  file.write('\n');
  file.write('  static Map<String, BaseLocalized> localized = {\n');

  for (int i = 0; i < groups.length; i++) {
    final LocalizationGroup group = groups[i];
    file.write('    ${group.mapEntry()}');

    if (i < (groups.length - 1)) {
      file.write(',\n');
    } else {
      file.write('\n');
    }
  }
  file.write('  };\n');
  file.write('\n');
  file.write('  static void load(Locale locale) {\n');
  file.write('    get = localized[locale.languageCode];\n');
  file.write('  }\n');
  file.write('}\n');

  // delegate
  file.write(
      '\nclass CustomLocalizationsDelegate extends LocalizationsDelegate {\n');
  file.write('  const CustomLocalizationsDelegate();\n');
  file.write('\n');
  file.write('  @override\n');
  file.write('  bool isSupported(Locale locale) => Localized.locales\n');
  file.write('      .map((l) => l.languageCode)\n');
  file.write('      .contains(locale.languageCode);\n');
  file.write('\n');
  file.write('  @override\n');
  file.write('  Future load(Locale locale) {\n');
  file.write('    Localized.load(locale);\n');
  file.write('    return SynchronousFuture(Object());\n');
  file.write('  }\n');
  file.write('\n');
  file.write('  @override\n');
  file.write(
      '  bool shouldReload(CustomLocalizationsDelegate old) => false;\n');
  file.write('}');
}

class LocalizationGroup {
  final String locale;
  final List<LocalizationEntry> entries;

  LocalizationGroup(this.locale, this.entries);

  String name() {
    return locale.toUpperCase();
  }

  String mapEntry() {
    return "'$locale': ${name()}Localized()";
  }

  String base() {
    String result = 'abstract class BaseLocalized {\n';

    for (LocalizationEntry entry in entries) {
      result += entry.lineBase();
    }

    result += '}\n';

    return result;
  }

  String concrete() {
    String result = 'class ${name()}Localized extends BaseLocalized {\n';

    for (LocalizationEntry entry in entries) {
      result += entry.lineConcrete();
    }

    result += '}\n';

    return result;
  }
}

class LocalizationEntry {
  final String key;
  final String value;
  final List<String> params;

  LocalizationEntry(this.key, this.value, [this.params = const <String>[]]);

  static LocalizationEntry create(String key, String value) {
    final RegExp exp = RegExp(r'\$\{([^\}]+)\}');
    final List<String> params =
        exp.allMatches(value).toList().map((Match r) => r.group(1)).toList();

    for (String param in params) {
      value = value.replaceFirst('\$\{$param\}', '\$\{$param.toString()\}');
    }

    value = value.replaceAll("'", "\\'");

    return LocalizationEntry(key, value, params);
  }

  String lineConcrete() {
    String result = '\n  @override\n';
    result += _line(value);

    return result;
  }

  String lineBase() {
    if (params.isEmpty) {
      return '\n  String get ${_sanitizeKey(key)};\n';
    } else {
      return '\n  String ${_sanitizeKey(key)}(${_parameterList(params)});\n';
    }
  }

  String _line(String value) {
    if (params.isEmpty) {
      return "  String get ${_sanitizeKey(key)} => '$value';\n";
    } else {
      return "  String ${_sanitizeKey(key)}(${_parameterList(params)}) => '$value';\n";
    }
  }

  String _sanitizeKey(String value) {
    String result = '';
    bool shouldCapitalize = false;

    for (int i = 0; i < value.length; i++) {
      final String char = value[i];

      if (char == '.') {
        shouldCapitalize = true;
      } else if (shouldCapitalize) {
        result += char.toUpperCase();
        shouldCapitalize = false;
      } else {
        result += char;
      }
    }

    return result;
  }

  String _parameterList(List<String> parameters) {
    String result = '';

    for (String parameter in parameters) {
      result += result.isEmpty ? '' : ', ';

      result += 'Object $parameter';
    }

    return result;
  }
}

class SourceFile {
  final File file;

  SourceFile(String path) : file = File(path);

  void clear() {
    file.writeAsStringSync('');
  }

  void write(String content) {
    file.writeAsStringSync(content, mode: FileMode.append);
  }
}
