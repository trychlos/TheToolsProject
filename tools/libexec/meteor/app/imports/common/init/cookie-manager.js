/*
 * /imports/common/init/cookies.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { CookieManager } from 'meteor/pwix:cookie-manager';

CookieManager.configure({
    //consentLifetime: 31536000000,
    //verbosity: CM_VERBOSE_NONE
});
