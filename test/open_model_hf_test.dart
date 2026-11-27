import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';

void main() {
  group('OpenModel.fromHuggingFace', () {
    test('parses GGUF model payload correctly', () {
      final hfJson = {
        'id': 'bartowski/Llama-3.2-1B-Instruct-GGUF',
        'author': 'bartowski',
        'downloads': 45200,
        'likes': 120,
        'tags': ['gguf', 'llama', 'text-generation'],
        'safetensors': {'total': 1235814400},
        'siblings': [
          {'rfilename': 'README.md'},
          {'rfilename': 'Llama-3.2-1B-Instruct-Q4_K_M.gguf', 'size': 807694464},
          {'rfilename': 'Llama-3.2-1B-Instruct-Q8_0.gguf', 'size': 1321083008},
        ],
      };

      final model = OpenModel.fromHuggingFace(hfJson);

      expect(model.id, 'bartowski/Llama-3.2-1B-Instruct-GGUF');
      expect(model.name, 'Llama 3.2 1B Instruct');
      expect(model.publisher, 'Meta');
      expect(model.parameterSizeB, '1.2');
      expect(model.format, 'GGUF');
      expect(model.quantization, 'Q4_K_M');
      expect(model.downloadSizeMb, 770); // 807694464 / (1024 * 1024)
      expect(model.minRamGb, greaterThanOrEqualTo(2));
      expect(
        model.downloadUrl,
        'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      );
      expect(model.repoUrl, 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF');
    });

    test('parses Qwen model and detects Qwen publisher', () {
      final hfJson = {
        'id': 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
        'author': 'Qwen',
        'downloads': 15000,
        'likes': 85,
        'tags': ['gguf', 'qwen', 'text-generation'],
        'siblings': [
          {'rfilename': 'qwen2.5-0.5b-instruct-q4_k_m.gguf'},
        ],
      };

      final model = OpenModel.fromHuggingFace(hfJson);

      expect(model.publisher, 'Qwen');
      expect(model.parameterSizeB, '0.5');
      expect(model.format, 'GGUF');
      expect(model.quantization, 'Q4_K_M');
      expect(
        model.downloadUrl,
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      );
    });

    test('handles fallback when no siblings or safetensors are provided', () {
      final hfJson = {
        'id': 'custom-author/Gemma-2-2B-GGUF',
        'author': 'custom-author',
        'likes': 10,
        'tags': ['google', 'gemma'],
      };

      final model = OpenModel.fromHuggingFace(hfJson);

      expect(model.publisher, 'Google');
      expect(model.parameterSizeB, '2');
      expect(model.downloadSizeMb, greaterThan(0));
      expect(model.downloadUrl, isEmpty);
      expect(model.variants, isEmpty);
      expect(model.repoUrl, 'https://huggingface.co/custom-author/Gemma-2-2B-GGUF');
    });

    test('parses multiple GGUF variants and prioritizes Q4_K_M over Q8_0', () {
      final hfJson = {
        'id': 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
        'author': 'bartowski',
        'siblings': [
          {'rfilename': 'mmproj-model-f16.gguf', 'size': 100000000},
          {'rfilename': 'Qwen2.5-1.5B-Instruct-Q8_0.gguf', 'size': 1600000000},
          {'rfilename': 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf', 'size': 980000000},
        ],
      };

      final model = OpenModel.fromHuggingFace(hfJson);
      expect(model.variants.length, 2);
      expect(model.variants.first.quantization, 'Q4_K_M');
      expect(model.variants.last.quantization, 'Q8_0');
      expect(model.quantization, 'Q4_K_M');
    });

    test('excludes mtp- and draft- auxiliary files when main weights exist', () {
      expect(
        OpenModel.isAuxiliaryGgufFile('mtp-gemma-4-E2B-it-Artemis-Q4_0.gguf'),
        isTrue,
      );
      expect(OpenModel.isAuxiliaryGgufFile('mmproj-model-f16.gguf'), isTrue);
      expect(
        OpenModel.isAuxiliaryGgufFile('gemma-4-E2B-it-Artemis-Q4_0.gguf'),
        isFalse,
      );
      expect(OpenModel.isAuxiliaryGgufFile('prompt-helper.gguf'), isFalse);

      final hfJson = {
        'id': 'owner/gemma-4-E2B-it-Artemis-GGUF',
        'author': 'owner',
        'createdAt': '2026-11-20T10:00:00.000Z',
        'siblings': [
          {'rfilename': 'mtp-gemma-4-E2B-it-Artemis-Q4_0.gguf', 'size': 73 * 1024 * 1024},
          {'rfilename': 'gemma-4-E2B-it-Artemis-Q4_0.gguf', 'size': 2100 * 1024 * 1024},
        ],
      };

      final model = OpenModel.fromHuggingFace(hfJson);
      expect(model.variants.length, 1);
      expect(model.variants.first.fileName, 'gemma-4-E2B-it-Artemis-Q4_0.gguf');
      expect(model.downloadSizeMb, 2100);
      expect(model.createdAt, DateTime.utc(2026, 11, 20, 10));
    });

    test('parses Hugging Face gated field into isGated', () {
      final gatedBool = OpenModel.fromHuggingFace({
        'id': 'google/gemma-2b-gguf',
        'author': 'google',
        'gated': true,
        'siblings': [
          {'rfilename': 'gemma-2b.gguf', 'size': 1200 * 1024 * 1024},
        ],
      });
      final gatedManual = OpenModel.fromHuggingFace({
        'id': 'meta-llama/Llama-3-8B-GGUF',
        'author': 'meta-llama',
        'gated': 'manual',
        'siblings': [
          {'rfilename': 'llama-3-8b.gguf', 'size': 4500 * 1024 * 1024},
        ],
      });
      final ungatedFalse = OpenModel.fromHuggingFace({
        'id': 'owner/open-model-gguf',
        'author': 'owner',
        'gated': false,
        'siblings': [
          {'rfilename': 'open-model.gguf', 'size': 900 * 1024 * 1024},
        ],
      });
      final ungatedOmitted = OpenModel.fromHuggingFace({
        'id': 'owner/default-model-gguf',
        'author': 'owner',
        'siblings': [
          {'rfilename': 'default-model.gguf', 'size': 900 * 1024 * 1024},
        ],
      });

      expect(gatedBool.isGated, isTrue);
      expect(gatedManual.isGated, isTrue);
      expect(ungatedFalse.isGated, isFalse);
      expect(ungatedOmitted.isGated, isFalse);
    });

    test('uses gguf metadata for huge models without parameter size in repo id', () {
      final deepseek = OpenModel.fromHuggingFace({
        'id': 'ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF',
        'author': 'ISTA-DASLab',
        'gguf': {
          'total': 196613849600,
          'totalFileSize': 110595290816,
        },
        'siblings': [
          {'rfilename': 'DeepSeek-V4.1-Flash-Engram-IQ4_NL.gguf'},
        ],
      });

      expect(deepseek.parameterSizeB, '196.6');
      expect(deepseek.hasExactSizes, isFalse);
      expect(deepseek.downloadSizeMb, greaterThan(100000));
      expect(deepseek.isTooLargeForPhone(deviceRamGb: 8.0), isTrue);

      final fallbackTotalSizeOnly = OpenModel.fromHuggingFace({
        'id': 'owner/Mystery-Model-GGUF',
        'author': 'owner',
        'gguf': {
          'totalFileSize': 110595290816,
        },
        'siblings': [
          {'rfilename': 'Mystery-IQ4_NL.gguf'},
        ],
      });

      expect(fallbackTotalSizeOnly.downloadSizeMb, 105472);
      expect(fallbackTotalSizeOnly.isTooLargeForPhone(deviceRamGb: 8.0), isTrue);
    });
  });
}
