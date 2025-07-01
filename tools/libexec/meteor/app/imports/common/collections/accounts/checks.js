/*
 * /import/common/collections/accounts/checks.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { ReactiveVar } from 'meteor/reactive-var';

import { Accounts } from './index.js';

// fields check
//  - value: mandatory, the value to be tested
//  - data: optional, the data passed to Checker instanciation
//    if set the target item as a ReactiveVar, i.e. the item to be updated with this value
//  - opts: an optional behaviour options, with following keys:
//    > update: whether the item be updated with the value, defaults to true
//    > id: the identifier of the edited row when editing an array
// returns a TypedMessage, or an array of TypedMessage, or null

// item is a ReactiveVar which contains the edited record
const _assert_data_itemrv = function( caller, data ){
    assert.ok( data, caller+' data required' );
    assert.ok( data.item, caller+' data.item required' );
    assert.ok( data.item instanceof ReactiveVar, caller+' data.item expected to be a ReactiveVar' );
}

// returns the index of the identified row in the array
const _id2index = function( array, id ){
    for( let i=0 ; i<array.length ; ++i ){
        if( array[i].id === id ){
            return i;
        }
    }
    console.warn( 'id='+id+' not found' );
    return -1;
}

Accounts.checks = {
    // apiAllowed
    async apiAllowed( value, data, opts ){
        _assert_data_itemrv( 'Accounts.checks.apiAllowed()', data );
        const item = data.item.get();
        if( opts.update !== false ){
            item.apiAllowed = value;
        }
        return null;
    }
};
