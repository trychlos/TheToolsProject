/*
 * /imports/common/init/accounts-hub.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AccountsHub } from 'meteor/pwix:accounts-hub';
import { EnvSettings } from 'meteor/pwix:env-settings';
import { Tracker } from 'meteor/tracker';

// configure the AccountsHub package for production
AccountsHub.configure({
    //verbosity: AccountsHub.C.Verbose.CONFIGURE
});
