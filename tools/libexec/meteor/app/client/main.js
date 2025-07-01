/*
 * /client/main.js
 *
 * This is the main entry point of the client-side application.
 * Startup process:
 *
 * /client/main.js (this file, addressed by package.json)
 *  |
 *  +- /imports/client/init/index.js
 *      |
 *      +- /imports/common/init/index.js
 *      |   |
 *      |   +- ... import global common libraries and definitions
 *      |   |
 *      |   +- Meteor.APP = {}
 *      |
 *      +- ... import global client libraries and definitions
 *      |
 *      +- ./display-units.js                  Define the display units (pages and modals)
 *      +- ./routes.js                         FlowRouter routes
 *
 * Because an empty ('/') route is defined, the corresponding page is displayed as soon as the route exists in the system.
 */

import '/imports/client/init/index.js';
