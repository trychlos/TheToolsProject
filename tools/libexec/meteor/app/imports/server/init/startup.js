/*
 * /imports/common/init/startup.js
 *
 * Code executed both on client and server at Meteor startup() time.
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.startup(() => {
    console.debug( '/imports/server/init/startup.js' );
    console.log( 'Meteor.startup(): NODE_ENV=\''+process.env['NODE_ENV']+'\'' );
    console.log( 'Meteor.startup(): APP_ENV=\''+process.env['APP_ENV']+'\'' );
    console.log( 'Meteor.startup(): runtime.env=\''+Meteor.settings.runtime.env+'\'' );
});
