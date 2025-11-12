clean:
	flutter clean
	flutter pub get

install-ios-release: clean
	test -f .env.json || (echo "Missing .env.json. Copy env.example.json to .env.json and fill values." && exit 1)
	flutter build ipa --export-method development \
		--dart-define-from-file=.env.json
	flutter install --use-application-binary=build/ios/ipa/SwingGroove\ Golf.ipa

build-ipa: clean
	test -f .env.json || (echo "Missing .env.json. Copy env.example.json to .env.json and fill values." && exit 1)
	flutter build ipa --export-method app-store \
		--dart-define-from-file=.env.json