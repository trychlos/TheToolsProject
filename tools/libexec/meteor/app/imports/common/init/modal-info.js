/*
 * /imports/common/init/modal-info.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { ModalInfo } from 'meteor/pwix:modal-info';

ModalInfo.configure({
    label_zero: '<i>&lt;SAA&gt;</i>',
    //verbosity: ModalInfo.C.Verbose.CONFIGURE
});
