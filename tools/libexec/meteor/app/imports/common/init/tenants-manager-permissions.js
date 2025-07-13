/*
 * /imports/common/init/tenants-manager-permissions.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Permissions } from 'meteor/pwix:permissions';
import { Roles } from 'meteor/pwix:roles';
import { TenantsManager } from 'meteor/pwix:tenants-manager';
import { Tracker } from 'meteor/tracker';

Permissions.set({
    pwix: {
        tenants_manager: {
            feat: {
                async create( userId ){
                    console.warn( 'pwix.tenants_manager.feat.new: this placeholder should be updated' );
                    //return await Roles.userIsInRoles( userId, 'TENANT_CREATE' );
                    return true;
                },
                async delete( userId, item ){
                    console.warn( 'pwix.tenants_manager.feat.delete: this placeholder should be updated' );
                    //return await Roles.userIsInRoles( userId, 'TENANT_DELETE' ) || await Roles.userIsInRoles( userId, 'SCOPED_TENANT_MANAGER', { scope: entity });
                    return true;
                },
                async edit( userId, item ){
                    console.warn( 'pwix.tenants_manager.feat.edit: this placeholder should be updated' );
                    //return await Roles.userIsInRoles( userId, 'TENANT_EDIT' );
                    return true;
                },
                async list( userId, selector ){
                    console.warn( 'pwix.tenants_manager.feat.list: this placeholder should be updated' );
                    //return userId !== null;
                    return true;
                }
            }
        }
    }
});
