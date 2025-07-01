/*
 * /imports/common/init/app-pages.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';
import { Permissions } from 'meteor/pwix:permissions';
import { Roles } from 'meteor/pwix:roles';

AppPages.configure({
    allowFn: Permissions.isAllowed,
    //allowFn: null,
    classes: [ Meteor.APP.C.layoutTheme, Meteor.APP.C.colorTheme ],
    //classes: [ 't-page' ],
    //menuIcon: 'fa-chevron-right',
    //verbosity: 65535
    //verbosity: AppPages.C.Verbose.CONFIGURE
});

Permissions.set({
    pwix: {
        app_pages: {
            menus: {
            }
        }
    }
});
