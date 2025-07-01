/*
 * /imports/common/init/roles.js
 *
 *  Defines the roles used in the application, along with their hierarchy.
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Permissions } from 'meteor/pwix:permissions';
import { Roles } from 'meteor/pwix:roles';

const roles = {
    hierarchy: [
        {
            // appAdmin may do anything in the application
            name: Meteor.APP.C.appAdmin,
            children: [
                {
                    // edit the inline documents
                    name: 'APP_EDITOR'
                },
                {
                    // manage application user accounts
                    name: 'ACCOUNTS_MANAGER'
                },
                {
                    // manage organizations
                    name: 'TENANTS_MANAGER'
                },
                {
                    // manage the authorizations for all organizations (e.g. a support service)
                    name: 'AUTHORIZATIONS_MANAGER'
                },
                {
                    // manage one or several organization (scoped role)
                    name: 'SCOPED_TENANT_MANAGER',
                    scoped: true,
                    children: [
                        {
                            name: 'SCOPED_AUTHORIZATIONS_MANAGER'
                        },
                        {
                            name: 'SCOPED_EDITOR'
                        }
                    ]
                }
            ]
        }
    ]
};

Roles.configure({
    allowFn: Permissions.isAllowed,
    //allowFn: null,
    //maintainHierarchy: true,
    roles: roles,
    //roles: null,
    //scopeLabelFn: null,
    //scopesFn: null,
    scopesPub: 'pwix_tenants_manager_tenants_get_scopes',
    //scopesPub: null,
    verbosity: Roles.C.Verbose.CONFIGURE | Roles.C.Verbose.READY | Roles.C.Verbose.CURRENT
    //verbosity: Roles.C.Verbose.CONFIGURE
});

Permissions.set( Roles.suggestedPermissions());
