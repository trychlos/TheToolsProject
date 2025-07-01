/*
 * /imports/common/init/tabular.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Tabular } from 'meteor/pwix:tabular';

Tabular.configure({
    hideDisabled: false
    //verbosity: Tabular.C.Verbose.CONFIGURE
});
