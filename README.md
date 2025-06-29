# Math Game server

I wrote this back when we were trying to help a foster kiddo learn multiplication. Maybe it'll be useful to someone else, but I needed to set this aside to get over the heartbreak. The client code is at https://github.com/jterhorst/Math-Game


## Running the example

Run the app and open http://localhost:8080 in the browser

```sh
swift run App
```

## Dev mode with auto-reload on save

The `swift-dev` script auto-reloads open browser tabs on source file changes.

It is using [watchexec](https://github.com/watchexec/watchexec) and [browsersync](https://browsersync.io/).

### Install required tools

Use homebrew and npm to install the following (tested on macOS):

```sh
npm install -g browser-sync
brew install watchexec
```

### Run app in watch-mode

This will watch all swift files in the demo package, build on-demand, and re-sync the browser page

```sh
./swift-dev
```

### Game preview

http://localhost:8080/game

