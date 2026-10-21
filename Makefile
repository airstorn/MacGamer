.PHONY: app run test cli

app:
	tools/package-app.sh

run: app
	open "$(HOME)/Applications/MacGamer.app"

test:
	swift test

cli:
	swift build --product macgamer
