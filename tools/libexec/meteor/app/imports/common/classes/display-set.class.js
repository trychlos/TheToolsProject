/*
 * /imports/common/classes/display-set.class.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';

export class DisplaySet extends AppPages.DisplaySet {

    // static data

    // static methods

    // private data

    // private methods

    // public data

    /**
     * Constructor
     * @param {Object} o an optional parameters object
     * @returns {DisplaySet} this instance
     */
    constructor(){
        super( ...arguments );
        return this;
    }
}

AppPages.DisplaySet = DisplaySet;
