/*
 * /imports/common/init/tenants-manager.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Permissions } from 'meteor/pwix:permissions';
import { Roles } from 'meteor/pwix:roles';
import { TenantsManager } from 'meteor/pwix:tenants-manager';
import { Tracker } from 'meteor/tracker';

TenantsManager.configure({
    allowFn: Permissions.isAllowed,
    //allowFn: null,
    hideDisabled: false,
    //hideDisabled: true,
    //enabled: true,
    //entityFields: null,
    //recordFields: null,
    //recordFields: null,
    //scopedManagerRole: SCOPED_TENANT_MANAGER,
    //serverAllExtend: null,
    //serverTabularExtend: null,
    //tenantButtons: null,
    //tenantFields: null,
    //verbosity: TenantsManager.C.Verbose.CONFIGURE
});

Permissions.set({
});
