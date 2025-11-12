clean:
	flutter clean
	flutter pub get

install -ios-release: clean
	flutter build ipa --export-method development \
		--dart-define=ADMOB_APP_ID=ca-app-pub-1679051359335856~1094547017 \
		--dart-define=ADMOB_BANNER_IOS=ca-app-pub-1679051359335856/4194550743
	flutter install --use-application-binary=build/ios/ipa/SwingGroove\ Golf.ipa

build-ipa: clean
	flutter build ipa --export-method app-store \
		--dart-define=ADMOB_APP_ID=ca-app-pub-1679051359335856~1094547017 \
		--dart-define=ADMOB_BANNER_IOS=ca-app-pub-1679051359335856/4194550743