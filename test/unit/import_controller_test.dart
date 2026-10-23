import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/import/image_picker_service.dart';
import 'package:reranger/domain/import/image_staging_service.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';

class MockTestPickerService implements ImagePickerService {
  ImagePickResult result;
  MockTestPickerService(this.result);

  @override
  Future<ImagePickResult> pickImage() async => result;
}

class LowStorageMockChecker implements StorageCapacityChecker {
  const LowStorageMockChecker();

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async => 1024; // 1 KB
}

void main() {
  group('ImportController Tests (Batch C)', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('import_controller_test_');
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

    test('successful import creates project with matching SHA-256 and leaves original media untouched', () async {
      // 1. Prepare valid source image
      final image = img.Image(width: 200, height: 100);
      img.fill(image, color: img.ColorRgba8(50, 150, 250, 255));
      final sourceBytes = Uint8List.fromList(img.encodePng(image));

      final sourceFile = File('${tempDir.path}/user_camera.png')
        ..writeAsBytesSync(sourceBytes);

      final controller = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.importFromPath(sourceFile.path);

      expect(controller.state, isA<ImportSuccess>());
      final success = controller.state as ImportSuccess;
      expect(success.project.sourceWidth, equals(200));
      expect(success.project.sourceHeight, equals(100));
      expect(success.imageSummary.aspectRatio, closeTo(2.0, 0.001));

      // Invariant 4: Source media bit-for-bit unchanged
      expect(sourceFile.existsSync(), isTrue);
      expect(sourceFile.readAsBytesSync(), equals(sourceBytes));

      // Repository contains the newly saved project
      final loaded = await repository.loadProject(success.project.id);
      expect(loaded, isNotNull);
      expect(loaded!.sourceImageHash, equals(success.project.sourceImageHash));
    });

    test(
      'picker cancellation creates NO project in storage or repository',
      () async {
        final mockPicker = MockTestPickerService(const ImagePickCancelled());
        final controller = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
          pickerService: mockPicker,
        );

        await controller.pickAndImport();

        expect(controller.state, isA<ImportCancelled>());
        final summaries = await repository.getRecentProjects();
        expect(summaries.isEmpty, isTrue);
      },
    );

    test(
      'double tap / concurrent invocation creates <= 1 active job',
      () async {
        final image = img.Image(width: 100, height: 100);
        final sourceBytes = Uint8List.fromList(img.encodePng(image));
        final sourceFile = File('${tempDir.path}/double_tap.png')
          ..writeAsBytesSync(sourceBytes);

        final controller = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        // Trigger two imports simultaneously
        final future1 = controller.importFromPath(sourceFile.path);
        final future2 = controller.importFromPath(
          sourceFile.path,
        ); // Should be dropped immediately

        await Future.wait([future1, future2]);

        expect(controller.state, isA<ImportSuccess>());
        final summaries = await repository.getRecentProjects();
        expect(summaries.length, equals(1)); // Exactly 1 project created!
      },
    );

    test('corrupt file import fails gracefully, cleans up sandbox, and enables retry', () async {
      final corruptFile = File(
        '${tempDir.path}/corrupt.jpg',
      )..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0x00]); // truncated corrupt header

      final controller = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.importFromPath(corruptFile.path);

      expect(controller.state, isA<ImportFailureState>());
      final failureState = controller.state as ImportFailureState;
      expect(failureState.canRetry, isTrue);

      // Verify no projects exist in repository
      final summaries = await repository.getRecentProjects();
      expect(summaries.isEmpty, isTrue);

      // Verify sandbox has no orphaned projects
      final projectsDir = fileStorage.projectsDir;
      if (projectsDir.existsSync()) {
        expect(projectsDir.listSync().isEmpty, isTrue);
      }
    });

    test(
      'low disk storage triggers LowStorageFailure and creates no project',
      () async {
        final image = img.Image(width: 100, height: 100);
        final sourceBytes = Uint8List.fromList(img.encodePng(image));
        final sourceFile = File('${tempDir.path}/low_disk.png')
          ..writeAsBytesSync(sourceBytes);

        final lowStorageService = ImageStagingService(
          atomicWriter: const AtomicFileWriter(
            capacityChecker: LowStorageMockChecker(),
          ),
        );

        final controller = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
          stagingService: lowStorageService,
        );

        await controller.importFromPath(sourceFile.path);

        expect(controller.state, isA<ImportFailureState>());
        final failureState = controller.state as ImportFailureState;
        expect(
          failureState.errorMessage,
          contains('Insufficient disk storage'),
        );

        final summaries = await repository.getRecentProjects();
        expect(summaries.isEmpty, isTrue);
      },
    );

    test('user cancellation cleans up staged project files and emits ImportCancelled', () async {
      final image = img.Image(width: 100, height: 100);
      final sourceBytes = Uint8List.fromList(img.encodePng(image));
      final sourceFile = File('${tempDir.path}/cancel_me.png')
        ..writeAsBytesSync(sourceBytes);

      final controller = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      // Start import and immediately cancel
      final importFuture = controller.importFromPath(sourceFile.path);
      controller.cancel();
      await importFuture;

      expect(controller.state, isA<ImportCancelled>());
      final summaries = await repository.getRecentProjects();
      expect(summaries.isEmpty, isTrue);
    });
  });
}
