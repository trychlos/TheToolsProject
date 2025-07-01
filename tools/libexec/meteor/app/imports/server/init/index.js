/*
 * /imports/server/init/index.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import '/imports/common/init/index.js';

import './collections.js';
import './email_templates.js';
import './startup.js';
//import './tables.js';
//import './tenants-manager.js';
//import './webapp-express.js';   // must be before other webapp's
//import './webapp-rest-global.js';
//import './webapp-rest-scoped.js';
import './webapp-workaround.js';
