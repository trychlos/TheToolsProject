/*
 * /imports/client/init/startup.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.startup(() => {
    console.debug( '/imports/client/init/startup.js' );
    console.log( 'Meteor.startup(): public.runtime.env=\''+Meteor.settings.public.runtime.env+'\'' );
});
