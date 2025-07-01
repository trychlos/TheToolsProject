/*
 * /imports/common/init/startup-app-admin.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { SAA } from 'meteor/pwix:startup-app-admin';

SAA.configure({
    adminRole: Meteor.APP.C.appAdmin,
    verbosity: SAA.C.Verbose.CONFIGURE | SAA.C.Verbose.COUNTS,
    //verbosity: Package['pwix:startup-app-admin'].SAA.C.Verbose.CONFIGURE
});
