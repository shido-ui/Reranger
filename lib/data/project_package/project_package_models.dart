import 'dart:convert';

/// Specification format identifier for portable Reranger project packages.
const String kRerangerPackageFormatId = 'reranger_project_package';
const int kRerangerPackageVersion = 1;

/// Manifest declaring files, paths, and cryptographic SHA-256 digests in a package.
class ProjectPackageManifest {
  final String format;
  final int version;
  final DateTime createdAt;
  final String originalProjectId;
  final String projectName;
  final String sourceImageHash;
  final Map<String, String> files; // Relative path -> SHA-256 hex digest

  const ProjectPackageManifest({
    this.format = kRerangerPackageFormatId,
    this.version = kRerangerPackageVersion,
    required this.createdAt,
    required this.originalProjectId,
    required this.projectName,
    required this.sourceImageHash,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'originalProjectId': originalProjectId,
    'projectName': projectName,
    'sourceImageHash': sourceImageHash,
    'files': files,
  };

  factory ProjectPackageManifest.fromJson(Map<String, dynamic> json) {
    final filesMap =
        (json['files'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {};

    return ProjectPackageManifest(
      format: json['format'] as String? ?? kRerangerPackageFormatId,
      version: json['version'] as int? ?? kRerangerPackageVersion,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      originalProjectId: json['originalProjectId'] as String? ?? '',
      projectName: json['projectName'] as String? ?? 'Untitled Project',
      sourceImageHash: json['sourceImageHash'] as String? ?? '',
      files: filesMap,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Verification report returned after inspecting a project package's manifest and files.
class PackageIntegrityReport {
  final bool isValid;
  final List<String> missingFiles;
  final List<String> corruptedFiles;
  final String details;

  const PackageIntegrityReport({
    required this.isValid,
    this.missingFiles = const [],
    this.corruptedFiles = const [],
    required this.details,
  });

  factory PackageIntegrityReport.valid() => const PackageIntegrityReport(
    isValid: true,
    details: 'Package checksums and structure verified successfully.',
  );

  factory PackageIntegrityReport.corrupt({
    List<String> missingFiles = const [],
    List<String> corruptedFiles = const [],
    required String details,
  }) => PackageIntegrityReport(
    isValid: false,
    missingFiles: missingFiles,
    corruptedFiles: corruptedFiles,
    details: details,
  );
}
