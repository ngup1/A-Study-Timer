# Study Timer

A minimal macOS menu-bar timer with a seven-segment display. Timer, Pomodoro and Stopwatch modes.

Requires macOS 13+ on Apple Silicon.

## Install

Download [`dist/StudyTimer.zip`](dist/StudyTimer.zip), unzip, and move `StudyTimer.app` to Applications.

The app isn't notarized, so on first launch right-click it → **Open**, or run:

```sh
xattr -cr /Applications/StudyTimer.app
```

## Build

```sh
./build.sh install
```

## License

[MIT](LICENSE)
