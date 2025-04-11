# The Tools Project - Tools System and Working Paradigm for IT Production

## Identifying the Perl modules to be installed

```sh
$ find TTP/tools -type f -name '*.p?' -exec grep -E '^use ' {} \; | awk '{ print $2 }' | grep -vE 'TTP|base|constant|if|open|overload|strict|warnings' | sed -e 's|;\s*$||' | sort -u | while read mod; do echo -n "testing $mod "; perl -e "use $mod;" 2>/dev/null && echo "OK" || echo "NOT OK"; done

```

Email::Sender::Transport::SMTP -> Email::Sender

MSWin32:
    Win32::OLE
    Win32::Console::ANSI
    Win32::SqlServer

The command below does work but is not enough as:
- we should also take into account the target OS to not try to install e.g. Win32 package on Linux
- some modules are not packages as such e.g. module Email::Sender::Transport::SMTP is packaged in perl-Email-Sender

$ dnf install -y $(find /opt/trychlos.pwi/TTP/tools -type f -name '*.p?' -exec grep -E '^use ' {} \; | awk '{ print $2 }' | grep -vE 'TTP|base|constant|if|open|overload|strict|warnings' | sed -e 's|;\s*$||' | sort -u | while read mod; do echo -n "testing $mod "; perl -e "use $mod;" 2>/dev/null && echo "OK" || echo "NOT OK"; done | grep 'NOT OK' | awk '{ printf( "perl-%s\n", $2 )}' | sed -e 's|::|-|g')

On node93:

No match for argument: perl-Email-Sender-Transport-SMTP
No match for argument: perl-Email-Stuffer
No match for argument: perl-LWP-UserAgent
No match for argument: perl-Proc-Background
No match for argument: perl-Role-Tiny-With
No match for argument: perl-vars-global
No match for argument: perl-Win32-SqlServer

## Used Perl modules

```
    Capture::Tiny
    Carp
    Config
    Data::Dumper
    Data::UUID
    Devel::StackTrace
    Digest::SHA
    Email::Sender::Transport::SMTP
    Email::Stuffer
    File::Copy
    File::Copy::Recursive
    File::Find
    File::Path
    File::Spec
    File::Temp
    Getopt::Long
    HTML::Parser
    IO::Socket::INET
    JSON
    List::Util
    LWP::UserAgent
    Module::Load
    Net::MQTT::Simple
    Path::Tiny
    Proc::Background
    Proc::ProcessTable
    Role::Tiny
    Role::Tiny::With
    Scalar::Util
    Sub::Exporter
    Sys::Hostname
    Term::ANSIColor
    Test::Deep
    Time::HiRes
    Time::Moment
    Try::Tiny
    URI::Escape
    URI::Split
    vars::global

    MSWin32
        Win32::SqlServer
```
