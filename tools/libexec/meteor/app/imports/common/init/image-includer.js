/*
 * /imports/common/init/image-includer.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { ImageIncluder } from 'meteor/pwix:image-includer';

ImageIncluder.configure({
    //verbosity: ImageIncluder.C.Verbose.CONFIGURE
});
