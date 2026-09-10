var a = {
  "id": "qwen2.5-0.5b-instruct-q4",
  "name": "Qwen 2.5 0.5B Instruct",
  "publisher": "Qwen",
  "parameter_size_b": 0.5,
  "format": "GGUF",
  "quantization": "Q4_K_M",
  "download_size_mb": 390,
  "min_ram_gb": 3,
  "download_url":
      "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",

  // --- RECOMMENDED ADDITIONAL FIELDS ---
  "description":
      "Ultra-lightweight model ideal for quick text tasks, basic chat, and low-end mobile devices.",
  "context_length": 32768, // Max tokens (input + output) the model can handle
  "categories": ["chat", "code", "general"], // Helps filter models in UI
  "languages": ["en", "zh"], // Supported languages
  "capabilities": {
    "function_calling": true, // Tool/API calling support
    "vision": false, // Multimodal (image input) support
    "system_prompt": true, // Supports custom system prompts
  },
  "recommended_settings": {
    "temperature": 0.7, // Ideal sampling temperature
    "top_p": 0.9,
    "stop_tokens": ["<|im_end|>"], // Crucial for stopping output correctly
  },
  "license": "apache-2.0", // Open source / commercial usage license
  "icon_url": "https://...", // UI display avatar/icon
  "recommended_hardware":
      "mobile", // "mobile", "mid_range_laptop", "gpu_required"
};
