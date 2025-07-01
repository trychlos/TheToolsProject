/*
 * /imports/common/classes/display-unit.class.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';

export class DisplayUnit extends AppPages.DisplayUnit {

    // static data

    // static methods

    // private data

    // private methods

    // public data

    /**
     * Constructor
     * @param {Object} o an optional parameters object
     * @returns {DisplayUnit} this instance
     */
    constructor(){
        super( ...arguments );
        return this;
    }
}

AppPages.DisplayUnit = DisplayUnit;
