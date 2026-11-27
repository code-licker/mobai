import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/open_model.dart';

class ModelFilterCriteria {
  // Constant standard bounds (large enough for 35B+ GGUFs by default)
  static const double defaultMinSizeMb = 100.0;
  static const double defaultMaxSizeMb = 30720.0; // 30.0 GB

  static const double defaultMinParamsB = 0.1;
  static const double defaultMaxParamsB = 70.0;

  static const double defaultMinRamGb = 1.0;
  static const double defaultMaxRamGb = 64.0;

  final RangeValues? sizeRangeMb;
  final RangeValues? paramsRangeB;
  final RangeValues? ramRangeGb;
  final Set<String> selectedProviders;
  final bool hideNotRecommended;
  final bool downloadedOnly;

  const ModelFilterCriteria({
    this.sizeRangeMb,
    this.paramsRangeB,
    this.ramRangeGb,
    this.selectedProviders = const {},
    this.hideNotRecommended = false,
    this.downloadedOnly = false,
  });

  static double effectiveMaxSizeMbFor(Iterable<OpenModel> models) {
    double maxFound = defaultMaxSizeMb;
    for (final m in models) {
      if (m.downloadSizeMb > maxFound) {
        maxFound = m.downloadSizeMb.toDouble();
      }
    }
    // Round up cleanly to nearest GB (1024 MB)
    return (maxFound / 1024).ceil() * 1024.0;
  }

  static double effectiveMaxParamsBFor(Iterable<OpenModel> models) {
    double maxFound = defaultMaxParamsB;
    for (final m in models) {
      if (m.paramSizeNum > maxFound) {
        maxFound = m.paramSizeNum;
      }
    }
    return math.max(defaultMaxParamsB, maxFound.ceilToDouble());
  }

  static double effectiveMaxRamGbFor(Iterable<OpenModel> models) {
    double maxFound = defaultMaxRamGb;
    for (final m in models) {
      if (m.minRamGb > maxFound) {
        maxFound = m.minRamGb.toDouble();
      }
    }
    return math.max(defaultMaxRamGb, maxFound.ceilToDouble());
  }

  bool isSizeFilterActiveWithMax([double maxSizeMb = defaultMaxSizeMb]) =>
      sizeRangeMb != null &&
      (sizeRangeMb!.start > defaultMinSizeMb || sizeRangeMb!.end < maxSizeMb);

  bool isParamsFilterActiveWithMax([double maxParamsB = defaultMaxParamsB]) =>
      paramsRangeB != null &&
      (paramsRangeB!.start > defaultMinParamsB ||
          paramsRangeB!.end < maxParamsB);

  bool isRamFilterActiveWithMax([double maxRamGb = defaultMaxRamGb]) =>
      ramRangeGb != null &&
      (ramRangeGb!.start > defaultMinRamGb || ramRangeGb!.end < maxRamGb);

  bool get isSizeFilterActive => isSizeFilterActiveWithMax(defaultMaxSizeMb);
  bool get isParamsFilterActive => isParamsFilterActiveWithMax(defaultMaxParamsB);
  bool get isRamFilterActive => isRamFilterActiveWithMax(defaultMaxRamGb);
  bool get isProviderFilterActive => selectedProviders.isNotEmpty;

  bool isActiveWithBounds({
    double maxSizeMb = defaultMaxSizeMb,
    double maxParamsB = defaultMaxParamsB,
    double maxRamGb = defaultMaxRamGb,
  }) =>
      isSizeFilterActiveWithMax(maxSizeMb) ||
      isParamsFilterActiveWithMax(maxParamsB) ||
      isRamFilterActiveWithMax(maxRamGb) ||
      isProviderFilterActive ||
      hideNotRecommended ||
      downloadedOnly;

  bool get isActive => isActiveWithBounds();

  int activeFilterCountWithBounds({
    double maxSizeMb = defaultMaxSizeMb,
    double maxParamsB = defaultMaxParamsB,
    double maxRamGb = defaultMaxRamGb,
  }) {
    int count = 0;
    if (isSizeFilterActiveWithMax(maxSizeMb)) count++;
    if (isParamsFilterActiveWithMax(maxParamsB)) count++;
    if (isRamFilterActiveWithMax(maxRamGb)) count++;
    if (isProviderFilterActive) count += selectedProviders.length;
    if (hideNotRecommended) count++;
    if (downloadedOnly) count++;
    return count;
  }

  int get activeFilterCount => activeFilterCountWithBounds();

  bool matches(
    OpenModel model, {
    double maxSizeMb = defaultMaxSizeMb,
    double maxParamsB = defaultMaxParamsB,
    double maxRamGb = defaultMaxRamGb,
    double deviceRamGb = 8.0,
  }) {
    if (hideNotRecommended &&
        model.isTooLargeForPhone(deviceRamGb: deviceRamGb)) {
      return false;
    }

    if (sizeRangeMb != null) {
      final size = model.downloadSizeMb.toDouble();
      if (size < sizeRangeMb!.start) return false;
      if (sizeRangeMb!.end < maxSizeMb && size > sizeRangeMb!.end) {
        return false;
      }
    }

    if (paramsRangeB != null) {
      final p = model.paramSizeNum;
      if (p < paramsRangeB!.start) return false;
      if (paramsRangeB!.end < maxParamsB && p > paramsRangeB!.end) {
        return false;
      }
    }

    if (ramRangeGb != null) {
      final ram = model.minRamGb.toDouble();
      if (ram < ramRangeGb!.start) return false;
      if (ramRangeGb!.end < maxRamGb && ram > ramRangeGb!.end) {
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
    bool? hideNotRecommended,
    bool? downloadedOnly,
    bool clearSize = false,
    bool clearParams = false,
    bool clearRam = false,
  }) {
    return ModelFilterCriteria(
      sizeRangeMb: clearSize ? null : (sizeRangeMb ?? this.sizeRangeMb),
      paramsRangeB: clearParams ? null : (paramsRangeB ?? this.paramsRangeB),
      ramRangeGb: clearRam ? null : (ramRangeGb ?? this.ramRangeGb),
      selectedProviders: selectedProviders ?? this.selectedProviders,
      hideNotRecommended: hideNotRecommended ?? this.hideNotRecommended,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
    );
  }

  static ModelFilterCriteria initial() {
    return const ModelFilterCriteria();
  }
}
