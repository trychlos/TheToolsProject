/*
 * /imports/common/init/collections-get.js
 *
 * Used when managing dynamic publications to dynamic collections, typically for example for a tabular display of a collection with validities...
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { Mongo } from 'meteor/mongo';

Meteor.APP.Collections = {
    managed: {},

    /**
     * returns the named collection, maybe instanciating it if needed
     * @param {String} name
     * @returns {Mongo.Collection}
     */
    get( name ){
        const side = Meteor.isClient ? 'client' : 'server';
        let res = this.managed[name] && this.managed[name][side];
        if( !res ){
            this.managed[name] = this.managed[name] || {};
            this.managed[name][side] = new Mongo.Collection( name );
            res = this.managed[name][side];
        }
        return res;
    }
};
