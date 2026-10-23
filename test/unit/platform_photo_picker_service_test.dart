import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/platform/platform_photo_picker_service.dart';
import 'package:reranger/domain/import/image_picker_service.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformPhotoPickerService Unit Tests', () {
    const channelName = 'com.reranger.app/photo_picker';
    const channel = MethodChannel(channelName);
    late PlatformPhotoPickerService service;

    setUp(() {
      service = const PlatformPhotoPickerService(channel: channel);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns ImagePickSuccess when valid image file path is selected', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'pickImage') {
              return '/data/user/0/com.reranger.reranger/cache/picked_12345.png';
            }
            return null;
          });

      final result = await service.pickImage();
      expect(result, isA<ImagePickSuccess>());
      expect(
        (result as ImagePickSuccess).path,
        equals('/data/user/0/com.reranger.reranger/cache/picked_12345.png'),
      );
    });

    test('returns ImagePickCancelled when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return null;
          });

      final result = await service.pickImage();
      expect(result, isA<ImagePickCancelled>());
    });

    test(
      'returns ImagePickCancelled when platform returns empty string',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              return '   ';
            });

        final result = await service.pickImage();
        expect(result, isA<ImagePickCancelled>());
      },
    );

    test(
      'returns ImagePickPermissionDenied when PERMISSION_DENIED is thrown',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              throw PlatformException(
                code: 'PERMISSION_DENIED',
                message: 'Storage permission denied',
              );
            });

        final result = await service.pickImage();
        expect(result, isA<ImagePickPermissionDenied>());
        expect(
          (result as ImagePickPermissionDenied).message,
          equals('Storage permission denied'),
        );
      },
    );

    test(
      'returns ImagePickCancelled when CANCELLED platform exception is thrown',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              throw PlatformException(
                code: 'CANCELLED',
                message: 'User aborted',
              );
            });

        final result = await service.pickImage();
        expect(result, isA<ImagePickCancelled>());
      },
    );

    test('returns ImagePickFailure on arbitrary PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(
              code: 'PICK_FAILED',
              message: 'Activity crashed',
            );
          });

      final result = await service.pickImage();
      expect(result, isA<ImagePickFailure>());
      expect((result as ImagePickFailure).error, equals('Activity crashed'));
    });

    test('returns ImagePickFailure on MissingPluginException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw MissingPluginException('Not implemented');
          });

      final result = await service.pickImage();
      expect(result, isA<ImagePickFailure>());
      expect(
        (result as ImagePickFailure).error,
        contains('channel is not registered'),
      );
    });
  });

  group('ImportController Reset & Intake Lifecycle Tests', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('picker_test_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );
    });

    tearDown(() {
      database.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'reset clears executing lock, source path, and returns to ImportInitial',
      () {
        final controller = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
          initialState: const ImportCancelled(),
        );

        expect(controller.state, isA<ImportCancelled>());
        controller.reset();
        expect(controller.state, isA<ImportInitial>());
        expect(controller.isExecuting, isFalse);
      },
    );
  });
}
