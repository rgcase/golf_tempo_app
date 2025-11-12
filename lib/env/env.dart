class Env {
  static const String adMobAppId = String.fromEnvironment('ADMOB_APP_ID');
  static const String iosBannerUnitId = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
  );
  static const String androidBannerUnitId = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
  );
  static const bool screenshotMode = bool.fromEnvironment(
    'SCREENSHOT_MODE',
    defaultValue: false,
  );
  static const bool adsRemovedOverride = bool.fromEnvironment(
    'ADS_REMOVED_OVERRIDE',
    defaultValue: false,
  );
  static const bool forceTestAds = bool.fromEnvironment(
    'FORCE_TEST_ADS',
    defaultValue: false,
  );
  static const bool forceRealAds = bool.fromEnvironment(
    'FORCE_REAL_ADS',
    defaultValue: false,
  );
  static const bool adsDiag = bool.fromEnvironment(
    'ADS_DIAG',
    defaultValue: false,
  );
  static const bool forceNpa = bool.fromEnvironment(
    'FORCE_NPA',
    defaultValue: false,
  );
  static const bool adsDisableBanners = bool.fromEnvironment(
    'ADS_DISABLE_BANNERS',
    defaultValue: false,
  );
  static const String admobTestDeviceId = String.fromEnvironment(
    'ADMOB_TEST_DEVICE_ID',
  );
  static const String themeModeOverrideRaw = String.fromEnvironment(
    'THEME_MODE_OVERRIDE',
  );
}
