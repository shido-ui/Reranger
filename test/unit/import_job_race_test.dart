import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/import/image_picker_service.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';

class _FakePickerService implements ImagePickerService {
  int callCount = 0;
  Future<ImagePickResult> Function()? onPick;

  @override
  Future<ImagePickResult> pickImage() async {
    callCount++;
    if (onPick != null) {
      return onPick!();
    }
    return const ImagePickCancelled();
  }
}

void main() {
  group('DEF-023: Import Job Races, Token Isolation & Disposal Tests', () {
    late Directory tempDir;
    late ProjectDatabase db;
    late ProjectFileStorage storage;
    late LocalProjectRepository repository;
    late _FakePickerService pickerService;
    late ImportController controller;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('reranger_race_test_');
      db = ProjectDatabase.openInMemory();
      storage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(database: db, fileStorage: storage);
      pickerService = _FakePickerService();
      controller = ImportController(
        projectRepository: repository,
        fileStorage: storage,
        pickerService: pickerService,
      );
    });

    tearDown(() {
      controller.dispose();
      db.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'Rapid consecutive pickAndImport calls execute at most once concurrently',
      () async {
        pickerService.onPick = () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return const ImagePickCancelled();
        };

        // Fire two pick requests concurrently
        final future1 = controller.pickAndImport();
        final future2 = controller.pickAndImport();

        await Future.wait([future1, future2]);

        expect(pickerService.callCount, equals(1));
        expect(controller.state, isA<ImportCancelled>());
      },
    );

    test(
      'Cancellation increments active token and isolates subsequent job',
      () async {
        pickerService.onPick = () async {
          await Future.delayed(const Duration(milliseconds: 100));
          return const ImagePickCancelled();
        };

        final future1 = controller.pickAndImport();
        expect(controller.state, isA<ImportPicking>());

        // Cancel the active job
        controller.cancel();
        expect(controller.state, isA<ImportCancelled>());

        await future1;

        // Now start a fresh job
        pickerService.onPick = () async => const ImagePickFailure('Test error');
        await controller.pickAndImport();

        expect(controller.state, isA<ImportFailureState>());
        expect(
          (controller.state as ImportFailureState).errorMessage,
          equals('Test error'),
        );
      },
    );

    test(
      'Disposed controller does not throw on late async completion',
      () async {
        pickerService.onPick = () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return const ImagePickSuccess('/some/dummy/path.png');
        };

        final future = controller.pickAndImport();
        controller.dispose();

        // Should complete cleanly without throwing FlutterError or Bad state
        await future;
      },
    );
  });
}
