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
