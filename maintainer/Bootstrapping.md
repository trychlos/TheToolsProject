# TheToolsProject - a work paradigm for IT productions

## Bootstrapping

First, we want our commands be in the `PATH` so that the user is able to enter `$ ttp.sh` at the prompt and get its results.

So we need at least a `PATH` to fulfill this point.

Second, we want be able to manage several layers of __TheToolsProject__, each of them maybe uncomplete, say one contains only configurations, a second contains some verbs in development state, a third an old version, a fourth a more up-to-date version.

And third, we want manage these layers through drop-in directories which address them.

May be `ttp.sh` command auto-discover the rest of the layers ?

Examining the `PATH` to search for all __TTP__ trees would be a solution, but requires the command to embed the needed code. This has the drawback of duplicating this code in each and every command, thus making the maintenance much more difficult.

To make the maintenance as easy as possible, we so prefer use `FPATH` (in shell-based __TTP__, resp. `PERL5LIB` in perl-based __TTP__).

__Setup these two variables so require a bootstrap process.__

## TTP_ROOTS vs ttp_roots variable

OK: bootstrapping process discovers each layer of __TTP__ trees, and set the `PATH` and `FPATH` (resp. `PERL5LIB`) variables.

The list of these layers is needed in __TTP__ each time we want access a configured variable. Alternative is:

- either take advantage of bootstap process, and keep a `TTP_ROOTS` environment variable with every layer
- or rebuild on each command execution an internal ttp_roots variable.

- `TTP_ROOTS`

    - Pro:

        - work is done once in bootstrap process
        - the list of drop-in directories can be overriden by the site integrator

    - Con:

        - an additional environment variable

- `ttp_roots`

    - Pro:

        - no additional environment variable

    - Con:

        - each command must start with a full discover of each __TTP__ layer
        - this late discover cannot consider a change of drop-in directories list by the site integrator

Because v4 introduces the possibility for the integrator to override the list of drop-in directories, then we have to stuck with the `TTP_ROOTS` environment variable.
