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
      expect(model.repoUrl, 'https://huggingface.co/custom-author/Gemma-2-2B-GGUF');
    });
  });
}
