/*
 * /imports/common/classes/run-context.class.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { AppPages } from 'meteor/pwix:app-pages';
import { ReactiveVar } from 'meteor/reactive-var';

export class RunContext extends AppPages.RunContext {

    // static data

    // static methods

    // private data

    // the current organization and validity period
    #entity = new ReactiveVar( null );
    #record = new ReactiveVar( null );

    // private methods

    // public data

    /**
     * Constructor
     * @param {Object} o an optional parameters object
     * @returns {RunContext} this instance
     */
    constructor(){
        super( ...arguments );
        const self = this;

        return this;
    }

    /**
     * @summary Return the classes to be provided to other display units than the current page
     *  This may come from the application defaults, from the page itself, or from the user preferences
     * @returns {Array} the list of color and layout themes
     */
    pageUIClasses(){
        const page = this.iAppPageableCurrent();
        const colorTheme = page ? page.get( 'colorTheme' ) || Meteor.APP.C.colorTheme : Meteor.APP.C.colorTheme;
        const layoutTheme = page ? page.get( 'layoutTheme' ) || Meteor.APP.C.layoutTheme : Meteor.APP.C.layoutTheme;
        let classesArray = [];
        classesArray.push( colorTheme );
        classesArray.push( layoutTheme );
        return classesArray;
    }
}

AppPages.RunContext = RunContext;
