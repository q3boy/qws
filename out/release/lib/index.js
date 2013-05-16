var Server = require('./server').Server;
var Frame = require('./frame').Frame;
module.exports = exports = {
  createServer : function(http, options, cb) {
    if (typeof options === 'function') {
      cb = options;
      options = null;
    }
    var server = new Server(http, options);
    if (typeof cb === 'function') {
      server.on('connect', function(msg){
        msg.on('message', cb);
      });
    }
    return server;
  },
  Server : Server,
  createFrame : function(props) {
    return new Frame(props);
  },
  Frame : Frame
};
