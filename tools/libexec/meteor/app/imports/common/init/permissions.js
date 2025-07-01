/*
 * /imports/common/init/permissions.js
 *
 * Manage the permissions of a user.
 * 
 * Permissions are managed per task.
 * For each terminal node, the permission can be specified as: 
 * - an async function with proto: async fn( user<String|Object> ): Boolean
 * - a role name or a list of role names which are or-ed
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Permissions } from 'meteor/pwix:permissions';
//import { Roles } from 'meteor/pwix:roles';

Permissions.configure({
    allowedIfTaskNotFound: false,
    //allowedIfTaskNotFound: true,
    //warnIfTaskNotFound: true,
    verbosity: Permissions.C.Verbose.CONFIGURE | Permissions.C.Verbose.NOT_ALLOWED
    //verbosity: Permissions.C.Verbose.CONFIGURE
});

// Define here permissions as an any-deep object where terminal nodes are async functions
// e.g.:
//  Permissions.set({
//      feat: {
//          authorizations: {
//              async create( user, scope, opts={} ){
//                  return user ? await Roles.userIsInRoles( user, 'AUTHORIZATIONS_MANAGER' ) || await Roles.userIsInRoles( user, 'SCOPED_AUTHORIZATION_CREATE', { scope: scope }) : false;
//              }
//          }
//      }
//  });

Permissions.set({
});
