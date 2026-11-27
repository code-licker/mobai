import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';

void main() {
  group('ModelFilterCriteria', () {
    final llama = OpenModel(
      id: 'llama-3.2-1b',
      name: 'Llama 3.2 1B',
      publisher: 'Meta',
      parameterSizeB: '1.2',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 800,
      minRamGb: 4,
      downloadUrl: 'https://huggingface.co/...',
      description: 'Llama model',
      repoUrl: 'https://huggingface.co/...',
    );

    final qwen = OpenModel(
      id: 'qwen-2.5-0.5b',
      name: 'Qwen 2.5 0.5B',
      publisher: 'Qwen',
      parameterSizeB: '0.5',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 390,
      minRamGb: 3,
      downloadUrl: 'https://huggingface.co/...',
      description: 'Qwen model',
      repoUrl: 'https://huggingface.co/...',
    );

    final gemmaLarge = OpenModel(
      id: 'gemma-2-9b',
      name: 'Gemma 2 9B',
      publisher: 'Google',
      parameterSizeB: '9.0',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 5500,
      minRamGb: 12,
      downloadUrl: 'https://huggingface.co/...',
      description: 'Gemma 9B',
      repoUrl: 'https://huggingface.co/...',
    );

    test('initial criteria matches all models and is inactive', () {
      final criteria = ModelFilterCriteria.initial();
      expect(criteria.isActive, false);
      expect(criteria.activeFilterCount, 0);
      expect(criteria.matches(llama), true);
      expect(criteria.matches(qwen), true);
      expect(criteria.matches(gemmaLarge), true);
    });

    test('filters models by size range', () {
      final criteria = ModelFilterCriteria(
        sizeRangeMb: const RangeValues(100, 1000),
      );
      expect(criteria.isSizeFilterActive, true);
      expect(criteria.matches(llama), true); // 800 MB
      expect(criteria.matches(qwen), true); // 390 MB
      expect(criteria.matches(gemmaLarge), false); // 5500 MB
    });

    test('filters models by parameter count range', () {
      final criteria = ModelFilterCriteria(
        paramsRangeB: const RangeValues(0.1, 2.0),
      );
      expect(criteria.isParamsFilterActive, true);
      expect(criteria.matches(llama), true); // 1.2 B
      expect(criteria.matches(qwen), true); // 0.5 B
      expect(criteria.matches(gemmaLarge), false); // 9.0 B
    });

    test('filters models by minimum RAM range', () {
      final criteria = ModelFilterCriteria(ramRangeGb: const RangeValues(1, 4));
      expect(criteria.isRamFilterActive, true);
      expect(criteria.matches(llama), true); // 4 GB
      expect(criteria.matches(qwen), true); // 3 GB
      expect(criteria.matches(gemmaLarge), false); // 12 GB
    });

    test('filters models by provider', () {
      final criteria = ModelFilterCriteria(selectedProviders: {'Meta', 'Qwen'});
      expect(criteria.isProviderFilterActive, true);
      expect(criteria.matches(llama), true);
      expect(criteria.matches(qwen), true);
      expect(criteria.matches(gemmaLarge), false);
    });

    test('combines multiple active filters', () {
      final criteria = ModelFilterCriteria(
        paramsRangeB: const RangeValues(0.1, 1.0),
        selectedProviders: {'Qwen'},
      );
      expect(criteria.matches(qwen), true);
      expect(criteria.matches(llama), false);
      expect(criteria.matches(gemmaLarge), false);
    });

    test(
      'supports hideNotRecommended, downloadedOnly, and dynamic bounds for large 19.4GB models',
      () {
        final large35B = OpenModel(
          id: 'ornith/35b-a3b',
          name: 'Ornith 1.5 35B A3B',
          publisher: 'ornith-ai',
          parameterSizeB: '35',
          format: 'GGUF',
          quantization: 'Q4_K_M',
          downloadSizeMb: 19400,
          minRamGb: 30,
          downloadUrl: 'https://huggingface.co/...',
          description: '35B model',
          repoUrl: 'https://huggingface.co/...',
        );

        final maxSize = ModelFilterCriteria.effectiveMaxSizeMbFor([
          llama,
          large35B,
        ]);
        expect(maxSize, greaterThanOrEqualTo(30720.0));

        final initial = ModelFilterCriteria.initial();
        expect(initial.matches(large35B, maxSizeMb: maxSize), true);

        final hideHeavy = initial.copyWith(hideNotRecommended: true);
        expect(hideHeavy.isActive, isTrue);
        expect(hideHeavy.matches(llama, deviceRamGb: 8.0), true);
        expect(
          hideHeavy.matches(gemmaLarge, deviceRamGb: 8.0),
          false,
        ); // 12 > 8
        expect(
          hideHeavy.matches(gemmaLarge, deviceRamGb: 16.0),
          true,
        ); // 12 <= 12 & <= 16
        expect(
          hideHeavy.matches(large35B, deviceRamGb: 16.0),
          false,
        ); // 30 > 12

        final downloadedFilter = initial.copyWith(downloadedOnly: true);
        expect(downloadedFilter.isActive, isTrue);
        expect(downloadedFilter.activeFilterCount, 1);
      },
    );
  });
}
