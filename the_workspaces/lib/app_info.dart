class AppInfo {
  final String name;
  final String exec;
  final String? iconPath;
  final bool isSvg;

  AppInfo({
    required this.name,
    required this.exec,
    this.iconPath,
    this.isSvg = false,
  });
}
