/*
 * /imports/client/init/display-units.js
 * 
 * Instanciate here the DisplayUnit's of the application, and some of their relevant properties.
 * Done at the application level so that all packages may have incremented 'AppPages.displayUnitDefs' at that time
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';

// AppPages.RunContext installs each instance as AppPages.runContext ReactiveVar.
// We reference the instance in Meteor.APP too as a convenience
Meteor.APP.runContext = new AppPages.RunContext();
