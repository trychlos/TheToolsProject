/*
 * /imports/common/init/forms.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Forms } from 'meteor/pwix:forms';

Forms.configure({
    //showStatusOverridable: true,
    //fieldStatusShow: Forms.C.ShowStatus.INDICATOR,   // Forms.C.ShowStatus.BOOTSTRAP Forms.C.ShowStatus.NONE
    //fieldTypeShow: true,
    //verbosity: Forms.C.Verbose.CONFIGURE
});
