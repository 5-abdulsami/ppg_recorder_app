/// Paths of the files written for one saved recording.
class SavedRecording {
  /// Creates a saved-recording record.
  const SavedRecording({
    required this.directoryPath,
    required this.csvPath,
    required this.metadataPath,
    required this.videoPath,
  });

  /// Folder containing the files.
  final String directoryPath;

  /// PPG signal CSV.
  final String csvPath;

  /// Metadata JSON.
  final String metadataPath;

  /// Recorded video (MP4).
  final String videoPath;

  /// All files, in share order.
  List<String> get allPaths => [csvPath, metadataPath, videoPath];
}
