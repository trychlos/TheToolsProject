/*
 * /imports/common/init/accounts-manager-users.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';
import strftime from 'strftime';

import { AccountsManager } from 'meteor/pwix:accounts-manager';
import { EnvSettings } from 'meteor/pwix:env-settings';
import { Permissions } from 'meteor/pwix:permissions';
import { pwixI18n } from 'meteor/pwix:i18n';

import { Accounts } from '../collections/accounts/index.js';

let _args = {
    /* from AccountsHub.ahClass
    */
    name: 'users',
    //haveEmailAddress: AccountsHub.C.Identifier.MANDATORY,
    //haveUsername: AccountsHub.C.Identifier.NONE,
    //informWrongEmail: AccountsHub.C.WrongEmail.ERROR,
    //onSignin: Meteor.loginWithPassword,
    //passwordLength: 10
    //passwordStrength: AccountsHub.C.Password.STRONG,
    //preferredLabel: AccountsHub.C.PreferredLabel.EMAIL_ADDRESS,
    //sendVerificationEmail: true,
    //serverAllExtend: null,
    //usernameLength: 6,
    //collection: // same than name,

    /* from AccountsManager.amClass
    */
    //baseFieldset: // default fields definitions
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
    //additionalFieldset: null,
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
    //additionalTabs: null,
    allowFn: Permissions.isAllowed,
    //classes: null,
    //clientNewFn: AccountsUI.Features.createUser, // for 'users' instance
    //clientNewArgs: null,
    //clientUpdateFn: null,
    //clientUpdateArgs: null,
    //closeAfterNew: true,
    //feedNow: true,
    //haveIdent: true,
    //haveRoles: true,
    hideDisabled: false,
    //hideDisabled: true,
    //preNewFn: null,
    //postNewFn: null,
    //preUpdateFn: null,
    //postUpdateFn: null,
    //scopesFn: null,
    //serverTabularExtend: null,
    //tabularActiveCheckboxes: false,
    //tabularFieldsDef: null,
    //verbosity: AccountsManager.C.Verbose.CONFIGURE,
    //withGlobals: true,
    //withScoped: true
};

// let the 'users' amClass be configured by the settings
Tracker.autorun(() => {
    if( EnvSettings.ready()){
        EnvSettings.environmentSettings()
            .then(( settings ) => {
                if( settings ){
                    [ 'AccountsHub', 'AccountsManager' ].forEach(( pck ) => {
                        if( settings[pck] && settings[pck].users ){
                            Object.keys( settings[pck].users ).forEach(( key ) => {
                                _args[key] = settings[pck].users[key];
                            });
                        }
                    });
                    // no need to keep the instance somewhere as it will be addressable as AccountsHub.getInstance( 'users' )
                    new AccountsManager.amClass( _args );
                }
            });
    }
});
