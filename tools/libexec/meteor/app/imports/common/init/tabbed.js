/*
 * /imports/common/init/tabbed.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Tabbed } from 'meteor/pwix:tabbed';

Tabbed.configure({
    //verbosity: Tabular.C.Verbose.CONFIGURE | Tabular.C.Verbose.INSTANCIATIONS
    //verbosity: Tabular.C.Verbose.CONFIGURE
});
