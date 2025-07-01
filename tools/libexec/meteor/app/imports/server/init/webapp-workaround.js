/*
 * /imports/server/init/webapp-workaround.js
 */

import _ from 'lodash';
import { strict as assert } from 'node:assert';

import { WebApp } from 'meteor/webapp';

// returns true if the url has been redirected (so it is no worth to try other redirectors)
const meteorWorkAround = function( url, res ){
    const usedPath = [
        '/images/'
    ];
    let found = false;
    usedPath.every(( path ) => {
        const indexOf = url.indexOf( path );
        //console.debug( 'url', url, 'path', path, 'index', indexOf );
        if( indexOf > 0 ){
            found = true;
            const newurl = path + url.substring( indexOf+path.length );
            console.debug( '(MyApplication) redirecting', url, 'to', newurl );
            res.writeHead( 301, {
                Location: newurl
            });
            res.end();
        }
        return !found;
    });
    return found;
}

// when route='/doc/res', a path like /images/... is transformed by Meteor in /doc/images...
// this is a known Meteor bug #12524 (still opened as of 06/2025 - https://github.com/meteor/meteor/issues/12524)
WebApp.handlers.use( function( req, res, next ){
    //console.debug( req.url );
    if( !meteorWorkAround( req.url, res )){
        next();
    }
});
