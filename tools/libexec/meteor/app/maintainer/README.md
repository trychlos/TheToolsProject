# MyApplication - maintainer/README

## Run

In development environment, should be run with:

```sh
    APP_ENV=dev:0 meteor run
```

## Images

- https://www.svgrepo.com/

- https://feathericons.com/

- https://fontawesome.com/

- https://icons.getbootstrap.com/

- https://ionic.io/ionicons

- https://css.gg/

- https://react-icons.github.io/react-icons/

- https://shields.io/

## nodejs ESM

```sh
    $ meteor --version && meteor node --version
    Meteor 3.3
    v22.16.0
```

### assert

From Meteor as of v3.3.0:

```js
    import assert from 'assert';
```

From [NodeJS](https://nodejs.org/docs/latest-v22.x/api/assert.html#assert):

```js
    import { strict as assert } from 'node:assert';
    import assert from 'node:assert/strict';
```

#### The way chosen here

```js
    import { strict as assert } from 'node:assert';
```

---
P. Wieser
- Last updated on 0000, Jan. 1st
