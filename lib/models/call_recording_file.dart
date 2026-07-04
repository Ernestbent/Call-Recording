class CallRecordingFile {
  static final RegExp _fileNameTimestampRegex = RegExp(
    r'(?<!\d)(\d{14})(?!\d)',
  );

  final String filePath;
  final String fileName;
  final DateTime lastModifiedTime;

  const CallRecordingFile({
    required this.filePath,
    required this.fileName,
    required this.lastModifiedTime,
  });

  factory CallRecordingFile.fromMap(Map<dynamic, dynamic> map) {
    return CallRecordingFile(
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      lastModifiedTime: DateTime.fromMillisecondsSinceEpoch(
        map['lastModifiedTime'] as int,
      ),
    );
  }

  DateTime? get fileNameTimestamp {
    final rawTimestamp = _fileNameTimestampRegex.firstMatch(fileName)?.group(1);
    if (rawTimestamp == null) return null;

    final year = int.tryParse(rawTimestamp.substring(0, 4));
    final month = int.tryParse(rawTimestamp.substring(4, 6));
    final day = int.tryParse(rawTimestamp.substring(6, 8));
    final hour = int.tryParse(rawTimestamp.substring(8, 10));
    final minute = int.tryParse(rawTimestamp.substring(10, 12));
    final second = int.tryParse(rawTimestamp.substring(12, 14));

    if ([year, month, day, hour, minute, second].contains(null)) {
      return null;
    }

    return DateTime(year!, month!, day!, hour!, minute!, second!);
  }

  DateTime get effectiveTimestamp => fileNameTimestamp ?? lastModifiedTime;
}
