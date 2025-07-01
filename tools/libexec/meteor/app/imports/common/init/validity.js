/*
 * /imports/common/init/validity.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Validity } from 'meteor/pwix:validity';

Validity.configure({
    //effectEnd: 'effectEnd',
    //effectStart: 'effectStart',
    //verbosity: Validity.C.Verbose.CONFIGURE
});
