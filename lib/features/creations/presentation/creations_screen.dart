import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../domain/project/project_entity.dart';
import '../../import/presentation/import_providers.dart';

/// SCR-15: Creations & Export Archive Screen (DEF-031).
/// Displays real saved project outputs and variants with honest status.
class CreationsScreen extends ConsumerStatefulWidget {
  const CreationsScreen({super.key});

  @override
  ConsumerState<CreationsScreen> createState() => _CreationsScreenState();
}

class _CreationsScreenState extends ConsumerState<CreationsScreen> {
  late Future<List<ProjectSummary>> _projectsFuture;

  @override
  void initState() {
    super.initState();
    _loadCreations();
  }

  void _loadCreations() {
    final repo = ref.read(projectRepositoryProvider);
    _projectsFuture = repo.getRecentProjects().then(
      (projects) =>
          projects.where((p) => p.outputReferencePath != null).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText = isDark
        ? AppColorTokens.darkTextPrimary
        : AppColorTokens.lightTextPrimary;
    final secondaryText = isDark
        ? AppColorTokens.darkTextSecondary
        : AppColorTokens.lightTextSecondary;
    final accentColor = isDark
        ? AppColorTokens.darkAccentPrimary
        : AppColorTokens.lightAccentPrimary;
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Creations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Creations',
            onPressed: () {
              setState(() {
                _loadCreations();
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<ProjectSummary>>(
          future: _projectsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final creations = snapshot.data ?? [];

            if (creations.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacingTokens.lg),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(AppSpacingTokens.xl),
                    decoration: BoxDecoration(
                      color: surfaceElevated,
                      borderRadius: AppRadiusTokens.borderLg,
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.collections_bookmark_outlined,
                          size: 56,
                          color: accentColor,
                        ),
                        const SizedBox(height: AppSpacingTokens.md),
                        Text(
                          'No Creations Saved Yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacingTokens.xs),
                        Text(
                          'When you export or save transformed images in the Studio, they will be archived here on your local device.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(AppSpacingTokens.md),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacingTokens.md,
                mainAxisSpacing: AppSpacingTokens.md,
                childAspectRatio: 0.85,
              ),
              itemCount: creations.length,
              itemBuilder: (context, index) {
                final item = creations[index];
                final outputFile = File(item.outputReferencePath!);
                final exists = outputFile.existsSync();

                return Card(
                  clipBehavior: Clip.antiAlias,
                  color: surfaceElevated,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadiusTokens.borderMd,
                    side: BorderSide(color: borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: exists
                            ? Image.file(
                                outputFile,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: secondaryText,
                                      ),
                                    ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: secondaryText,
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacingTokens.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Studio: ${item.activeStudio}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondaryText,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
