/*
 * /imports/common/init/core-app.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { CoreApp } from 'meteor/pwix:core-app';

CoreApp.configure({
    appName: Meteor.APP.C.appName,
    //appName: null,
    //colorTheme: 't-default-color',
    //homeTemplate: 'coreAppHome',
    //layoutTheme: 't-default-layout',
    //rightHeader: [ CoreApp.C.Component.EDIT_SWITCH, CoreApp.C.Component.LANG_SELECT, CoreApp.C.Component.USER_BUTTON, CoreApp.C.Component.MENU_BUTTON ],
    //mainMenu: 'coreAppMenu',
    //routePrefix: '/coreApp',
    //verbosity: CoreApp.C.Verbose.CONFIGURE
});
