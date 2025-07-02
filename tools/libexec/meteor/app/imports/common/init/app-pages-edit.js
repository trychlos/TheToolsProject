/*
 * /imports/common/init/app-pages-edit.js
 *
 * AppEdit needs two additional DisplayUnit parameters to manage the display of the edit toggle button and the permissions of the user to actually edit the document:
 * - wantEditionSwitch: whether the edit toggle button must be displayed
 * - wantEditionRoles: whether the user is allowed to edit the current page documents
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPagesEdit } from 'meteor/pwix:app-pages-edit';
import { Permissions } from 'meteor/pwix:permissions';

AppPagesEdit.configure({
    allowFn: Permissions.isAllowed,
    //allowFn: null,
    //collection: 'contents',
    //permission: 'pwix.app_pages_edit.editable',
    //toggleHiddenWhenNotConnected: true,
    //toggleHiddenWhenUnallowed: true,
    //verbosity: AppPagesEdit.C.Verbose.CONFIGURE
});
