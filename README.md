## Rocksteady
#### Drink blazin' electric death, downtime!
Fast, zero-downtime apps for production enviroments. Rocksteady runs your node
app and keeps it running for you. It can reload your app and browser on file
modifications for more productive development and reload on SIGHUP for
zero-downtime app upgrades.

### Installation
```sh
$ npm install -g rocksteady
```

### Usage
Point rocksteady at your node app and off you go. You can use the `rocksteady`:

```sh
$ rocksteady ./my-app.js
```

Or require rocksteady into your project and pass it the path directly:

```javascript
require('rocksteady').run('./app')
```

### CLI
Run `rocksteady -h` for a complete list of options.

    rocksteady server.js [options]

    Options:
      --port             Specify port to listen on.
      --workers          Number of workers to start.
      --restart-cooldown Seconds to wait before respawning workers that die.
      --force-kill       Seconds to wait before killing unresponsive worker.
      --watch            Watch for and reload server/browser on changes.

### API
#### Class: rocksteady.Master
`Master` represents a running app, it is an `EventEmitter`.

#### new rocksteady.Master(serverModule, [options])
- `serverModule` [String] Should be a path to a module (either
JavaScript or CoffeeScript) which exports either a connect/express app or an
instance of `http.Server`
- `options` [Object]
    - `port` [Number] Port to listen on
    - `workers` [Number] Number of workers to fork
    - `forceKillTimeout` [Number] Number of seconds to wait before killing an
      unresponsive worker
    - `socketTimeout` [Number] Number of ms to wait before socket times out
    - `watch` [Boolean] Whether or not to watch for changes and reload
      server/browser.
    - `runAs` [Object]
        - `dropPrivileges` [Boolean] Whether to drop privileges if running as
          root.
        - `gid` [String] gid to change to
        - `uid` [String] uid to change to
    - `setupMaster` [Object] options to pass to `cluster`
    - `logger` [Object] logger to use
