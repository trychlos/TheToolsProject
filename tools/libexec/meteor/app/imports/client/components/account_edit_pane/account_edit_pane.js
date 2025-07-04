/*
 * /imports/client/components/account_edit_pane/account_edit_pane.js
 *
 * A pane to be rendered in a Tabbed to edit application-specific account data.
 *
 * Parms:
 * - item: a ReactiveVar which holds the account object to edit (may be empty, but not null)
 * - isNew: true|false
 * - checker: a ReactiveVar which holds the parent Checker
 * - amInstance: a ReactiveVar which holds the amClass instance
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AccountsManager } from 'meteor/pwix:accounts-manager';
import { Forms } from 'meteor/pwix:forms';
import { pwixI18n } from 'meteor/pwix:i18n';

import './account_edit_pane.html';

Template.account_edit_pane.onCreated( function(){
    const self = this;

    self.APP = {
        fields: {
            apiAllowed: {
                js: '.js-api-allowed',
                form_status: Forms.C.ShowStatus.NONE
            },
            apiConnection: {
                js: '.js-last',
                formTo( $node, item ){
                    return $node.val( item.apiConnection ? strftime( AccountsManager.configure().datetime, item.lastConnection ) : '' );
                }
            }
        },
        // the Form.Checker instance for this panel
        checker: new ReactiveVar( null )
    };
});

Template.account_edit_pane.onRendered( function(){
    const self = this;

    // initialize the Checker for this panel as soon as we get the parent Checker
    self.autorun(() => {
        const amInstance = Template.currentData().amInstance.get();
        const parentChecker = Template.currentData().checker?.get();
        const checker = self.APP.checker.get();
        if( amInstance && parentChecker && !checker ){
            self.APP.checker.set( new Forms.Checker( self, {
                parent: parentChecker,
                panel: new Forms.Panel( self.APP.fields, amInstance.fieldSet()),
                data: {
                    item: Template.currentData().item
                },
                setForm: Template.currentData().item.get()
            }));
        }
    });
});

Template.account_edit_pane.helpers({
    // string translation
    i18n( arg ){
        return pwixI18n.label( I18N, arg.hash.key );
    }
});
