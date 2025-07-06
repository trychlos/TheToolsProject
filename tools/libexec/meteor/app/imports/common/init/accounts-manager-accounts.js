/*
 * /imports/common/init/accounts-manager-accounts.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';
import strftime from 'strftime';

import { AccountsManager } from 'meteor/pwix:accounts-manager';
import { Permissions } from 'meteor/pwix:permissions';
import { pwixI18n } from 'meteor/pwix:i18n';

import { Accounts } from '../collections/accounts/index.js';

// no need to keep the instance somewhere as it will be addressable as AccountsHub.instances[name]
new AccountsManager.amClass({
    name: 'users',
    additionalFieldset: {
        before: 'adminNotes',
        fields: [{
            // whether the account is allowed to use the REST API
            name: 'apiAllowed',
            type: Boolean,
            defaultValue: false,
            dt_title: pwixI18n.label( I18N, 'accounts.fieldset.api_allowed_dt_title' ),
            dt_template: 'dt_checkbox',
            dt_className: 'dt-center',
            dt_templateContext( rowData ){
                return {
                    item: rowData,
                    readonly: true,
                    enabled: true
                };
            },
            form_status: false,
            form_check: Accounts.checks.apiAllowed
        },{
            // last API connection
            name: 'apiConnection',
            type: Date,
            optional: true,
            dt_title: pwixI18n.label( I18N, 'accounts.fieldset.api_connection_dt_title' ),
            dt_render( data, type, rowData ){
                return rowData.apiConnection ? strftime( AccountsManager.configure().datetime, rowData.lastConnection ) : '';
            },
            dt_className: 'dt-center',
            form_status: false,
            form_check: false
        }]
    },
    additionalTabs: [
        {
            before: 'account_roles_tab',
            tabs: [
                {
                    tabid: 'app_account_tab',
                    paneid: 'app_account_pane',
                    navLabel: pwixI18n.label( I18N, 'accounts.edit.tab_title' ),
                    paneTemplate: 'account_edit_pane'
                }
            ]
        }
    ],
    allowFn: Permissions.isAllowed,
    //closeAfterNew: true,
    hideDisabled: false,
    //hideDisabled: true,
    //tabularActiveCheckboxes: false,
    //verbosity: AccountsManager.C.Verbose.CONFIGURE
});
