/*
 * /imports/i18n/fr.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

Meteor.APP.i18n = {
    ...Meteor.APP.i18n,
    ...{
        fr: {
            accounts: {
                edit: {
                    api_allowed_label: 'API REST autorisée: ',
                    api_last_label: 'Dernière connexion à l\'API REST: ',
                    tab_title: 'Application'
                },
                fieldset: {
                    api_allowed_dt_title: 'API REST autorisée',
                    api_connection_dt_title: 'Dernière connexion à l\'API REST'
                }
            },
            app: {
                label: 'MyApplication AppLabel'
            }
        }
    }
};
