/*
 * /imports/common/init/accounts-manager-permissions.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Permissions } from 'meteor/pwix:permissions';
import { Roles } from 'meteor/pwix:roles';

Permissions.set({
    pwix: {
        accounts_manager: {
            // manage CRUD operations
            // args:
            //  - amInstance: the amClass instance, always present
            //  - scope: optional
            feat: {
                async create( userId, args ){
                    console.warn( 'pwix.accounts_manager.feat.create: this placeholder should be updated' );
                    if( userId ){
                        const instanceName = args.amInstance.name();
                        if( instanceName === 'users' ){
                            return await Roles.userIsInRoles( userId, 'ACCOUNTS_MANAGER' ) || ( args.scope && await Roles.userIsInRoles( userId, 'SCOPED_ACCOUNTS_MANAGER', { scope: args.scope }));
                        }
                    }
                    return false;
                },
                // user cannot delete itself
                //  user cannot delete an account which have higher roles, but can who has equal roles (so an admin may delete another admin)
                // args:
                //  - id: the target account identifier
                async delete( userId, args ){
                    console.warn( 'pwix.accounts_manager.feat.delete: this placeholder should be updated' );
                    if( userId ){
                        const compare = await Roles.compareLevels( userId, args.id );
                        if( compare < 0 ){
                            return false;
                        }
                        const instanceName = args.amInstance.name();
                        if( instanceName === 'users' ){
                            return await Roles.userIsInRoles( userId, 'ACCOUNTS_MANAGER' ) || ( args.scope && await Roles.userIsInRoles( userId, 'SCOPED_ACCOUNTS_MANAGER', { scope: args.scope }));
                        }
                    }
                    return false;
                },
                // whether the userId account can edit the user account
                //  user cannot edit an account which have higher roles, but can who has equal roles (so an admin may edit another admin)
                // args:
                //  - id: the target account identifier
                async edit( userId, args ){
                    console.warn( 'pwix.accounts_manager.feat.edit: this placeholder should be updated' );
                    if( userId ){
                        const compare = await Roles.compareLevels( userId, args.id );
                        if( compare < 0 ){
                            return false;
                        }
                        const instanceName = args.amInstance.name();
                        if( instanceName === 'users' ){
                            return await Roles.userIsInRoles( userId, 'ACCOUNTS_MANAGER' ) || ( args.scope && await Roles.userIsInRoles( userId, 'SCOPED_ACCOUNTS_MANAGER', { scope: args.scope }));
                        }
                    }
                    return false;
                },
                // does the user is allowed to get a display of the accounts ?
                // yes if he is a (scoped) accounts manager
                async list( userId, args ){
                    console.warn( 'pwix.accounts_manager.feat.list: this placeholder should be updated' );
                    if( userId ){
                        const instanceName = args.amInstance.name();
                        if( instanceName === 'users' ){
                            return await Roles.userIsInRoles( userId, 'ACCOUNTS_MANAGER' ) || ( args.scope && await Roles.userIsInRoles( userId, 'SCOPED_ACCOUNTS_MANAGER', { scope: args.scope }));
                        }
                    }
                    return false;
                }
            }
        }
    }
});
