/*
 * /imports/common/init/modal.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Modal } from 'meteor/pwix:modal';

Modal.configure({
    closeByBackdrop: false,
    //closeByBackdrop: true,
    contentClassesArray: [
        'modal-white',
        'modal-yellow'
    ],
    //contentClassesArray: null,
    //verbosity: Modal.C.Verbose.CONFIGURE
});
