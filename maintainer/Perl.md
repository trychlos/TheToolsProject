# The Tools Project - Tools System and Working Paradigm for IT Production

## Identifying the Perl modules to be installed

```sh
$ find . -type f -name '*.p?' -exec grep -E '^use ' {} \; | awk '{ print $2 }' | grep -vE 'TTP|base|constant|if|open|overload|strict|warnings' | sed -e 's|;\s*$||' | sort -u | while read mod; do echo -n "testing $mod "; perl -e "use $mod;" 2>/dev/null && echo "OK" || echo "NOT OK"; done

```

Email::Sender::Transport::SMTP -> Email::Sender

MSWin32:
    Win32::OLE
    Win32::Console::ANSI
    Win32::SqlServer
