/*
 * /imports/common/init/notes.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Notes } from 'meteor/pwix:notes';

Notes.configure({
    //verbosity: Notes.C.Verbose.CONFIGURE
});
