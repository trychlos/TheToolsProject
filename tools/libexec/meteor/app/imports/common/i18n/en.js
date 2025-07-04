/*
 * /imports/i18n/en.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.APP.i18n = {
    ...Meteor.APP.i18n,
    ...{
        en: {
            accounts: {
                edit: {
                    api_allowed_label: 'Is REST API allowed: ',
                    api_last_label: 'Last REST API connection: ',
                    tab_title: 'Application'
                },
                fieldset: {
                    api_allowed_dt_title: 'Is REST API allowed',
                    api_connection_dt_title: 'Last REST API connection'
                }
            },
            app: {
                label: 'MyApplication AppLabel'
            }
        }
    }
};
