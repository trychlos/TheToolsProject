/*
 * /imports/common/init/index.js
 *
 * Imported both from the client and the server, this is our first executed code, and is common to the two sides.
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Meteor } from 'meteor/meteor';

import '../classes/display-set.class.js';
import '../classes/display-unit.class.js';
import '../classes/run-context.class.js';

if( false ){
    //require( '@vestergaard-company/js-mixin/package.json' );
}

import './constants.js';
import './i18n.js';
import './permissions.js';
//
import './accounts-base.js';
import './accounts-hub.js';
import './accounts-manager.js';
//_import './accounts-manager-accounts.js';
//_import './accounts-manager-permissions.js';
import './accounts-ui.js';
import './app-pages.js';
import './app-pages-edit.js';
import './app-pages-i18n.js';
//_import './assistant.js';
import './collection2.js';
//_import './collections-get.js';
import './cookie-manager.js';
import './core-app.js';
//_import './date.js';
//_import './date-input.js';
import './display-unit-defs.js';
import './env-settings.js';
import './env-settings-ext.js';
import './field.js';
import './forms.js';
import './image-includer.js';
import './modal.js';
import './modal-info.js';
import './notes.js';
//_import './providers.js';
//_import './reserved-words.js';
import './roles.js';
import './startup-app-admin.js';
import './tabbed.js';
//_import './tables.js';
import './tabular.js';
import './tenants-manager.js';
import './tolert.js';
import './ui-layout.js';
import './validity.js';
