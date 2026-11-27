/// Formats a size given in megabytes (`MiB`) into human-friendly `MB`, `GB`, or `TB`.
String formatSizeMb(num mb) {
  if (mb >= 1024 * 1024) {
    return '${(mb / (1024 * 1024)).toStringAsFixed(2)} TB';
  }
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '${mb.round()} MB';
}

/// Formats a size in megabytes with a multi-part suffix when `partCount > 1`.
String formatSizeWithParts(num mb, {int partCount = 1}) {
  final base = formatSizeMb(mb);
  return partCount > 1 ? '$base ($partCount parts)' : base;
}

/// Formats a byte count into `B`, `KB`, `MB`, `GB`, or `TB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes >= 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

/// Formats a model release timestamp into a compact relative or month label.
String formatRelativeReleaseDate(DateTime date, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(date);
  if (diff.inDays < 1) return 'Today';
  if (diff.inDays == 1) return '1d ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}
