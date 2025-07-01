/*
 * /imports/common/init/env-settings-ext.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { EnvSettingsExt } from 'meteor/pwix:env-settings-ext';

EnvSettingsExt.configure({
    environmentsKeys: [ Meteor.APP.C.appName, 'environments' ],
    //environmentsKeys: null,
    verbosity: EnvSettingsExt.C.Verbose.CONFIGURE | EnvSettingsExt.C.Verbose.SETTINGS
    //verbosity: EnvSettingsExt.C.Verbose.CONFIGURE
});
