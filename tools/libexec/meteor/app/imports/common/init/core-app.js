/*
 * /imports/common/init/core-app.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { CoreApp } from 'meteor/pwix:core-app';

CoreApp.configure({
    appName: Meteor.APP.C.appName,
    //appName: null,
    //async appCopyrightTemplate(){ return { template: 'local_copyright' }; },: ,
    //async appHomeTemplate(){ return { template: 'local_home_label' }; },
    //colorTheme: 't-default-color',
    //layoutTheme: 't-default-layout',
    //loginIfNotConnected: false,
    //mainMenu: 'coreAppMenu',
    managedLanguages: Meteor.APP.C.managedLanguages,
    //managedLanguages: null,
    //routePrefix: '/core.app',
    //verbosity: CoreApp.C.Verbose.CONFIGURE
});
