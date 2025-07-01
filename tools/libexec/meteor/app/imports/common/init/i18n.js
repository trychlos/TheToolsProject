/*
 * /imports/common/init/i18n.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { pwixI18n } from 'meteor/pwix:i18n';

// note that imports are executed first, and pwixI18n.namespace() is only called after that
import '../i18n/en.js';
import '../i18n/fr.js';

pwixI18n.configure({
    //dateStyle: 'short',
    //language: PI_DEFAULT_LANGUAGE,
    //managed: [ PI_DEFAULT_LANGUAGE ],
    //storePreferredLanguage: false,
    //timeStyle: 'medium',
    //verbosity: PI_VERBOSE_NONE
});

pwixI18n.namespace({ namespace: I18N, translations: Meteor.APP.i18n });
