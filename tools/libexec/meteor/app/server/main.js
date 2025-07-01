/*
 * /server/main.js
 *
 * This is the main entry point of the server-side application.
 * Startup process:
 *
 * /server/main.js (this file, addressed by package.json)
 *  |
 *  +- /imports/server/init/index.js
 *      |
 *      +- /imports/common/init/index.js
 *      |   |
 *      |   +- ... import global common libraries and definitions
 *      |
 *      +- ... import global server libraries and definitions
 */

import '/imports/server/init/index.js';
