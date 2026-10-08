import 'package:flutter/material.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';

class ModelFilterBottomSheet extends StatefulWidget {
  final ModelFilterCriteria initialCriteria;
  final List<OpenModel> allModels;
  final List<String> availableProviders;
  final ValueChanged<ModelFilterCriteria> onApply;
  final VoidCallback onReset;

  const ModelFilterBottomSheet({
    super.key,
    required this.initialCriteria,
    required this.allModels,
    required this.availableProviders,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<ModelFilterBottomSheet> createState() => _ModelFilterBottomSheetState();
}

class _ModelFilterBottomSheetState extends State<ModelFilterBottomSheet> {
  late RangeValues _sizeRange;
  late RangeValues _paramsRange;
  late RangeValues _ramRange;
  late Set<String> _selectedProviders;

  @override
  void initState() {
    super.initState();
    _sizeRange = widget.initialCriteria.sizeRangeMb ??
        const RangeValues(
          ModelFilterCriteria.defaultMinSizeMb,
          ModelFilterCriteria.defaultMaxSizeMb,
        );

    _paramsRange = widget.initialCriteria.paramsRangeB ??
        const RangeValues(
          ModelFilterCriteria.defaultMinParamsB,
          ModelFilterCriteria.defaultMaxParamsB,
        );

    _ramRange = widget.initialCriteria.ramRangeGb ??
        const RangeValues(
          ModelFilterCriteria.defaultMinRamGb,
          ModelFilterCriteria.defaultMaxRamGb,
        );

    _selectedProviders = Set<String>.from(widget.initialCriteria.selectedProviders);
  }

  ModelFilterCriteria _buildCurrentCriteria() {
    return ModelFilterCriteria(
      sizeRangeMb: _sizeRange,
      paramsRangeB: _paramsRange,
      ramRangeGb: _ramRange,
      selectedProviders: _selectedProviders,
    );
  }

  int _countMatchingModels() {
    final criteria = _buildCurrentCriteria();
    return widget.allModels.where((m) => criteria.matches(m)).length;
  }

  void _resetLocalFilters() {
    setState(() {
      _sizeRange = const RangeValues(
        ModelFilterCriteria.defaultMinSizeMb,
        ModelFilterCriteria.defaultMaxSizeMb,
      );
      _paramsRange = const RangeValues(
        ModelFilterCriteria.defaultMinParamsB,
        ModelFilterCriteria.defaultMaxParamsB,
      );
      _ramRange = const RangeValues(
        ModelFilterCriteria.defaultMinRamGb,
        ModelFilterCriteria.defaultMaxRamGb,
      );
      _selectedProviders.clear();
    });
  }

  String _formatSize(double mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toInt()} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchingCount = _countMatchingModels();
    final criteria = _buildCurrentCriteria();

    // Curated providers list
    final allKnownProviders = <String>{
      'Qwen',
      'Meta',
      'Google',
      'Mistral',
      'Microsoft',
      'DeepSeek',
      'Bartowski',
      ...widget.availableProviders,
    }.toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Filter Models',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (criteria.isActive) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${criteria.activeFilterCount} active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (criteria.isActive)
                    TextButton(
                      onPressed: _resetLocalFilters,
                      child: const Text('Reset All'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Filter options list
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                children: [
                  // --- 1. DOWNLOAD SIZE FILTER ---
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Download Size',
                    valueLabel: '${_formatSize(_sizeRange.start)} – ${_formatSize(_sizeRange.end)}',
                  ),
                  RangeSlider(
                    values: _sizeRange,
                    min: ModelFilterCriteria.defaultMinSizeMb,
                    max: ModelFilterCriteria.defaultMaxSizeMb,
                    divisions: 99,
                    labels: RangeLabels(
                      _formatSize(_sizeRange.start),
                      _formatSize(_sizeRange.end),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _sizeRange = values;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- 2. PARAMETER COUNT FILTER ---
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Parameters',
                    valueLabel: '${_paramsRange.start.toStringAsFixed(1)}B – ${_paramsRange.end.toStringAsFixed(1)}B',
                  ),
                  RangeSlider(
                    values: _paramsRange,
                    min: ModelFilterCriteria.defaultMinParamsB,
                    max: ModelFilterCriteria.defaultMaxParamsB,
                    divisions: 70,
                    labels: RangeLabels(
                      '${_paramsRange.start.toStringAsFixed(1)}B',
                      '${_paramsRange.end.toStringAsFixed(1)}B',
                    ),
                    onChanged: (values) {
                      setState(() {
                        _paramsRange = values;
                      });
                    },
                  ),
                  // Quick parameter presets
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildPresetChip('≤ 1.5B (Edge)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 1.5);
                        });
                      }),
                      _buildPresetChip('≤ 3B (Mobile)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 3.0);
                        });
                      }),
                      _buildPresetChip('≤ 8B (High Perf)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 8.0);
                        });
                      }),
                      _buildPresetChip('All Params', () {
                        setState(() {
                          _paramsRange = const RangeValues(
                            ModelFilterCriteria.defaultMinParamsB,
                            ModelFilterCriteria.defaultMaxParamsB,
                          );
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- 3. MINIMUM RAM REQUIRED FILTER ---
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Minimum RAM Required',
                    valueLabel: '${_ramRange.start.toInt()} GB – ${_ramRange.end.toInt()} GB',
                  ),
                  RangeSlider(
                    values: _ramRange,
                    min: ModelFilterCriteria.defaultMinRamGb,
                    max: ModelFilterCriteria.defaultMaxRamGb,
                    divisions: 31,
                    labels: RangeLabels(
                      '${_ramRange.start.toInt()} GB',
                      '${_ramRange.end.toInt()} GB',
                    ),
                    onChanged: (values) {
                      setState(() {
                        _ramRange = values;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- 4. PROVIDERS / PUBLISHERS FILTER ---
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Publishers & Creators',
                    valueLabel: _selectedProviders.isEmpty
                        ? 'All'
                        : '${_selectedProviders.length} selected',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allKnownProviders.map((provider) {
                      final isSelected = _selectedProviders.any(
                        (p) => p.toLowerCase() == provider.toLowerCase(),
                      );
                      return FilterChip(
                        label: Text(provider),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedProviders.add(provider);
                            } else {
                              _selectedProviders.removeWhere(
                                (p) => p.toLowerCase() == provider.toLowerCase(),
                              );
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Footer Apply Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    widget.onApply(_buildCurrentCriteria());
                    Navigator.pop(context);
                  },
                  child: Text(
                    matchingCount > 0
                        ? 'Apply Filters ($matchingCount models)'
                        : 'Apply Filters (0 matches)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required ThemeData theme,
    required String title,
    required String valueLabel,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            valueLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
