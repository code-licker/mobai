import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/utils/format_utils.dart';

class ModelFilterBottomSheet extends StatefulWidget {
  final ModelFilterCriteria initialCriteria;
  final List<OpenModel> allModels;
  final List<String> availableProviders;
  final double deviceRamGb;
  final ValueChanged<ModelFilterCriteria> onApply;
  final VoidCallback onReset;

  const ModelFilterBottomSheet({
    super.key,
    required this.initialCriteria,
    required this.allModels,
    required this.availableProviders,
    this.deviceRamGb = 8.0,
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
  late bool _hideNotRecommended;
  late bool _downloadedOnly;

  final TextEditingController _sizeMinController = TextEditingController();
  final TextEditingController _sizeMaxController = TextEditingController();
  final TextEditingController _paramsMinController = TextEditingController();
  final TextEditingController _paramsMaxController = TextEditingController();
  final TextEditingController _ramMinController = TextEditingController();
  final TextEditingController _ramMaxController = TextEditingController();
  final TextEditingController _providerSearchController =
      TextEditingController();

  final FocusNode _sizeMinFocus = FocusNode();
  final FocusNode _sizeMaxFocus = FocusNode();
  final FocusNode _paramsMinFocus = FocusNode();
  final FocusNode _paramsMaxFocus = FocusNode();
  final FocusNode _ramMinFocus = FocusNode();
  final FocusNode _ramMaxFocus = FocusNode();

  String _providerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _maxSizeMb = ModelFilterCriteria.effectiveMaxSizeMbFor(widget.allModels);
    _maxParamsB = ModelFilterCriteria.effectiveMaxParamsBFor(widget.allModels);
    _maxRamGb = ModelFilterCriteria.effectiveMaxRamGbFor(widget.allModels);

    final initSize = widget.initialCriteria.sizeRangeMb;
    _sizeRange = initSize != null
        ? RangeValues(
            initSize.start.clamp(
              ModelFilterCriteria.defaultMinSizeMb,
              _maxSizeMb,
            ),
            initSize.end.clamp(
              ModelFilterCriteria.defaultMinSizeMb,
              _maxSizeMb,
            ),
          )
        : RangeValues(ModelFilterCriteria.defaultMinSizeMb, _maxSizeMb);

    final initParams = widget.initialCriteria.paramsRangeB;
    _paramsRange = initParams != null
        ? RangeValues(
            initParams.start.clamp(
              ModelFilterCriteria.defaultMinParamsB,
              _maxParamsB,
            ),
            initParams.end.clamp(
              ModelFilterCriteria.defaultMinParamsB,
              _maxParamsB,
            ),
          )
        : RangeValues(ModelFilterCriteria.defaultMinParamsB, _maxParamsB);

    final initRam = widget.initialCriteria.ramRangeGb;
    _ramRange = initRam != null
        ? RangeValues(
            initRam.start.clamp(ModelFilterCriteria.defaultMinRamGb, _maxRamGb),
            initRam.end.clamp(ModelFilterCriteria.defaultMinRamGb, _maxRamGb),
          )
        : RangeValues(ModelFilterCriteria.defaultMinRamGb, _maxRamGb);

    _selectedProviders = Set<String>.from(
      widget.initialCriteria.selectedProviders,
    );
    _hideNotRecommended = widget.initialCriteria.hideNotRecommended;
    _downloadedOnly = widget.initialCriteria.downloadedOnly;

    _syncAllRangeTexts();
    _bindFocusCommit(_sizeMinFocus, () => _commitSizeText(isMin: true));
    _bindFocusCommit(_sizeMaxFocus, () => _commitSizeText(isMin: false));
    _bindFocusCommit(_paramsMinFocus, () => _commitParamsText(isMin: true));
    _bindFocusCommit(_paramsMaxFocus, () => _commitParamsText(isMin: false));
    _bindFocusCommit(_ramMinFocus, () => _commitRamText(isMin: true));
    _bindFocusCommit(_ramMaxFocus, () => _commitRamText(isMin: false));
  }

  void _bindFocusCommit(FocusNode node, VoidCallback commitFn) {
    node.addListener(() {
      if (!node.hasFocus && mounted) {
        commitFn();
      }
    });
  }

  @override
  void dispose() {
    _sizeMinController.dispose();
    _sizeMaxController.dispose();
    _paramsMinController.dispose();
    _paramsMaxController.dispose();
    _ramMinController.dispose();
    _ramMaxController.dispose();
    _providerSearchController.dispose();
    _sizeMinFocus.dispose();
    _sizeMaxFocus.dispose();
    _paramsMinFocus.dispose();
    _paramsMaxFocus.dispose();
    _ramMinFocus.dispose();
    _ramMaxFocus.dispose();
    super.dispose();
  }

  void _syncSizeTexts() {
    _sizeMinController.text = (_sizeRange.start / 1024.0).toStringAsFixed(1);
    _sizeMaxController.text = (_sizeRange.end / 1024.0).toStringAsFixed(1);
  }

  void _syncParamsTexts() {
    _paramsMinController.text = _paramsRange.start.toStringAsFixed(1);
    _paramsMaxController.text = _paramsRange.end.toStringAsFixed(1);
  }

  void _syncRamTexts() {
    _ramMinController.text = _ramRange.start.round().toString();
    _ramMaxController.text = _ramRange.end.round().toString();
  }

  void _syncAllRangeTexts() {
    _syncSizeTexts();
    _syncParamsTexts();
    _syncRamTexts();
  }

  void _onSizeTextChanged(String raw, {required bool isMin}) {
    final parsedGb = double.tryParse(raw.trim());
    if (parsedGb == null) return;
    final valMb = (parsedGb * 1024.0).clamp(
      ModelFilterCriteria.defaultMinSizeMb,
      _maxSizeMb,
    );
    setState(() {
      if (isMin && valMb <= _sizeRange.end) {
        _sizeRange = RangeValues(valMb, _sizeRange.end);
      } else if (!isMin && valMb >= _sizeRange.start) {
        _sizeRange = RangeValues(_sizeRange.start, valMb);
      }
    });
  }

  void _commitSizeText({required bool isMin}) {
    final raw = isMin ? _sizeMinController.text : _sizeMaxController.text;
    final parsedGb = double.tryParse(raw.trim());
    setState(() {
      if (parsedGb != null) {
        final clamped = (parsedGb * 1024.0).clamp(
          ModelFilterCriteria.defaultMinSizeMb,
          _maxSizeMb,
        );
        if (isMin) {
          _sizeRange = RangeValues(
            clamped <= _sizeRange.end ? clamped : _sizeRange.end,
            _sizeRange.end,
          );
        } else {
          _sizeRange = RangeValues(
            _sizeRange.start,
            clamped >= _sizeRange.start ? clamped : _sizeRange.start,
          );
        }
      }
      _syncSizeTexts();
    });
  }

  void _onParamsTextChanged(String raw, {required bool isMin}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return;
    final val = parsed.clamp(ModelFilterCriteria.defaultMinParamsB, _maxParamsB);
    setState(() {
      if (isMin && val <= _paramsRange.end) {
        _paramsRange = RangeValues(val, _paramsRange.end);
      } else if (!isMin && val >= _paramsRange.start) {
        _paramsRange = RangeValues(_paramsRange.start, val);
      }
    });
  }

  void _commitParamsText({required bool isMin}) {
    final raw = isMin ? _paramsMinController.text : _paramsMaxController.text;
    final parsed = double.tryParse(raw.trim());
    setState(() {
      if (parsed != null) {
        final clamped = parsed.clamp(
          ModelFilterCriteria.defaultMinParamsB,
          _maxParamsB,
        );
        if (isMin) {
          _paramsRange = RangeValues(
            clamped <= _paramsRange.end ? clamped : _paramsRange.end,
            _paramsRange.end,
          );
        } else {
          _paramsRange = RangeValues(
            _paramsRange.start,
            clamped >= _paramsRange.start ? clamped : _paramsRange.start,
          );
        }
      }
      _syncParamsTexts();
    });
  }

  void _onRamTextChanged(String raw, {required bool isMin}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return;
    final val = parsed.clamp(ModelFilterCriteria.defaultMinRamGb, _maxRamGb);
    setState(() {
      if (isMin && val <= _ramRange.end) {
        _ramRange = RangeValues(val, _ramRange.end);
      } else if (!isMin && val >= _ramRange.start) {
        _ramRange = RangeValues(_ramRange.start, val);
      }
    });
  }

  void _commitRamText({required bool isMin}) {
    final raw = isMin ? _ramMinController.text : _ramMaxController.text;
    final parsed = double.tryParse(raw.trim());
    setState(() {
      if (parsed != null) {
        final clamped = parsed.roundToDouble().clamp(
          ModelFilterCriteria.defaultMinRamGb,
          _maxRamGb,
        );
        if (isMin) {
          _ramRange = RangeValues(
            clamped <= _ramRange.end ? clamped : _ramRange.end,
            _ramRange.end,
          );
        } else {
          _ramRange = RangeValues(
            _ramRange.start,
            clamped >= _ramRange.start ? clamped : _ramRange.start,
          );
        }
      }
      _syncRamTexts();
    });
  }

  void _commitAllRangeTexts() {
    _commitSizeText(isMin: true);
    _commitSizeText(isMin: false);
    _commitParamsText(isMin: true);
    _commitParamsText(isMin: false);
    _commitRamText(isMin: true);
    _commitRamText(isMin: false);
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
      hideNotRecommended: _hideNotRecommended,
      downloadedOnly: _downloadedOnly,
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
            deviceRamGb: widget.deviceRamGb,
          ),
        )
        .length;
  }

  void _resetLocalFilters() {
    FocusScope.of(context).unfocus();
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
      _hideNotRecommended = false;
      _downloadedOnly = false;
      _providerSearchController.clear();
      _providerSearchQuery = '';
      _syncAllRangeTexts();
    });
  }

  Map<String, int> _buildProviderCounts() {
    final counts = <String, int>{
      for (final p in const [
        'Qwen',
        'Meta',
        'Google',
        'Mistral',
        'Microsoft',
        'DeepSeek',
        'Bartowski',
      ])
        p: 0,
      for (final p in widget.availableProviders) p: 0,
    };

    for (final model in widget.allModels) {
      if (model.publisher.isEmpty) continue;
      final existingKey = counts.keys.cast<String?>().firstWhere(
        (k) => k?.toLowerCase() == model.publisher.toLowerCase(),
        orElse: () => null,
      );
      final key = existingKey ?? model.publisher;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
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

    final providerCounts = _buildProviderCounts();
    final sortedProviders = providerCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final creatorQuery = _providerSearchQuery.trim().toLowerCase();
    final visibleProviders = creatorQuery.isEmpty
        ? sortedProviders
        : sortedProviders
              .where((p) => p.toLowerCase().contains(creatorQuery))
              .toList();

    final sizeEndLabel = _sizeRange.end >= _maxSizeMb
        ? '${formatSizeMb(_maxSizeMb)}+'
        : formatSizeMb(_sizeRange.end);
    final paramsEndLabel = _paramsRange.end >= _maxParamsB
        ? '${_maxParamsB.toStringAsFixed(0)}B+'
        : '${_paramsRange.end.toStringAsFixed(1)}B';
    final ramEndLabel = _ramRange.end >= _maxRamGb
        ? '${_maxRamGb.toInt()} GB+'
        : '${_ramRange.end.toInt()} GB';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Hide "Not Recommended" models',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Hides models needing > ${widget.deviceRamGb.toStringAsFixed(0)} GB (or > 12 GB) safe RAM',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: _hideNotRecommended,
                        onChanged: (val) {
                          setState(() {
                            _hideNotRecommended = val;
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Downloaded only (My Models)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Syncs with the My Models tab to show only local/custom models',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _downloadedOnly,
                        onChanged: (val) {
                          setState(() {
                            _downloadedOnly = val;
                          });
                        },
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      // --- 1. DOWNLOAD SIZE FILTER ---
                      _buildSectionHeader(
                        theme: theme,
                        title: 'Download Size',
                        valueLabel:
                            '${formatSizeMb(_sizeRange.start)} – $sizeEndLabel',
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
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _sizeRange = values;
                            _syncSizeTexts();
                          });
                        },
                      ),
                      _buildMinMaxInputsRow(
                        minController: _sizeMinController,
                        maxController: _sizeMaxController,
                        minFocus: _sizeMinFocus,
                        maxFocus: _sizeMaxFocus,
                        unitSuffix: 'GB',
                        allowDecimal: true,
                        onMinChanged: (v) => _onSizeTextChanged(v, isMin: true),
                        onMaxChanged: (v) =>
                            _onSizeTextChanged(v, isMin: false),
                        onMinSubmitted: () => _commitSizeText(isMin: true),
                        onMaxSubmitted: () => _commitSizeText(isMin: false),
                      ),
                      const SizedBox(height: 18),

                      // --- 2. PARAMETER COUNT FILTER ---
                      _buildSectionHeader(
                        theme: theme,
                        title: 'Parameters',
                        valueLabel:
                            '${_paramsRange.start.toStringAsFixed(1)}B – $paramsEndLabel',
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
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _paramsRange = values;
                            _syncParamsTexts();
                          });
                        },
                      ),
                      _buildMinMaxInputsRow(
                        minController: _paramsMinController,
                        maxController: _paramsMaxController,
                        minFocus: _paramsMinFocus,
                        maxFocus: _paramsMaxFocus,
                        unitSuffix: 'B',
                        allowDecimal: true,
                        onMinChanged: (v) =>
                            _onParamsTextChanged(v, isMin: true),
                        onMaxChanged: (v) =>
                            _onParamsTextChanged(v, isMin: false),
                        onMinSubmitted: () => _commitParamsText(isMin: true),
                        onMaxSubmitted: () => _commitParamsText(isMin: false),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildPresetChip('<= 1.5B (Edge)', () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _paramsRange = RangeValues(
                                0.1,
                                1.5.clamp(0.1, _maxParamsB),
                              );
                              _syncParamsTexts();
                            });
                          }),
                          _buildPresetChip('<= 3B (Mobile)', () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _paramsRange = RangeValues(
                                0.1,
                                3.0.clamp(0.1, _maxParamsB),
                              );
                              _syncParamsTexts();
                            });
                          }),
                          _buildPresetChip('<= 8B (High Perf)', () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _paramsRange = RangeValues(
                                0.1,
                                8.0.clamp(0.1, _maxParamsB),
                              );
                              _syncParamsTexts();
                            });
                          }),
                          _buildPresetChip('All Params', () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _paramsRange = RangeValues(
                                ModelFilterCriteria.defaultMinParamsB,
                                _maxParamsB,
                              );
                              _syncParamsTexts();
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
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _ramRange = values;
                            _syncRamTexts();
                          });
                        },
                      ),
                      _buildMinMaxInputsRow(
                        minController: _ramMinController,
                        maxController: _ramMaxController,
                        minFocus: _ramMinFocus,
                        maxFocus: _ramMaxFocus,
                        unitSuffix: 'GB',
                        allowDecimal: false,
                        onMinChanged: (v) => _onRamTextChanged(v, isMin: true),
                        onMaxChanged: (v) => _onRamTextChanged(v, isMin: false),
                        onMinSubmitted: () => _commitRamText(isMin: true),
                        onMaxSubmitted: () => _commitRamText(isMin: false),
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
                      TextField(
                        controller: _providerSearchController,
                        onChanged: (val) {
                          setState(() {
                            _providerSearchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search creators...',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _providerSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _providerSearchController.clear();
                                      _providerSearchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      if (_selectedProviders.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Selected: ${_selectedProviders.join(", ")}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedProviders.clear();
                                  });
                                },
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        height: 210,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: visibleProviders.isEmpty
                            ? Center(
                                child: Text(
                                  'No creators match "$_providerSearchQuery"',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: visibleProviders.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final provider = visibleProviders[idx];
                                  final count = providerCounts[provider] ?? 0;
                                  final isSelected = _selectedProviders.any(
                                    (p) =>
                                        p.toLowerCase() ==
                                        provider.toLowerCase(),
                                  );
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: isSelected,
                                    title: Text(
                                      provider,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    secondary: count > 0
                                        ? Text(
                                            '$count',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.outline,
                                                ),
                                          )
                                        : null,
                                    onChanged: (selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedProviders.add(provider);
                                        } else {
                                          _selectedProviders.removeWhere(
                                            (p) =>
                                                p.toLowerCase() ==
                                                provider.toLowerCase(),
                                          );
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
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
                        _commitAllRangeTexts();
                        widget.onApply(_buildCurrentCriteria());
                        Navigator.pop(context);
                      },
                      child: Text(
                        _downloadedOnly
                            ? 'Apply Filters (My Models)'
                            : (matchingCount > 0
                                ? 'Apply Filters ($matchingCount models)'
                                : 'Apply Filters (0 matches)'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinMaxInputsRow({
    required TextEditingController minController,
    required TextEditingController maxController,
    required FocusNode minFocus,
    required FocusNode maxFocus,
    required String unitSuffix,
    required bool allowDecimal,
    required ValueChanged<String> onMinChanged,
    required ValueChanged<String> onMaxChanged,
    required VoidCallback onMinSubmitted,
    required VoidCallback onMaxSubmitted,
  }) {
    final formatter = FilteringTextInputFormatter.allow(
      RegExp(allowDecimal ? r'[0-9.]' : r'[0-9]'),
    );
    final keyboardType = TextInputType.numberWithOptions(decimal: allowDecimal);

    Widget buildField({
      required String label,
      required TextEditingController controller,
      required FocusNode focusNode,
      required ValueChanged<String> onChanged,
      required VoidCallback onSubmitted,
    }) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        inputFormatters: [formatter],
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unitSuffix,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: buildField(
              label: 'Min',
              controller: minController,
              focusNode: minFocus,
              onChanged: onMinChanged,
              onSubmitted: onMinSubmitted,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('–', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: buildField(
              label: 'Max',
              controller: maxController,
              focusNode: maxFocus,
              onChanged: onMaxChanged,
              onSubmitted: onMaxSubmitted,
            ),
          ),
        ],
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
