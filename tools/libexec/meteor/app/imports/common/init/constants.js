/*
 * /imports/common/init/constants.js
 */

//import _ from 'lodash';
//import { strict as assert } from 'node:assert';

Meteor.APP.C = {

    // the application name
    appName: 'MyApplication',

    // the app administrator role
    appAdmin: 'APP_ADMINISTRATOR',

    managedLanguages: [
        'en',
        'fr'
    ],

    // display
    colorTheme: 't-default-color',
    layoutTheme: 't-default-layout',
    useBootstrapValidationClasses: true,
};

I18N = 'MyApplication.Internationalization';
