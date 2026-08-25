class CallRecordingFile {
  static final RegExp _fileNameTimestampRegex = RegExp(
    r'(?<!\d)(\d{14})(?!\d)',
  );
  static final RegExp _datedFileNameTimestampRegex = RegExp(
    r'(?<!\d)(\d{4})-(\d{2})-(\d{2})_(\d{2})\.(\d{2})\.(\d{2})(?!\d)',
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
    final datedTimestamp = _datedFileNameTimestampRegex.firstMatch(fileName);

    final year = int.tryParse(
      rawTimestamp?.substring(0, 4) ?? datedTimestamp?.group(1) ?? '',
    );
    final month = int.tryParse(
      rawTimestamp?.substring(4, 6) ?? datedTimestamp?.group(2) ?? '',
    );
    final day = int.tryParse(
      rawTimestamp?.substring(6, 8) ?? datedTimestamp?.group(3) ?? '',
    );
    final hour = int.tryParse(
      rawTimestamp?.substring(8, 10) ?? datedTimestamp?.group(4) ?? '',
    );
    final minute = int.tryParse(
      rawTimestamp?.substring(10, 12) ?? datedTimestamp?.group(5) ?? '',
    );
    final second = int.tryParse(
      rawTimestamp?.substring(12, 14) ?? datedTimestamp?.group(6) ?? '',
    );

    if ([year, month, day, hour, minute, second].contains(null)) {
      return null;
    }

    return DateTime(year!, month!, day!, hour!, minute!, second!);
  }

  DateTime get effectiveTimestamp => fileNameTimestamp ?? lastModifiedTime;
}
