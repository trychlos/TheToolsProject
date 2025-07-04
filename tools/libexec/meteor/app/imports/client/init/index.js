/*
 * /imports/client/init/index.js
 *
 *  Client-only UI init code.
 *  All third-party imports go here.
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert'; 

import '/imports/common/init/index.js';

import '../components/account_edit_pane/account_edit_pane.js';

import './display-set.js';
import './run-context.js';
import './startup.js';
