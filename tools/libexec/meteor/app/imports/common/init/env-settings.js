/*
 * /imports/common/init/env-settings.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { EnvSettings } from 'meteor/pwix:env-settings';

EnvSettings.configure({
    verbosity: EnvSettings.C.Verbose.CONFIGURE | EnvSettings.C.Verbose.READY
    //verbosity: EnvSettings.C.Verbose.CONFIGURE
});
