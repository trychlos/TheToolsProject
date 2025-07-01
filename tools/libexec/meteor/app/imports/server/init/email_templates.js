/*
 * /imports/server/init/email_templates.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Accounts } from 'meteor/accounts-base';
import { EnvSettings } from 'meteor/pwix:env-settings';
import { Tracker } from 'meteor/tracker';

Tracker.autorun(() => {
    if( EnvSettings.ready()){
        if( Accounts.emailTemplates ){
            EnvSettings.environmentSettings()
                .then(( settings ) => {
                    if( settings ){
                        Accounts.emailTemplates.from = settings.sender || 'NoReply <noreply@localhost';
                    }
                    Accounts.emailTemplates.siteName = Meteor.APP.name;
                });
        }
    }
});
