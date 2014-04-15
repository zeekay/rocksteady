var http = require('http');
require('coffee-script/register');

module.exports = {
  app:    require('./app'),
  utils:  require('./utils')
}
