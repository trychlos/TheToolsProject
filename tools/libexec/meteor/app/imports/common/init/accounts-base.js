/*
 * /imports/common/init/accounts-base.js
 *
 * This is the Meteor accounts-base package, it handles the standard 'users' collection.
 * 
 * const VALID_CONFIG_KEYS = [
 *   'sendVerificationEmail',
 *   'forbidClientAccountCreation',
 *   'restrictCreationByEmailDomain',
 *   'loginExpiration',
 *   'loginExpirationInDays',
 *   'oauthSecretKey',
 *   'passwordResetTokenExpirationInDays',
 *   'passwordResetTokenExpiration',
 *   'passwordEnrollTokenExpirationInDays',
 *   'passwordEnrollTokenExpiration',
 *   'ambiguousErrorMessages',
 *   'bcryptRounds',
 *   'defaultFieldSelector',
 *   'collection',
 *   'loginTokenExpirationHours',
 *   'tokenSequenceLength',
 *   'clientStorage',
 *   'ddpUrl',
 *   'connection',
 * ];
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Accounts } from 'meteor/accounts-base';

Accounts.config({
    //passwordResetTokenExpirationInDays: 3
});
