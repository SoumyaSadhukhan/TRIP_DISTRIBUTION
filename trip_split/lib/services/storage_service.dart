// lib/services/storage_service.dart
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class StorageService {
  final String baseDirPath;
  SharedPreferences? _prefs;

  StorageService({this.baseDirPath = 'data/users', SharedPreferences? prefs})
      : _prefs = prefs;

  /// Ensures that the storage and SharedPreferences instance are initialized
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();

    if (!kIsWeb) {
      try {
        final dir = Directory(baseDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (_) {
        // Silently ignore directory creation errors on platforms/sandboxes without relative directory write access
      }
    }
  }

  /// Sanitizes username to create a safe key and file name
  String _sanitizeUsername(String username) {
    return username.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
  }

  String _getPrefKey(String cleanUsername) => 'user_data_$cleanUsername';
  static const String _registryKey = 'users_registry';

  /// Checks if a user already exists by username
  Future<bool> userExists(String username) async {
    await init();
    final clean = _sanitizeUsername(username);

    // 1. Check SharedPreferences direct key
    final prefKey = _getPrefKey(clean);
    if (_prefs?.containsKey(prefKey) == true) {
      return true;
    }

    // 2. Check SharedPreferences user registry
    final registry = _prefs?.getStringList(_registryKey) ?? [];
    if (registry.any((u) => _sanitizeUsername(u) == clean)) {
      return true;
    }

    // 3. Fallback: check file if available on non-web
    if (!kIsWeb) {
      try {
        final file = File('$baseDirPath/$clean.json');
        if (await file.exists()) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Saves or updates a user and their full trip/expense data
  Future<void> saveUser(UserModel user) async {
    await init();
    final clean = _sanitizeUsername(user.username);
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(user.toJson());

    // 1. Save to SharedPreferences (works on all platforms: Web, Android, iOS, Windows, Mac, Linux)
    final prefKey = _getPrefKey(clean);
    await _prefs?.setString(prefKey, jsonString);

    // Update username registry list
    final registry = _prefs?.getStringList(_registryKey) ?? [];
    if (!registry.contains(user.username)) {
      registry.add(user.username);
      await _prefs?.setStringList(_registryKey, registry);
    }

    // 2. Also try saving to local file as backup if on non-web
    if (!kIsWeb) {
      try {
        final dir = Directory(baseDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final file = File('$baseDirPath/$clean.json');
        await file.writeAsString(jsonString, flush: true);
      } catch (_) {
        // Silently ignore if file I/O isn't permitted in current sandbox
      }
    }
  }

  /// Loads a user from storage
  Future<UserModel?> loadUser(String username) async {
    await init();
    final clean = _sanitizeUsername(username);

    // 1. Try loading from SharedPreferences
    final prefKey = _getPrefKey(clean);
    final jsonStr = _prefs?.getString(prefKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
        return UserModel.fromJson(jsonMap);
      } catch (_) {}
    }

    // 2. Try loading from file on non-web if available
    if (!kIsWeb) {
      try {
        final file = File('$baseDirPath/$clean.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          final Map<String, dynamic> jsonMap = jsonDecode(content);
          final user = UserModel.fromJson(jsonMap);
          // Sync to SharedPreferences for fast subsequent reads
          await _prefs?.setString(prefKey, content);
          return user;
        }
      } catch (_) {}
    }

    // 3. Fallback: Search all users in registry or directory
    final allUsers = await getAllUsers();
    try {
      return allUsers.firstWhere(
        (u) => _sanitizeUsername(u.username) == clean,
      );
    } catch (_) {
      return null;
    }
  }

  /// Retrieves all saved users
  Future<List<UserModel>> getAllUsers() async {
    await init();
    final Map<String, UserModel> userMap = {};

    // 1. Load from SharedPreferences registry
    final registry = _prefs?.getStringList(_registryKey) ?? [];
    for (final uname in registry) {
      final clean = _sanitizeUsername(uname);
      final prefKey = _getPrefKey(clean);
      final jsonStr = _prefs?.getString(prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
          final user = UserModel.fromJson(jsonMap);
          userMap[clean] = user;
        } catch (_) {}
      }
    }

    // 2. Also check any additional keys in SharedPreferences
    final allKeys = _prefs?.getKeys() ?? {};
    for (final key in allKeys) {
      if (key.startsWith('user_data_')) {
        final clean = key.substring('user_data_'.length);
        if (!userMap.containsKey(clean)) {
          final jsonStr = _prefs?.getString(key);
          if (jsonStr != null) {
            try {
              final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
              final user = UserModel.fromJson(jsonMap);
              userMap[clean] = user;
            } catch (_) {}
          }
        }
      }
    }

    // 3. Also check files on non-web if available
    if (!kIsWeb) {
      try {
        final dir = Directory(baseDirPath);
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
          for (final file in files) {
            try {
              final content = await file.readAsString();
              final Map<String, dynamic> jsonMap = jsonDecode(content);
              final user = UserModel.fromJson(jsonMap);
              final clean = _sanitizeUsername(user.username);
              if (!userMap.containsKey(clean)) {
                userMap[clean] = user;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return userMap.values.toList();
  }

  /// Deletes a user
  Future<bool> deleteUser(String username) async {
    await init();
    final clean = _sanitizeUsername(username);
    bool deleted = false;

    final prefKey = _getPrefKey(clean);
    if (_prefs?.containsKey(prefKey) == true) {
      await _prefs?.remove(prefKey);
      deleted = true;
    }

    final registry = _prefs?.getStringList(_registryKey) ?? [];
    if (registry.remove(username) || registry.remove(clean)) {
      await _prefs?.setStringList(_registryKey, registry);
      deleted = true;
    }

    if (!kIsWeb) {
      try {
        final file = File('$baseDirPath/$clean.json');
        if (await file.exists()) {
          await file.delete();
          deleted = true;
        }
      } catch (_) {}
    }

    return deleted;
  }
}

