/*
 * /imports/common/init/display-units.js
 * 
 * DisplayUnit's are defined in common code to be scanned for reserved words.
 * They are nonetheless instanciated in client side only.
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';

AppPages.displayUnitDefs = {
    ... AppPages.displayUnitDefs,
    ... {
    }
};
