if (require.extensions['.coffee']) {
  module.exports = exports = require('./lib/index.js');
} else {
  module.exports = exports = require('./out/release/lib/index.js');
}
