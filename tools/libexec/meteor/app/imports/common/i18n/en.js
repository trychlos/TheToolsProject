/*
 * /imports/i18n/en.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.APP.i18n = {
    ...Meteor.APP.i18n,
    ...{
        en: {
            app: {
                label: 'MyApplication AppLabel'
            },
            header: {
                my_roles: 'My roles'
            }
        }
    }
};
