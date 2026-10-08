import 'package:flutter/material.dart';
import 'package:mobai/models/open_model.dart';

class ModelFilterCriteria {
  // Constant standard bounds
  static const double defaultMinSizeMb = 100.0;
  static const double defaultMaxSizeMb = 10000.0;

  static const double defaultMinParamsB = 0.1;
  static const double defaultMaxParamsB = 70.0;

  static const double defaultMinRamGb = 1.0;
  static const double defaultMaxRamGb = 32.0;

  final RangeValues? sizeRangeMb;
  final RangeValues? paramsRangeB;
  final RangeValues? ramRangeGb;
  final Set<String> selectedProviders;

  const ModelFilterCriteria({
    this.sizeRangeMb,
    this.paramsRangeB,
    this.ramRangeGb,
    this.selectedProviders = const {},
  });

  bool get isSizeFilterActive =>
      sizeRangeMb != null &&
      (sizeRangeMb!.start > defaultMinSizeMb || sizeRangeMb!.end < defaultMaxSizeMb);

  bool get isParamsFilterActive =>
      paramsRangeB != null &&
      (paramsRangeB!.start > defaultMinParamsB || paramsRangeB!.end < defaultMaxParamsB);

  bool get isRamFilterActive =>
      ramRangeGb != null &&
      (ramRangeGb!.start > defaultMinRamGb || ramRangeGb!.end < defaultMaxRamGb);

  bool get isProviderFilterActive => selectedProviders.isNotEmpty;

  bool get isActive =>
      isSizeFilterActive ||
      isParamsFilterActive ||
      isRamFilterActive ||
      isProviderFilterActive;

  int get activeFilterCount {
    int count = 0;
    if (isSizeFilterActive) count++;
    if (isParamsFilterActive) count++;
    if (isRamFilterActive) count++;
    if (isProviderFilterActive) count += selectedProviders.length;
    return count;
  }

  bool matches(OpenModel model) {
    if (isSizeFilterActive) {
      final size = model.downloadSizeMb.toDouble();
      if (size < sizeRangeMb!.start || size > sizeRangeMb!.end) {
        return false;
      }
    }

    if (isParamsFilterActive) {
      final p = model.paramSizeNum;
      if (p < paramsRangeB!.start || p > paramsRangeB!.end) {
        return false;
      }
    }

    if (isRamFilterActive) {
      final ram = model.minRamGb.toDouble();
      if (ram < ramRangeGb!.start || ram > ramRangeGb!.end) {
        return false;
      }
    }

    if (isProviderFilterActive) {
      final matchesProvider = selectedProviders.any(
        (p) => p.toLowerCase() == model.publisher.toLowerCase(),
      );
      if (!matchesProvider) {
        return false;
      }
    }

    return true;
  }

  ModelFilterCriteria copyWith({
    RangeValues? sizeRangeMb,
    RangeValues? paramsRangeB,
    RangeValues? ramRangeGb,
    Set<String>? selectedProviders,
    bool clearSize = false,
    bool clearParams = false,
    bool clearRam = false,
  }) {
    return ModelFilterCriteria(
      sizeRangeMb: clearSize ? null : (sizeRangeMb ?? this.sizeRangeMb),
      paramsRangeB: clearParams ? null : (paramsRangeB ?? this.paramsRangeB),
      ramRangeGb: clearRam ? null : (ramRangeGb ?? this.ramRangeGb),
      selectedProviders: selectedProviders ?? this.selectedProviders,
    );
  }

  static ModelFilterCriteria initial() {
    return const ModelFilterCriteria();
  }
}
