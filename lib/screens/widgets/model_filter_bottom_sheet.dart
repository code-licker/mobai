import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/utils/format_utils.dart';

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
  late double _maxSizeMb;
  late double _maxParamsB;
  late double _maxRamGb;

  late RangeValues _sizeRange;
  late RangeValues _paramsRange;
  late RangeValues _ramRange;
  late Set<String> _selectedProviders;
  late bool _phoneReadyOnly;

  @override
  void initState() {
    super.initState();
    _maxSizeMb = ModelFilterCriteria.effectiveMaxSizeMbFor(widget.allModels);
    _maxParamsB = ModelFilterCriteria.effectiveMaxParamsBFor(widget.allModels);
    _maxRamGb = ModelFilterCriteria.effectiveMaxRamGbFor(widget.allModels);

    final initSize = widget.initialCriteria.sizeRangeMb;
    _sizeRange = initSize != null
        ? RangeValues(
            initSize.start.clamp(ModelFilterCriteria.defaultMinSizeMb, _maxSizeMb),
            initSize.end.clamp(ModelFilterCriteria.defaultMinSizeMb, _maxSizeMb),
          )
        : RangeValues(ModelFilterCriteria.defaultMinSizeMb, _maxSizeMb);

    final initParams = widget.initialCriteria.paramsRangeB;
    _paramsRange = initParams != null
        ? RangeValues(
            initParams.start.clamp(ModelFilterCriteria.defaultMinParamsB, _maxParamsB),
            initParams.end.clamp(ModelFilterCriteria.defaultMinParamsB, _maxParamsB),
          )
        : RangeValues(ModelFilterCriteria.defaultMinParamsB, _maxParamsB);

    final initRam = widget.initialCriteria.ramRangeGb;
    _ramRange = initRam != null
        ? RangeValues(
            initRam.start.clamp(ModelFilterCriteria.defaultMinRamGb, _maxRamGb),
            initRam.end.clamp(ModelFilterCriteria.defaultMinRamGb, _maxRamGb),
          )
        : RangeValues(ModelFilterCriteria.defaultMinRamGb, _maxRamGb);

    _selectedProviders = Set<String>.from(widget.initialCriteria.selectedProviders);
    _phoneReadyOnly = widget.initialCriteria.phoneReadyOnly;
  }

  ModelFilterCriteria _buildCurrentCriteria() {
    final sizeAtDefault =
        _sizeRange.start <= ModelFilterCriteria.defaultMinSizeMb &&
        _sizeRange.end >= _maxSizeMb;
    final paramsAtDefault =
        _paramsRange.start <= ModelFilterCriteria.defaultMinParamsB &&
        _paramsRange.end >= _maxParamsB;
    final ramAtDefault =
        _ramRange.start <= ModelFilterCriteria.defaultMinRamGb &&
        _ramRange.end >= _maxRamGb;

    return ModelFilterCriteria(
      sizeRangeMb: sizeAtDefault ? null : _sizeRange,
      paramsRangeB: paramsAtDefault ? null : _paramsRange,
      ramRangeGb: ramAtDefault ? null : _ramRange,
      selectedProviders: _selectedProviders,
      phoneReadyOnly: _phoneReadyOnly,
    );
  }

  int _countMatchingModels() {
    final criteria = _buildCurrentCriteria();
    return widget.allModels
        .where(
          (m) => criteria.matches(
            m,
            maxSizeMb: _maxSizeMb,
            maxParamsB: _maxParamsB,
            maxRamGb: _maxRamGb,
          ),
        )
        .length;
  }

  void _resetLocalFilters() {
    setState(() {
      _sizeRange = RangeValues(
        ModelFilterCriteria.defaultMinSizeMb,
        _maxSizeMb,
      );
      _paramsRange = RangeValues(
        ModelFilterCriteria.defaultMinParamsB,
        _maxParamsB,
      );
      _ramRange = RangeValues(
        ModelFilterCriteria.defaultMinRamGb,
        _maxRamGb,
      );
      _selectedProviders.clear();
      _phoneReadyOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchingCount = _countMatchingModels();
    final criteria = _buildCurrentCriteria();
    final isActive = criteria.isActiveWithBounds(
      maxSizeMb: _maxSizeMb,
      maxParamsB: _maxParamsB,
      maxRamGb: _maxRamGb,
    );
    final activeCount = criteria.activeFilterCountWithBounds(
      maxSizeMb: _maxSizeMb,
      maxParamsB: _maxParamsB,
      maxRamGb: _maxRamGb,
    );

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

    final sizeEndLabel = _sizeRange.end >= _maxSizeMb
        ? '${formatSizeMb(_maxSizeMb)}+'
        : formatSizeMb(_sizeRange.end);
    final paramsEndLabel = _paramsRange.end >= _maxParamsB
        ? '${_maxParamsB.toStringAsFixed(0)}B+'
        : '${_paramsRange.end.toStringAsFixed(1)}B';
    final ramEndLabel = _ramRange.end >= _maxRamGb
        ? '${_maxRamGb.toInt()} GB+'
        : '${_ramRange.end.toInt()} GB';

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  if (isActive) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$activeCount active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (isActive)
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

            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Phone-ready only (<= 8B / <= 10 GB RAM)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Hides desktop-scale models that exceed mobile RAM',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _phoneReadyOnly,
                    onChanged: (val) {
                      setState(() {
                        _phoneReadyOnly = val;
                      });
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // --- 1. DOWNLOAD SIZE FILTER ---
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Download Size',
                    valueLabel: '${formatSizeMb(_sizeRange.start)} – $sizeEndLabel',
                  ),
                  RangeSlider(
                    values: _sizeRange,
                    min: ModelFilterCriteria.defaultMinSizeMb,
                    max: _maxSizeMb,
                    divisions: 100,
                    labels: RangeLabels(
                      formatSizeMb(_sizeRange.start),
                      sizeEndLabel,
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
                    valueLabel: '${_paramsRange.start.toStringAsFixed(1)}B – $paramsEndLabel',
                  ),
                  RangeSlider(
                    values: _paramsRange,
                    min: ModelFilterCriteria.defaultMinParamsB,
                    max: _maxParamsB,
                    divisions: 70,
                    labels: RangeLabels(
                      '${_paramsRange.start.toStringAsFixed(1)}B',
                      paramsEndLabel,
                    ),
                    onChanged: (values) {
                      setState(() {
                        _paramsRange = values;
                      });
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildPresetChip('<= 1.5B (Edge)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 1.5);
                        });
                      }),
                      _buildPresetChip('<= 3B (Mobile)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 3.0);
                        });
                      }),
                      _buildPresetChip('<= 8B (High Perf)', () {
                        setState(() {
                          _paramsRange = const RangeValues(0.1, 8.0);
                        });
                      }),
                      _buildPresetChip('All Params', () {
                        setState(() {
                          _paramsRange = RangeValues(
                            ModelFilterCriteria.defaultMinParamsB,
                            _maxParamsB,
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
                    valueLabel: '${_ramRange.start.toInt()} GB – $ramEndLabel',
                  ),
                  RangeSlider(
                    values: _ramRange,
                    min: ModelFilterCriteria.defaultMinRamGb,
                    max: _maxRamGb,
                    divisions: (_maxRamGb - ModelFilterCriteria.defaultMinRamGb)
                        .round()
                        .clamp(10, 100),
                    labels: RangeLabels(
                      '${_ramRange.start.toInt()} GB',
                      ramEndLabel,
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
