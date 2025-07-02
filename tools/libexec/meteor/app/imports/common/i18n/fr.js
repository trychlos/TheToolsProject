/*
 * /imports/i18n/fr.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.APP.i18n = {
    ...Meteor.APP.i18n,
    ...{
        fr: {
            app: {
                label: 'MyApplication AppLabel'
            }
        }
    }
};
