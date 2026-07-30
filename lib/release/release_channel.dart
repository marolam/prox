enum ProxReleaseChannel {
  tester,
  staging,
  prod,
}

class ReleaseChannel {
  ReleaseChannel._();

  static const String _raw =
      String.fromEnvironment("PROX_RELEASE_CHANNEL", defaultValue: "tester");

  static ProxReleaseChannel get current {
    switch (_raw.trim().toLowerCase()) {
      case "prod":
      case "production":
        return ProxReleaseChannel.prod;
      case "staging":
        return ProxReleaseChannel.staging;
      default:
        return ProxReleaseChannel.tester;
    }
  }

  static bool get isProduction => current == ProxReleaseChannel.prod;

  static String get label {
    switch (current) {
      case ProxReleaseChannel.prod:
        return "prod";
      case ProxReleaseChannel.staging:
        return "staging";
      case ProxReleaseChannel.tester:
        return "tester";
    }
  }
}
