/*
 * /imports/common/init/accounts-ui.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AccountsUI } from 'meteor/pwix:accounts-ui';

// configure the AccountsUI package for production
AccountsUI.configure({
    //coloredBorders: AccountsUI.C.Colored.NEVER,
    //onEmailVerifiedBeforeFn: null,
    //onEmailVerifiedBox: true,
    //onEmailVerifiedBoxCb: null,
    //onEmailVerifiedBoxMessage: { namespace: I18N, i18n: 'user.verify_text' },
    //onEmailVerifiedBoxTitle: { namespace: I18N, i18n: 'user.verify_title' },
    //passwordTwice: true,
    //resetPasswordTwice: _passwordTwice,
    //resetPwdTextOne: { namespace: I18N, i18n: 'reset_pwd.textOne' },
    //resetPwdTextTwo: '',
    //verbosity: AccountsUI.C.Verbose.CONFIGURE
});
