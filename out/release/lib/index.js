var Server = require('./server').Server;
var Frame = require('./frame').Frame;
module.exports = exports = {
  createServer : function(http, options, cb) {
    if (typeof options === 'function') {
      cb = options;
      options = null;
    }
    if (!http.__QWS_SERVER) {
      http.__QWS_SERVER = new Server(http, options, cb);
      if (typeof cb === 'function') {
        http.__QWS_SERVER.on('connect', function(msg){
          msg.on('message', msg.__QWS_CB);
        });
      }
    } else {
      http.__QWS_SERVER.addServer(options, cb);
    }
    return http.__QWS_SERVER;
  },
  Server : Server,
  createFrame : function(props) {
    return new Frame(props);
  },
  Frame : Frame
};
